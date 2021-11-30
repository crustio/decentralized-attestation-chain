# tee-alliance
The TEE chain aimed on certificate nodes based on Substrate

# How to join the Tee Auth Chain as a validator
In general, there are the following six steps to be a validator.
1. Follow the ./sgx/README.md to run a dcap service.
2. Follow the ./docker/README.md to run a Tee Auth Chain validator.
3. Use `subkey` to generate a keypair and insert this key into your chain node through chain.insertKey. The type of the key is `teee`
4. Register `teee`'s pubkey into chain through verifier.registerNewPubkey
## Optional
5. Generate new session key and register it. https://substrate.dev/docs/en/knowledgebase/learn-substrate/session-keys#generation-and-use
6. Register yourself as a aura validator through collatorSelection.registerAsCandidate