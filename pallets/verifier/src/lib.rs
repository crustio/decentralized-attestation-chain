// This file is part of Substrate.

// Copyright (C) 2020-2021 Parity Technologies (UK) Ltd.
// SPDX-License-Identifier: Apache-2.0

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! <!-- markdown-link-check-disable -->
//! # Offchain Worker Example Module
//!
//! The Offchain Worker Example: A simple pallet demonstrating
//! concepts, APIs and structures common to most offchain workers.
//!
//! Run `cargo doc --package pallet-example-offchain-worker --open` to view this module's
//! documentation.
//!
//! - [`pallet_example_offchain_worker::Config`](./trait.Config.html)
//! - [`Call`](./enum.Call.html)
//! - [`Module`](./struct.Module.html)
//!
//!
//! ## Overview
//!
//! In this example we are going to build a very simplistic, naive and definitely NOT
//! production-ready oracle for BTC/USD price.
//! Offchain Worker (OCW) will be triggered after every block, fetch the current price
//! and prepare either signed or unsigned transaction to feed the result back on chain.
//! The on-chain logic will simply aggregate the results and store last `64` values to compute
//! the average price.
//! Additional logic in OCW is put in place to prevent spamming the network with both signed
//! and unsigned transactions, and custom `UnsignedValidator` makes sure that there is only
//! one unsigned transaction floating in the network.
#![cfg_attr(not(feature = "std"), no_std)]

use frame_system::{
	self as system,
	ensure_signed,
	ensure_none, ensure_root,
	offchain::{
		AppCrypto, CreateSignedTransaction, SendUnsignedTransaction,
		SignedPayload, SigningTypes, Signer,
	}
};
use frame_support::{
	ensure,
	dispatch::DispatchResult, decl_module, decl_storage, decl_event, decl_error,
	traits::Get,
};
use sp_core::crypto::KeyTypeId;
use sp_runtime::{
	RuntimeDebug,
	offchain::{http, Duration},
	transaction_validity::{
		InvalidTransaction, ValidTransaction, TransactionValidity, TransactionSource,
		TransactionPriority,
	},
};
use codec::{Encode, Decode};
use sp_std::{vec::Vec, vec};
use lite_json::json::JsonValue;

#[cfg(test)]
mod tests;

/// Defines application identifier for crypto keys of this module.
///
/// Every module that deals with signatures needs to declare its unique identifier for
/// its crypto keys.
/// When offchain worker is signing transactions it's going to request keys of type
/// `KeyTypeId` from the keystore and use the ones it finds to sign the transaction.
/// The keys can be inserted manually via RPC (see `author_insertKey`).
pub const KEY_TYPE: KeyTypeId = KeyTypeId(*b"teee");

/// Based on the above `KeyTypeId` we need to generate a pallet-specific crypto type wrappers.
/// We can use from supported crypto kinds (`sr25519`, `ed25519` and `ecdsa`) and augment
/// the types with this pallet-specific identifier.
pub mod crypto {
	use super::KEY_TYPE;
	use sp_runtime::{
		app_crypto::{app_crypto, sr25519},
		traits::Verify,
	};
	use sp_core::sr25519::Signature as Sr25519Signature;
	app_crypto!(sr25519, KEY_TYPE);

	pub struct TestAuthId;
	impl frame_system::offchain::AppCrypto<<Sr25519Signature as Verify>::Signer, Sr25519Signature> for TestAuthId {
		type RuntimeAppPublic = Public;
		type GenericSignature = sp_core::sr25519::Signature;
		type GenericPublic = sp_core::sr25519::Public;
	}
}

/// This pallet's configuration trait
pub trait Config: CreateSignedTransaction<Call<Self>> {
	/// The identifier type for an offchain worker.
	type AuthorityId: AppCrypto<Self::Public, Self::Signature>;

	/// The overarching event type.
	type Event: From<Event<Self>> + Into<<Self as frame_system::Config>::Event>;
	/// The overarching dispatch call type.
	type Call: From<Call<Self>>;

	// Configuration parameters

	/// A grace period after we send transaction.
	///
	/// To avoid sending too many transactions, we only attempt to send one
	/// every `GRACE_PERIOD` blocks. We use Local Storage to coordinate
	/// sending between distinct runs of this offchain worker.
	type VerifyDelay: Get<Self::BlockNumber>;

	/// Number of blocks of cooldown after unsigned transaction is included.
	///
	/// This ensures that we only accept unsigned transactions once, every `UnsignedInterval` blocks.
	type EvidenceLifetime: Get<Self::BlockNumber>;

