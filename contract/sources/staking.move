module my_addrx::Staking { 
    use std::signer;
    use aptos_framework::object;
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};

    /// Error codes
    const EINSUFFICIENT_STAKE: u64 = 0;
    const EINVALID_UNSTAKE_AMOUNT: u64 = 1;
    const EINVALID_REWARD_AMOUNT: u64 = 2;
    const EINVALID_APY: u64 = 3;
    const EINSUFFICIENT_BALANCE: u64 = 4;

    const VAULT_SEED: vector<u8> = b"VAULT";

    struct StakedBalance has store, key {
        staked_balance: u64,
    }

    struct Vault has key {
        extend_ref: object::ExtendRef,
    }

    fun init_module(sender: &signer) {
        let vault_constructor_ref = &object::create_named_object(sender, VAULT_SEED);
        let vault_signer = &object::generate_signer(vault_constructor_ref);

        move_to(vault_signer, Vault {
            extend_ref: object::generate_extend_ref(vault_constructor_ref),
        });
    }

    // ================================= Entry Functions ================================== //

    public entry fun stake(acc_own: &signer, amount: u64) acquires StakedBalance {
        let from = signer::address_of(acc_own);
        let balance = coin::balance<AptosCoin>(from);
        assert!(balance >= amount, EINSUFFICIENT_BALANCE);

        if(!exists<StakedBalance>(from)) {
            let staked_balance = StakedBalance {
                staked_balance: amount
            };
            move_to(acc_own, staked_balance);
        } else {
            let staked_balance = borrow_global_mut<StakedBalance>(from);
            staked_balance.staked_balance = staked_balance.staked_balance + amount;
        };

        aptos_account::transfer(acc_own, get_vault_addr(), amount);
    }

    public entry fun unstake(acc_own: &signer,amount: u64) acquires StakedBalance, Vault {
        let from = signer::address_of(acc_own);
        let staked_balance = borrow_global_mut<StakedBalance>(from);
        let staked_amount = staked_balance.staked_balance;
        assert!(staked_amount >= amount, EINVALID_UNSTAKE_AMOUNT);
        aptos_account::transfer(&get_vault_signer(), from, amount);
        staked_balance.staked_balance = staked_balance.staked_balance - amount;
    }

    // ================================= View Functions ================================== //

    #[view]
    public fun get_vault_addr(): address {
        object::create_object_address(&@my_addrx, VAULT_SEED)
    }

    #[view]
    public fun get_staked_balance(addr: address): u64 acquires StakedBalance {
        let staked_balance = borrow_global<StakedBalance>(addr);
        staked_balance.staked_balance
    }

    // ================================= Helper functions ================================== //
    fun get_vault_signer(): signer acquires Vault {
        let vault = borrow_global<Vault>(get_vault_addr());
        object::generate_signer_for_extending(&vault.extend_ref)
    }

    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::coin::{BurnCapability, MintCapability};
    #[test_only]
    use aptos_framework::aptos_coin;

    #[test(aptos_framework = @0x1, creator = @my_addrx, alice = @0x3)]
    public entry fun test_staking(aptos_framework: &signer, creator: &signer, alice: &signer) acquires StakedBalance, Vault {
        let (burn_cap, mint_cap) = setup_test(aptos_framework, creator, alice);

        // Alice stakes some tokens
        stake(alice, 500);
        
        // Check that Alice's staked balance is correct
        let alice_resource = borrow_global<StakedBalance>(signer::address_of(alice));
        assert!(alice_resource.staked_balance == 500, 100);

        // // Alice unstakes some tokens
        unstake(alice, 200);

        // Check that Alice's staked balance is correct
        let alice_resource = borrow_global<StakedBalance>(signer::address_of(alice));
        assert!(alice_resource.staked_balance == 300, 100);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, creator = @my_addrx, alice = @0x3)]
    #[expected_failure(abort_code = EINVALID_UNSTAKE_AMOUNT, location = Self)]
    public entry fun test_block_unstake_limit(aptos_framework: &signer, creator: &signer, alice: &signer) acquires StakedBalance, Vault {
        let (burn_cap, mint_cap) = setup_test(aptos_framework, creator, alice);

        // Alice stakes some tokens
        stake(alice, 500);
        
        // Unstake twice up to the limit
        unstake(alice, 400);
        unstake(alice, 100);

        // Unstake more than the limit
        unstake(alice, 100);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, creator = @my_addrx, alice = @0x3)]
    public entry fun test_should_allow_multiple_stakes(aptos_framework: &signer, creator: &signer, alice: &signer) acquires StakedBalance {
        let (burn_cap, mint_cap) = setup_test(aptos_framework, creator, alice);

        // Alice stakes some tokens
        stake(alice, 500);

        // Alice stakes again
        stake(alice, 100);

        // Check that Alice's staked balance is correct
        let alice_resource = borrow_global<StakedBalance>(signer::address_of(alice));
        assert!(alice_resource.staked_balance == 600, 100);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test_only]
    fun setup_test(aptos_framework: &signer, creator: &signer, alice: &signer): (BurnCapability<AptosCoin>, MintCapability<AptosCoin>) {
        account::create_account_for_test(signer::address_of(alice));

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        coin::register<AptosCoin>(alice);
        coin::deposit(signer::address_of(alice), coin::mint(1000000, &mint_cap));  

        init_module(creator);

        (burn_cap, mint_cap)
    }
}


