module triplex::vault {

    use std::error::not_implemented;
    use std::option;
    use std::option::none;
    use std::signer::address_of;
    use std::string;
    use std::string::{utf8, String};
    use std::vector::find;
    use aptos_std::math64;
    use aptos_std::math64::pow;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::coin::{paired_metadata, coin_to_fungible_asset};

    use aptos_framework::event::emit;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{Metadata, MintRef, BurnRef, TransferRef, generate_mint_ref, FungibleStore,
        FungibleAsset, create_store
    };
    use aptos_framework::object;
    use aptos_framework::object::{create_named_object, Object, generate_signer, object_from_constructor_ref, ExtendRef,
        create_object_address, object_address, create_object, ConstructorRef
    };
    use aptos_framework::primary_fungible_store;
    use aptos_framework::primary_fungible_store::create_primary_store_enabled_fungible_asset;
    use triplex::move_maker::dao_add_mortgage_assset;
    use triplex::utiles::{ get_collateral_total_amount};
    use triplex::pyth_feed::get_feed_id;
    use pyth::pyth;
    use pyth::price;
    use pyth::i64;
    use pyth::price_identifier;

    use triplex::package_manager::{get_signer, get_control_address};
    #[test_only]
    use aptos_std::debug;
    #[test_only]
    use aptos_std::string_utils;
    #[test_only]
    use triplex::dao::directly_add_mortgage;
    #[test_only]
    use triplex::package_manager;
    #[test_only]
    use triplex::swap::{deploy, print_apt_balance};

    friend triplex::move_maker;
    friend triplex::dao;


    //tpx-usd
    const TPX_SEED : vector<u8> = b"Tpxseed";
    const ICON_URL : vector<u8> = b"https://raw.githubusercontent.com/TriplexProtocol/TriplexMove/4ddaea46ce174b06461d7faf45ca696888d434d0/public/tpxUSD-metal.svg";
    const Project_URL : vector<u8> = b"https://github.com/TriplexProtocol";

    ///E not admin
    const E_not_admin :u64 =1 ;
    ///not support asset
    const E_not_support_asset:u64 =2 ;
    ///Over loan
    const E_over_loan :u64 =3;


    #[event]
    struct Add_collateral has copy,store,drop{
        user:address,
        user_collateral_total_amount:u64,   //all type asset value
        add_collateral_type:String,
        add_collateral_amount:u64
    }
    #[event]
    struct Loan has copy,store,drop{
        user:address,
        user_collateral_total_amount:u64,
        collateral_type:String,
        collateral_amount:u64,
        loan_tpxusd_amount:u64
    }
    #[event]
    struct Withdraw_collateral has copy,store,drop{
        user:address,
        user_collateral_total_amount:u64,
        withdraw_collateral_type:String,
        withdraw_collateral_amount:u64,
        original_collateral_amount:u64
    }
    #[event]
    struct Pay_Loan has copy,store,drop{
        user:address,
        user_collateral_total_amount:u64,
        collateral_type:String,
        collateral_amount:u64,
        loan_tpxusd_amount:u64
    }


    struct Control_ref has key,store{
        obj_meta:Object<Metadata>,
        mint_ref : MintRef,
        burn_ref : BurnRef,
        transfer_ref : TransferRef
    }

    struct Table_of_Vault has key,store{
        accept_asset:SmartTable<Object<Metadata>,Object<Vault>>,
        support_asset_vector:vector<Object<Metadata>>,
        tpxusd:Control_ref,
        fees:u64,
        fees_2:u64
    }
    struct VaultState has key {
        sequence_number: u128,
    }
    struct Vault has key {
        /// Unique identifier for the vault
        id: u128,
        /// Reference to the underlying asset metadata
        asset_metadata: Object<Metadata>,
        /// Reference to the share token metadata
        share_metadata: Object<Metadata>,
        /// Store for the underlying assets
        /// Total number of shares issued
        total_shares: u64,
        asset_store: Object<FungibleStore>,
        /// Extend ref for updating vault state
        extend_ref: ExtendRef,
        /// Mint capability for share tokens
        mint_ref: MintRef,
        /// Burn capability for share tokens
        burn_ref: BurnRef,

        user:SmartTable<address,User>
    }
    struct User has key,store{
        pledge_asset:vector<Pledge>,
    }
    struct Pledge has key,store{
        name:String,
        pledge_asset:Object<Metadata>,
        pledge_asset_amount:u64,
        usd_loan_amount:u64
    }