	/// A configuration for base priority of unsigned transactions.
	///
	/// This is exposed so that it can be tuned for particular runtime, when
	/// multiple pallets send unsigned transactions.
	type UnsignedPriority: Get<TransactionPriority>;
}

/// Payload used by this example crate to hold price
/// data required to submit a transaction.
#[derive(Encode, Decode, Clone, PartialEq, Eq, RuntimeDebug)]
pub struct RegisterPayload<Public, AccountId, BlockNumber> {
	block_number: BlockNumber,
	message: Vec<u8>,
	who: AccountId, 
	public: Public,
}

#[derive(Encode, Decode, Clone, PartialEq, Eq, RuntimeDebug)]
pub struct WrapPublic<Public> {
	public: Public
}

impl<T: SigningTypes> SignedPayload<T> for RegisterPayload<T::Public, T::AccountId, T::BlockNumber> {
	fn public(&self) -> T::Public {
		self.public.clone()
	}
}

decl_storage! {
	trait Store for Module<T: Config> as Verifier {
		WaitingQueue get(fn waiting_queue): double_map hasher(twox_64_concat) T::BlockNumber, hasher(twox_64_concat) T::AccountId => (T::AccountId, Vec<u8>);
		VerificationResults get(fn verification_results): map hasher(twox_64_concat) T::AccountId => Vec<RegisterPayload<T::Public, T::AccountId, T::BlockNumber>>;
		PublicKeys get(fn public_keys): Vec<WrapPublic<T::Public>>;
	}
}

decl_event!(
	/// Events generated by the module.
	pub enum Event<T> where AccountId = <T as frame_system::Config>::AccountId {
		RequestVerification(AccountId, Vec<u8>),
	}
);

decl_error! {
	pub enum Error for Module<T: Config>{
		InvalidSignature,
		InvalidPublic
	}
}

decl_module! {
	/// A public part of the pallet.
	pub struct Module<T: Config> for enum Call where origin: T::Origin {
		fn deposit_event() = default;

		/// Submit new price to the list.
		///
		/// This method is a public function of the module and can be called from within
		/// a transaction. It appends given `price` to current list of prices.
		/// In our example the `offchain worker` will create, sign & submit a transaction that
		/// calls this function passing the price.
		///
		/// The transaction needs to be signed (see `ensure_signed`) check, so that the caller
		/// pays a fee to execute it.
		/// This makes sure that it's not easy (or rather cheap) to attack the chain by submitting
		/// excesive transactions, but note that it doesn't ensure the price oracle is actually
		/// working and receives (and provides) meaningful data.
		/// This example is not focused on correctness of the oracle itself, but rather its
		/// purpose is to showcase offchain worker capabilities.
		#[weight = 1000]
		pub fn request_verification(origin, evidence: Vec<u8>) -> DispatchResult {
			// Retrieve sender of the transaction.
			let who = ensure_signed(origin)?;
			// Add the evidence to the on-chain list.
			let current_block_number = <system::Pallet<T>>::block_number();
			<WaitingQueue<T>>::insert(current_block_number + T::VerifyDelay::get(), who.clone(), (who.clone(), evidence.clone()));
			Self::deposit_event(RawEvent::RequestVerification(who, evidence));
			Ok(())
		}

		#[weight = 1000]
		pub fn submit_result_unsigned_with_signed_payload(
			origin,
			register_payload: RegisterPayload<T::Public, T::AccountId, T::BlockNumber>,
			signature: T::Signature,
		) -> DispatchResult {
			// This ensures that the function can only be called via unsigned transaction.
			ensure_none(origin)?;
			let public_keys = Self::public_keys();
			let wrap_pubkey = WrapPublic {
				public: register_payload.public.clone()
			};
			ensure!(public_keys.contains(&wrap_pubkey), Error::<T>::InvalidPublic);
			let signature_valid = SignedPayload::<T>::verify::<T::AuthorityId>(&register_payload, signature.clone());
			ensure!(signature_valid, Error::<T>::InvalidSignature);
			<VerificationResults<T>>::mutate(register_payload.who.clone(), |results| {
				results.push(register_payload);
			});
			Ok(())
		}

		#[weight = 1000]
		pub fn register_new_pubkey(
			origin,
			pubkey: T::Public,
		) -> DispatchResult {
			// This ensures that the function can only be called via unsigned transaction.
			let _ = ensure_root(origin)?;
			let mut public_keys = Self::public_keys();
			let wrap_pubkey = WrapPublic {
				public: pubkey
			};
			public_keys.push(wrap_pubkey);
			<PublicKeys<T>>::put(public_keys);
			Ok(())
		}

		/// Offchain Worker entry point.
		///
		/// By implementing `fn offchain_worker` within `decl_module!` you declare a new offchain
		/// worker.
		/// This function will be called when the node is fully synced and a new best block is
		/// succesfuly imported.
		/// Note that it's not guaranteed for offchain workers to run on EVERY block, there might
		/// be cases where some blocks are skipped, or for some the worker runs twice (re-orgs),
		/// so the code should be able to handle that.
		/// You can use `Local Storage` API to coordinate runs of the worker.
		fn offchain_worker(block_number: T::BlockNumber) {
			if sp_io::offchain::is_validator() {
				// It's a good idea to add logs to your offchain workers.
				// Using the `frame_support::debug` module you have access to the same API exposed by
				// the `log` crate.
				// Note that having logs compiled to WASM may cause the size of the blob to increase
				// significantly. You can use `RuntimeDebug` custom derive to hide details of the types
				// in WASM or use `debug::native` namespace to produce logs only when the worker is
				// running natively.
				for (who, evidence) in <WaitingQueue<T>>::iter_prefix_values(&block_number) {
					log::info!("Try to verify the evidence!");
					let res = Self::resolve_evidence_and_send_unsigned_for_any_account(who, evidence, block_number);
					if let Err(e) = res {
						log::error!("Error: {}", e);
					}
				}
			}
			else {
				log::trace!(
					target: "verify",
					"Skipping verify at {:?}. Not a validator.",
					block_number,
				)
			}
		}
	}
}

