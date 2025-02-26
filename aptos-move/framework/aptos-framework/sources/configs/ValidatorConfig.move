/// The ValidatorConfig resource holds information about a validator. Information
/// is published and updated by Diem root in a `Self::ValidatorConfig` in preparation for
/// later inclusion (by functions in Reconfiguration) in a `Reconfiguration::Reconfiguration<ValidatorSystem>`
/// struct (the `Self::ValidatorConfig` in a `Reconfiguration::ValidatorInfo` which is a member
/// of the `ValidatorSystem::ValidatorSystem.validators` vector).
module AptosFramework::ValidatorConfig {
    use Std::Capability::Cap;
    use Std::Errors;
    use Std::Option::{Self, Option};
    use Std::Signer;
    use AptosFramework::Timestamp;
    use AptosFramework::ValidatorOperatorConfig;
    use AptosFramework::Signature;
    use AptosFramework::SystemAddresses;

    /// Marker to be stored under @CoreResources during genesis
    struct ValidatorConfigChainMarker<phantom T> has key {}

    struct Config has copy, drop, store {
        consensus_pubkey: vector<u8>,
        validator_network_addresses: vector<u8>,
        fullnode_network_addresses: vector<u8>,
    }

    struct ValidatorConfig has key {
        /// set and rotated by the operator_account
        config: Option<Config>,
        operator_account: Option<address>,
        /// The human readable name of this entity. Immutable.
        human_name: vector<u8>,
    }

    // TODO(valerini): add events here

    /// The `ValidatorConfig` resource was not in the required state
    const EVALIDATOR_CONFIG: u64 = 0;
    /// The sender is not the operator for the specified validator
    const EINVALID_TRANSACTION_SENDER: u64 = 1;
    /// The provided consensus public key is malformed
    const EINVALID_CONSENSUS_KEY: u64 = 2;
    /// Tried to set an account without the correct operator role as a Validator Operator
    const ENOT_A_VALIDATOR_OPERATOR: u64 = 3;
    /// The `ValidatorSetChainMarker` resource was not in the required state
    const ECHAIN_MARKER: u64 = 9;

    public fun initialize<T>(account: &signer) {
        Timestamp::assert_genesis();
        SystemAddresses::assert_core_resource(account);

        assert!(
            !exists<ValidatorConfigChainMarker<T>>(@CoreResources),
            Errors::already_published(ECHAIN_MARKER)
        );
        move_to(account, ValidatorConfigChainMarker<T>{});
    }

    ///////////////////////////////////////////////////////////////////////////
    // Validator setup methods
    ///////////////////////////////////////////////////////////////////////////

    /// Publishes a mostly empty ValidatorConfig struct. Eventually, it
    /// will have critical info such as keys, network addresses for validators,
    /// and the address of the validator operator.
    public fun publish<T>(
        validator_account: &signer,
        human_name: vector<u8>,
        _cap: Cap<T>
    ) {
        Timestamp::assert_operating();
        assert!(
            exists<ValidatorConfigChainMarker<T>>(@CoreResources),
            Errors::not_published(ECHAIN_MARKER)
        );

        assert!(
            !exists<ValidatorConfig>(Signer::address_of(validator_account)),
            Errors::already_published(EVALIDATOR_CONFIG)
        );
        move_to(validator_account, ValidatorConfig {
            config: Option::none(),
            operator_account: Option::none(),
            human_name,
        });
    }

    /// Returns true if a ValidatorConfig resource exists under addr.
    fun exists_config(addr: address): bool {
        exists<ValidatorConfig>(addr)
    }

    ///////////////////////////////////////////////////////////////////////////
    // Rotation methods callable by ValidatorConfig owner
    ///////////////////////////////////////////////////////////////////////////

    /// Sets a new operator account, preserving the old config.
    /// Note: Access control.  No one but the owner of the account may change .operator_account
    public fun set_operator(validator_account: &signer, operator_addr: address) acquires ValidatorConfig {
        assert!(
            ValidatorOperatorConfig::has_validator_operator_config(operator_addr),
            Errors::invalid_argument(ENOT_A_VALIDATOR_OPERATOR)
        );
        let sender = Signer::address_of(validator_account);
        assert!(exists_config(sender), Errors::not_published(EVALIDATOR_CONFIG));
        (borrow_global_mut<ValidatorConfig>(sender)).operator_account = Option::some(operator_addr);
    }