    public fun get_fungible_store_of_tpxusdt(caller:&signer):Object<FungibleStore> acquires Table_of_Vault {
        let conf = create_named_object(caller,TPX_SEED);
        create_store(&conf,get_tpxusd_metadata())
    }


    #[view]
    public fun get_tpxusd_metadata():Object<Metadata> acquires Table_of_Vault {
        let borrow = borrow_global<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        borrow.tpxusd.obj_meta
    }

    public(friend) fun create_vault(constructor_ref:&ConstructorRef,
                                    asset_metadata: Object<Metadata>,
                                    name: String,
                                    symbol: String,
                                    decimals: u8,
    ):Object<Vault> acquires VaultState {
        //let constructor_ref = object::create_named_object(caller, *string::bytes(&symbol));
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            string::utf8(b""),  // Collection URI
            string::utf8(b""),  // Project URI
        );

        let share_metadata = object::object_from_constructor_ref<Metadata>(constructor_ref);

        // Create store for underlying assets
        let asset_store = fungible_asset::create_store(constructor_ref, asset_metadata);

        // Get mint and burn capabilities
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let extend_ref = object::generate_extend_ref(constructor_ref);

        // Get next vault ID
        let vault_state = borrow_global_mut<VaultState>(@triplex);
        let vault_id = vault_state.sequence_number + 1;
        vault_state.sequence_number = vault_id;

        // Initialize vault config
        let vault_config = Vault {
            id: vault_id,
            asset_metadata,
            share_metadata,
            asset_store,
            total_shares: 0,
            extend_ref,
            mint_ref,
            burn_ref,
            user:smart_table::new()
        };