/// Most of the functions are moved outside of the `decl_module!` macro.
///
/// This greatly helps with error messages, as the ones inside the macro
/// can sometimes be hard to debug.
impl<T: Config> Module<T> {
	/// A helper function to fetch the price, sign payload and send an unsigned transaction
	fn resolve_evidence_and_send_unsigned_for_any_account(applier: T::AccountId, evidence: Vec<u8>, block_number: T::BlockNumber) -> Result<(), &'static str> {
		// Make an external HTTP request to fetch the current price.
		// Note this call will block until response is received.
		let message = Self::resolve_evidence(evidence).map_err(|_| "Resolve evidence failed")?;

		// -- Sign using any account
		let (_, result) = Signer::<T, T::AuthorityId>::any_account().send_unsigned_transaction(
			|account| RegisterPayload {
				block_number,
				message: message.clone(),
				who: applier.clone(),
				public: account.public.clone()
			},
			|payload, signature| {
				log::info!("public: {:?}", payload.public.clone());
				Call::submit_result_unsigned_with_signed_payload(payload, signature)
			}
		).ok_or("No local accounts accounts available.")?;
		result.map_err(|()| "Unable to submit transaction")?;

		Ok(())
	}

	/// Fetch current price and return the result in cents.
	fn resolve_evidence(evidence: Vec<u8>) -> Result<Vec<u8>, http::Error> {
		// We want to keep the offchain worker execution time reasonable, so we set a hard-coded
		// deadline to 2s to complete the external call.
		// You can also wait idefinitely for the response, however you may still get a timeout
		// coming from the host machine.
		let deadline = sp_io::offchain::timestamp().add(Duration::from_millis(30_000));
		// Initiate an external HTTP GET request.
		// This is using high-level wrappers from `sp_runtime`, for the low-level calls that
		// you can find in `sp_io`. The API is trying to be similar to `reqwest`, but
		// since we are running in a custom WASM execution environment we can't simply
		// import the library here.
		let pending = http::Request::default()
				.method(http::Method::Post)
				.url("http://localhost:17777/entryNetwork")
				.body(vec![evidence])
				.deadline(deadline)
				.send()
				.map_err(|e| {
					log::error!("Error: {:?}", e);
					http::Error::IoError
				})?;

		// The request is already being processed by the host, we are free to do anything
		// else in the worker (we can send multiple concurrent requests too).
		// At some point however we probably want to check the response though,
		// so we can block current thread and wait for it to finish.
		// Note that since the request is being driven by the host, we don't have to wait
		// for the request to have it complete, we will just not read the response.
		let response = pending.try_wait(deadline)
			.map_err(|_| http::Error::DeadlineReached)??;
		// Let's check the status code before we proceed to reading the response.
		if response.code != 200 {
			log::warn!("Unexpected status code: {}", response.code);
			return Err(http::Error::Unknown);
		}
		log::info!("Got response success!");
		// Next we want to fully read the response body and collect it to a vector of bytes.
		// Note that the return object allows you to read the body in chunks as well
		// with a way to control the deadline.
		let body = response.body().collect::<Vec<u8>>();

		// Create a str slice from the body.
		let body_str = sp_std::str::from_utf8(&body).map_err(|_| {
			log::warn!("No UTF8 body");
			http::Error::Unknown
		})?;

		let message = match Self::parse_result(body_str) {
			Some(message) => Ok(message),
			None => {
				log::warn!("Unable to extract message from the response: {:?}", body_str);
				Err(http::Error::Unknown)
			}
		}?;

		log::info!("Got message: {:?}", message);

		Ok(message)
	}

	/// Parse the price from the given JSON string using `lite-json`.
	///
	/// Returns `None` when parsing failed or `Some(price in cents)` when parsing is successful.
	fn parse_result(result_str: &str) -> Option<Vec<u8>> {
		let val = lite_json::parse_json(result_str);
		let rst = match val.ok()? {
			JsonValue::Object(obj) => {
				let (_, v) = obj.into_iter()
					.find(|(k, _)| k.iter().copied().eq("message".chars()))?;
				match v {
					JsonValue::String(s) => Some(s),
					_ => return None,
				}
			},
			_ => return None,
		};
		match rst{
			Some(result) => Some(result.iter().map(|c| *c as u8).collect::<Vec<_>>()),
			None => None
		}
		
	}

	fn validate_transaction_parameters(
		block_number: &T::BlockNumber,
		who: &T::AccountId
	) -> TransactionValidity {
		// Now let's check if the transaction has any chance to succeed.
		if !<WaitingQueue<T>>::contains_key(block_number, who) {
			return InvalidTransaction::Stale.into();
		}
		// Let's make sure to reject transactions from the future.
		let current_block = <system::Pallet<T>>::block_number();
		if &current_block < block_number {
			return InvalidTransaction::Future.into();
		}

        ensure!(current_block <= *block_number + T::EvidenceLifetime::get(), InvalidTransaction::Custom(ValidityError::OutdatedRequest.into()));

		ValidTransaction::with_tag_prefix("Verifier")
			// We set base priority to 2**20 and hope it's included before any other
			// transactions in the pool. Next we tweak the priority depending on how much
			// it differs from the current average. (the more it differs the more priority it
			// has).
			.priority(T::UnsignedPriority::get())
			// This transaction does not require anything else to go before into the pool.
			// In theory we could require `previous_unsigned_at` transaction to go first,
			// but it's not necessary in our case.
			//.and_requires()
			// We set the `provides` tag to be the same as `next_unsigned_at`. This makes
			// sure only one transaction produced after `next_unsigned_at` will ever
			// get to the transaction pool and will end up in the block.
			// We can still have multiple transactions compete for the same "spot",
			// and the one with higher priority will replace other one in the pool.
			.and_provides(who)
			// The transaction is only valid for next 5 blocks. After that it's
			// going to be revalidated by the pool.
			.longevity(10)
			// It's fine to propagate that transaction to other peers, which means it can be
			// created even by nodes that don't produce blocks.
			// Note that sometimes it's better to keep it for yourself (if you are the block
			// producer), since for instance in some schemes others may copy your solution and
			// claim a reward.
			.propagate(true)
			.build()
	}
}

