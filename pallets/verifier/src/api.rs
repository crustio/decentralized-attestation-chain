// Copyright (C) 2019-2021 Crust Network Technologies Ltd.
// This file is part of Crust.

#![cfg_attr(not(feature = "std"), no_std)]
use sp_runtime_interface::runtime_interface;
use sp_std::vec::Vec;

#[cfg(feature = "std")]
extern crate libloading;

#[runtime_interface]
pub trait OvlVerifier {
    fn verify(msg: &Vec<u8>) -> bool {
        let _l = unsafe { libloading::Library::new("./libdcap_quoteprov.so.1").unwrap() };
        return true;
    }
}A