        move_to(&object::generate_signer(constructor_ref), vault_config);
        object::object_from_constructor_ref(constructor_ref)
    }




    fun ensure_user_on_vault(caller:&signer,in_asset:Object<Metadata>) acquires Table_of_Vault, Vault {
        let borrow = borrow_global_mut<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        assert!(borrow.accept_asset.contains(in_asset)==true ,not_implemented(E_not_support_asset));
        let object_vault =  borrow_global_mut<Vault>(object_address(borrow.accept_asset.borrow(in_asset)));
        let exists = object_vault.user.contains(address_of(caller));
        if(!exists){
            let new_user = User{
                pledge_asset:vector[]
            };
            object_vault.user.add(address_of(caller),new_user);
        }
    }
    fun search(in:&Pledge,name:Object<Metadata>):bool{
        in.pledge_asset == name
    }
    fun change_user_on_vault(caller:&signer,in_amount:u64,loan_amount:u64,pledge_asset:Object<Metadata>) acquires Vault, Table_of_Vault {
        let borrow = borrow_global_mut<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        assert!(borrow.accept_asset.contains(pledge_asset)==true ,not_implemented(E_not_support_asset));
        let object_vault =  borrow_global_mut<Vault>(object_address(borrow.accept_asset.borrow(pledge_asset)));
        let user = object_vault.user.borrow_mut(address_of(caller));
        let (exisits ,index ) = find(&user.pledge_asset,|t| search(t,pledge_asset) );
        if(exisits){
            user.pledge_asset[index].pledge_asset_amount += in_amount;
            user.pledge_asset[index].usd_loan_amount += loan_amount;
        }else{
            let new_pledge = Pledge{
                name:fungible_asset::symbol(pledge_asset),
                pledge_asset,
                pledge_asset_amount:in_amount,
                usd_loan_amount:loan_amount
            };
            user.pledge_asset.push_back(new_pledge);
        };
    }
    fun deposite_in_fa(caller:&signer,in_asset:Object<Metadata>,in_amount:u64) acquires Vault, Table_of_Vault {
        let borrow = borrow_global<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        assert!(borrow.accept_asset.contains(in_asset)==true ,not_implemented(E_not_support_asset));
        let object_vault =  borrow_global<Vault>(object_address(borrow.accept_asset.borrow(in_asset)));
        let in_fa  = primary_fungible_store::withdraw(caller,in_asset,in_amount);
        fungible_asset::deposit(object_vault.asset_store,in_fa);
    }

    public entry fun  pledge_to_get_tpxusd_CO<CoinA>(caller:&signer,in_amount:u64,loan_amount:u64,pyth_price_update: vector<vector<u8>>) acquires Table_of_Vault, Vault {

        let in_asset = (paired_metadata<CoinA>()).destroy_some();
        let in_coin =  coin::withdraw<CoinA>(caller,in_amount);
        let in_fa = coin_to_fungible_asset( in_coin);

        ensure_user_on_vault(caller,in_asset);

        let pyth_fee=pyth::get_update_fee(&pyth_price_update);
        let coins = coin::withdraw<AptosCoin>(caller,pyth_fee);
        pyth::update_price_feeds(pyth_price_update,coins);

        let borrow = borrow_global<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        assert!(borrow.accept_asset.contains(in_asset)==true ,not_implemented(E_not_support_asset));
        let object_vault =  borrow_global<Vault>(object_address(borrow.accept_asset.borrow(in_asset)));

        fungible_asset::deposit(object_vault.asset_store,in_fa);


        let coin_price_identifier =  get_feed_id(in_asset);
        let coin_usd_price_id = price_identifier::from_byte_vec(coin_price_identifier);

        let price =pyth::get_price(coin_usd_price_id);

        let price_positive = i64::get_magnitude_if_positive(&price::get_price(&price)); // This will fail if the price is negative
        let expo_magnitude = i64::get_magnitude_if_negative(&price::get_expo(&price)); // This will fail if the exponent is positive

        let decimals = fungible_asset::decimals(in_asset);
        let octas = pow(10, (decimals as u64));


        let price_in_aptos_coin =  (octas * pow(10, expo_magnitude)) / price_positive;
        assert!(loan_amount <= price_positive,not_implemented(E_over_loan));
        // let out_amount = if(loan_amount != 0){
        //     math64::mul_div(price_in_aptos_coin,loan_amount,100000)
        // }else{
        //     loan_amount
        // };
        let out_amount = loan_amount;


        change_user_on_vault(caller,in_amount,out_amount,in_asset);


        let loan_fa = pledge_to_get_tpxusd(out_amount);

        primary_fungible_store::deposit(address_of(caller),loan_fa);

        emit(Add_collateral{
            user:address_of(caller),
            user_collateral_total_amount:get_collateral_total_amount(caller),
            add_collateral_type:fungible_asset::symbol(in_asset),
            add_collateral_amount:in_amount,
        });
        emit(Loan{
            user:address_of(caller),
            user_collateral_total_amount:get_collateral_total_amount(caller),
            collateral_type:fungible_asset::symbol(in_asset),
            collateral_amount:in_amount,
            loan_tpxusd_amount:out_amount,
        });

    }
    public entry fun  pledge_to_get_tpxusd_FA(caller:&signer,in_asset:Object<Metadata>,in_amount:u64,loan_amount:u64,pyth_price_update: vector<vector<u8>>) acquires Table_of_Vault, Vault {
        ensure_user_on_vault(caller,in_asset);



        let pyth_fee=pyth::get_update_fee(&pyth_price_update);
        let coins = coin::withdraw<AptosCoin>(caller,pyth_fee);
        pyth::update_price_feeds(pyth_price_update,coins);
        deposite_in_fa(caller,in_asset,in_amount);




        let coin_price_identifier =  get_feed_id(in_asset);
        let coin_usd_price_id = price_identifier::from_byte_vec(coin_price_identifier);

        let price =pyth::get_price(coin_usd_price_id);

        let price_positive = i64::get_magnitude_if_positive(&price::get_price(&price)); // This will fail if the price is negative
        let expo_magnitude = i64::get_magnitude_if_negative(&price::get_expo(&price)); // This will fail if the exponent is positive

        let decimals = fungible_asset::decimals(in_asset);
        let octas = pow(10, (decimals as u64));


        let price_in_aptos_coin =  (octas * pow(10, expo_magnitude)) / price_positive;

        assert!(loan_amount <= price_positive,not_implemented(E_over_loan));

        // let out_amount = if(loan_amount != 0){
        //     math64::mul_div(price_in_aptos_coin,loan_amount,100000)
        // }else{
        //     loan_amount
        // };
        let out_amount = loan_amount;

        change_user_on_vault(caller,in_amount,out_amount,in_asset);


        let loan_fa = pledge_to_get_tpxusd(out_amount);

        primary_fungible_store::deposit(address_of(caller),loan_fa);

        emit(Add_collateral{
            user:address_of(caller),
            user_collateral_total_amount:get_collateral_total_amount(caller),
            add_collateral_type:fungible_asset::symbol(in_asset),
            add_collateral_amount:in_amount,
        });
        emit(Loan{
            user:address_of(caller),
            user_collateral_total_amount:get_collateral_total_amount(caller),
            collateral_type:fungible_asset::symbol(in_asset),
            collateral_amount:in_amount,
            loan_tpxusd_amount:out_amount,
        });


    }

    public(friend) fun  pledge_to_get_tpxusd(amount:u64):FungibleAsset acquires Table_of_Vault {
        let borrow = borrow_global_mut<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        fungible_asset::mint(&borrow.tpxusd.mint_ref,amount)
    }


    public(friend) fun add_to_vault_table(caller:&signer,pledge_asset:Object<Metadata>,name:String,symbol:String) acquires Table_of_Vault{
        let borrow = borrow_global_mut<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        //let new_vault = create_vault(caller,pledge_asset,name,symbol,8);
        //borrow.accept_asset.add(pledge_asset,new_vault);
    }

    public(friend)fun a(in:Object<Metadata>,new_vault:Object<Vault>) acquires Table_of_Vault {
        let borrow = borrow_global_mut<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        borrow.support_asset_vector.push_back(in);
        borrow.accept_asset.add(in,new_vault);
    }


    #[view]
    public fun get_support_Asset():vector<Object<Metadata>> acquires Table_of_Vault {
        let borrow = borrow_global<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        borrow.support_asset_vector
    }

    public entry fun initlize(caller:&signer){
       // assert!(address_of(caller)==@admin,not_implemented(E_not_admin));
        let conf = &create_named_object(&get_signer(),TPX_SEED);
        create_primary_store_enabled_fungible_asset(conf ,none<u128>(),utf8(b"TPXusd"),utf8(b"TPXUSD"),8,utf8(ICON_URL),utf8(Project_URL ));
        let new=Table_of_Vault{
            accept_asset:smart_table::new(),
            support_asset_vector:vector[],
            tpxusd:Control_ref{
                obj_meta:object_from_constructor_ref<Metadata>(conf),
                mint_ref:generate_mint_ref(conf),
                burn_ref:fungible_asset::generate_burn_ref(conf),
                transfer_ref:fungible_asset::generate_transfer_ref(conf),
            },
            fees: 1 ,
            fees_2 :  100
        };
        move_to(&generate_signer(conf),new);


    }
    fun init_module(caller:&signer){
        move_to(caller,VaultState{
            sequence_number:0
        })
    }




    #[test_only]
    public fun print_user_data (caller:&signer,pledge_asset:Object<Metadata>) acquires Table_of_Vault, Vault {
        let borrow = borrow_global<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        assert!(borrow.accept_asset.contains(pledge_asset)==true ,not_implemented(E_not_support_asset));
        let object_vault =  borrow_global<Vault>(object_address(borrow.accept_asset.borrow(pledge_asset)));
        let user = object_vault.user.borrow(address_of(caller));
        // debug::print(&string_utils::format1(&b"User = {}",user.));
        debug::print( user);
    }
    #[test_only]
    public fun call_vault_init(caller:&signer){
        initlize(caller);
        init_module(caller);
    }
    #[test_only]
    public fun print_usd_balance(caller:&signer) acquires Table_of_Vault {
        let meta =get_tpxusd_metadata();
        let b= primary_fungible_store::balance(address_of(caller),meta);
        debug::print(&string_utils::format1(&b"Balance of tpxusd = {}",b/100000000));
    }

    #[test(caller=@triplex)]
    fun test_vault(caller:&signer) {
        // ready_everything(caller);
        // let (apt_obj,_)=deploy(address_of(caller));
        // directly_add_mortgage(caller,apt_obj);
        // // pledge_to_get_tpxusd_FA(caller,apt_obj,100000000000,10000000000,);
        //
        //
        // print_apt_balance(caller,apt_obj);
        // print_usd_balance(caller);
        // print_user_data(caller,apt_obj);
    }
    #[test_only]
    fun ready_everything(caller:&signer){
        package_manager::call_package_init(caller);
        initlize(caller);
        init_module(caller);
    }


}