/// Custom validity errors used in Polkadot while validating transactions.
#[repr(u8)]
pub enum ValidityError {
    /// Outdated Request
    OutdatedRequest = 0
}

impl From<ValidityError> for u8 {
    fn from(err: ValidityError) -> Self {
        err as u8
    }
}

#[allow(deprecated)] // ValidateUnsigned
impl<T: Config> frame_support::unsigned::ValidateUnsigned for Module<T> {
	type Call = Call<T>;

	/// Validate unsigned call to this module.
	///
	/// By default unsigned transactions are disallowed, but implementing the validator
	/// here we make sure that some particular calls (the ones produced by offchain worker)
	/// are being whitelisted and marked as valid.
	fn validate_unsigned(
		_source: TransactionSource,
		call: &Self::Call,
	) -> TransactionValidity {
		// Firstly let's check that we call the right function.
		if let Call::submit_result_unsigned_with_signed_payload(
			ref payload, ref signature
		) = call {
			let signature_valid = SignedPayload::<T>::verify::<T::AuthorityId>(payload, signature.clone());
			if !signature_valid {
				return InvalidTransaction::BadProof.into();
			}
			Self::validate_transaction_parameters(&payload.block_number, &payload.who)
		} else {
			InvalidTransaction::Call.into()
		}
	}
}