    /// Removes an operator account, setting a corresponding field to Option::none.
    /// The old config is preserved.
    public fun remove_operator(validator_account: &signer) acquires ValidatorConfig {
        let sender = Signer::address_of(validator_account);
        // Config field remains set
        assert!(exists_config(sender), Errors::not_published(EVALIDATOR_CONFIG));
        (borrow_global_mut<ValidatorConfig>(sender)).operator_account = Option::none();
    }

    ///////////////////////////////////////////////////////////////////////////
    // Rotation methods callable by ValidatorConfig.operator_account
    ///////////////////////////////////////////////////////////////////////////

    /// Rotate the config in the validator_account.
    /// Once the config is set, it can not go back to `Option::none` - this is crucial for validity
    /// of the ValidatorSystem's code.
    public fun set_config(
        validator_operator_account: &signer,
        validator_addr: address,
        consensus_pubkey: vector<u8>,
        validator_network_addresses: vector<u8>,
        fullnode_network_addresses: vector<u8>,
    ) acquires ValidatorConfig {
        assert!(
            Signer::address_of(validator_operator_account) == get_operator(validator_addr),
            Errors::invalid_argument(EINVALID_TRANSACTION_SENDER)
        );
        assert!(
            Signature::ed25519_validate_pubkey(copy consensus_pubkey),
            Errors::invalid_argument(EINVALID_CONSENSUS_KEY)
        );
        // TODO(valerini): verify the proof of posession for consensus_pubkey
        assert!(exists_config(validator_addr), Errors::not_published(EVALIDATOR_CONFIG));
        let t_ref = borrow_global_mut<ValidatorConfig>(validator_addr);
        t_ref.config = Option::some(Config {
            consensus_pubkey,
            validator_network_addresses,
            fullnode_network_addresses,
        });
    }

    ///////////////////////////////////////////////////////////////////////////
    // Publicly callable APIs: getters
    ///////////////////////////////////////////////////////////////////////////

    /// Returns true if all of the following is true:
    /// 1) there is a ValidatorConfig resource under the address, and
    /// 2) the config is set, and
    /// we do not require the operator_account to be set to make sure
    /// that if the validator account becomes valid, it stays valid, e.g.
    /// all validators in the Validator Set are valid
    public fun is_valid(addr: address): bool acquires ValidatorConfig {
        exists<ValidatorConfig>(addr) && Option::is_some(&borrow_global<ValidatorConfig>(addr).config)
    }

    /// Get Config
    /// Aborts if there is no ValidatorConfig resource or if its config is empty
    public fun get_config(addr: address): Config acquires ValidatorConfig {
        assert!(exists_config(addr), Errors::not_published(EVALIDATOR_CONFIG));
        let config = &borrow_global<ValidatorConfig>(addr).config;
        assert!(Option::is_some(config), Errors::invalid_argument(EVALIDATOR_CONFIG));
        *Option::borrow(config)
    }

    /// Get validator's account human name
    /// Aborts if there is no ValidatorConfig resource
    public fun get_human_name(addr: address): vector<u8> acquires ValidatorConfig {
        assert!(exists<ValidatorConfig>(addr), Errors::not_published(EVALIDATOR_CONFIG));
        let t_ref = borrow_global<ValidatorConfig>(addr);
        *&t_ref.human_name
    }

    /// Get operator's account
    /// Aborts if there is no ValidatorConfig resource or
    /// if the operator_account is unset
    public fun get_operator(addr: address): address acquires ValidatorConfig {
        assert!(exists<ValidatorConfig>(addr), Errors::not_published(EVALIDATOR_CONFIG));
        let t_ref = borrow_global<ValidatorConfig>(addr);
        assert!(Option::is_some(&t_ref.operator_account), Errors::invalid_argument(EVALIDATOR_CONFIG));
        *Option::borrow(&t_ref.operator_account)
    }

    /// Get consensus_pubkey from Config
    /// Never aborts
    public fun get_consensus_pubkey(config_ref: &Config): &vector<u8> {
        &config_ref.consensus_pubkey
    }

    /// Get validator's network address from Config
    /// Never aborts
    public fun get_validator_network_addresses(config_ref: &Config): &vector<u8> {
        &config_ref.validator_network_addresses
    }
}
