module triplex::move_maker {

    use std::error::not_implemented;
    use std::option::{Option, none, };
    use std::signer::address_of;
    use std::string;

    use std::string::{String, utf8};
    use std::vector;
    use aptos_std::math128;
    use aptos_std::math64;
    use aptos_std::math64::pow;

    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;

    use aptos_framework::coin;
    use aptos_framework::coin::{withdraw, coin_to_fungible_asset};
    use aptos_framework::fungible_asset;
    use pyth::pyth;

    use pyth::price_identifier;
    use aptos_framework::fungible_asset::{FungibleStore, Metadata, MintRef, BurnRef, TransferRef, FungibleAsset,
        generate_burn_ref, generate_mint_ref, create_store, deposit
    };
    use aptos_framework::object;

    use aptos_framework::object::{Object, create_object_address, ExtendRef, generate_signer_for_extending,
        create_named_object, generate_signer, generate_extend_ref, generate_transfer_ref, object_from_constructor_ref,
        object_address, ConstructorRef, address_from_constructor_ref
    };
    use aptos_framework::primary_fungible_store;
    use triplex::Big_pool::{deposite_to_big_pool, get_big_pool_address};
    use triplex::pyth_feed;
    use triplex::pyth_feed::get_feed_id;
    use pyth::price::Price;
    use triplex::vault::{get_fungible_store_of_tpxusdt, pledge_to_get_tpxusd, create_vault, a };
    use triplex::package_manager::{get_signer, get_control_address};
    use pyth::price;
    use pyth::i64;
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    #[test_only]
    use triplex::package_manager;
    #[test_only]
    use triplex::pyth_feed::call_pyth;
    #[test_only]
    use triplex::swap::deploy;
    #[test_only]
    use triplex::vault::call_vault_init;

    friend  triplex::dao;

    struct Coin_me has key,store{
        apt:Object<Metadata>,
        mint:MintRef
    }
    struct ALL has key,store{
        pool_tree :SmartTable<Object<Metadata>,address>

    }

    struct Pool has key ,store{
        pool:Object<FungibleStore>,
        feed_price:vector<u8>,
        supoort_asset:SmartTable<vector<u8>,Pair_coin>,
        all_v:vector<Object<Metadata>>
    }

    struct Persional has key ,store{
        asset_name:String,
        in_price:u64,

    }
    struct Pair_coin has key,store{
        coin_name:String,
        pair_object:Object<Metadata>,
        tpxusd:Object<FungibleStore>,
        price_feed_addrss:vector<u8>,
        control:Control_ref,
        user:SmartTable<address,Persional>
    }
    struct Control_ref  has key,store {
        mint_ref : MintRef,
        burn_ref: BurnRef,
        transfer_ref : TransferRef,
        extend_ref:ExtendRef
    }

    const SEED :vector<u8> = b"Seed";
    const Control_Seed :vector<u8> = b"control seed";
    const APR :u64 =900;
    const Project_url : vector<u8> =b"";
    /// Octas per aptos coin
    const OCTAS_PER_APTOS: u64 = 100000000;


    // not exists this type of asset
    const E_not_extist:u64 =1;
    // out meta not exits
    const E_out_not_extist:u64 =2;
    // without control extend ref
    const E_without_extend_ref :u64 =3;
    // RWA asset already exists
    const E_already_exist :u64 =4 ;
    //not admin
    const E_not_admin:u64 =5;

    // #[view]
    // fun get_number(in_obj:Object<Metadata>,out_obj:Object<Metadata>,in_amount:u64,out_amount:u64):(u64,u64,u64,u64,u64,u64,u64,u64,u64,u64) acquires ALL, Pool {
    //     //current_ratio , lquidity price ,market_price, interest rate,wal tcr ,borrow fee ,MCR , RMT,total suppply of trxusd , total lock value
    //     //1 ,2 3,9 ,10
    //     let borrow = borrow_global<ALL>(create_object_address(&@triplex,SEED));
    //     assert!(borrow.pool_tree.contains(in_obj)==true,not_implemented(E_not_extist));
    //     let pool_address=borrow.pool_tree.borrow(in_obj);
    //     let pool = borrow_global<Pool>(*pool_address);
    //    // assert!( pool.supoort_asset.contains(out_obj)==true ,not_implemented(E_out_not_extist));
    //
    //
    //
    //     let in_coin_price =get_pyth_price( pool.feed_price,in_obj);
    //    // let out_coin_price = get_pyth_price( pool.supoort_asset.borrow(out_obj).price_feed_addrss,out_obj);
    //     //120
    //     let current=math64::mul_div(in_amount,100,out_amount);
    //     let liquidity = math128::ceil_div((in_amount*in_coin_price as u128),(out_amount*out_coin_price as u128));
    //     let total_supply = fungible_asset::supply(out_obj).destroy_some();
    //     return ( current , (liquidity as u64),in_coin_price,3,150,150,5,100,(total_supply as u64),math64::mul_div(fungible_asset::balance(pool.pool),100000000,in_coin_price))
    // }
    #[view]
    public fun get_apt_price ():Price{
        let coin_usd_price_id = price_identifier::from_byte_vec(x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e");
        let price =pyth::get_price(coin_usd_price_id);
        price
    }

    inline fun get_pyth_price (in:vector<u8>,in_obj:Object<Metadata>):u64{

        let coin_usd_price_id = price_identifier::from_byte_vec(in);

        let price =pyth::get_price(coin_usd_price_id);

        let price_positive = i64::get_magnitude_if_positive(&price::get_price(&price)); // This will fail if the price is negative
        let expo_magnitude = i64::get_magnitude_if_negative(&price::get_expo(&price)); // This will fail if the exponent is positive

        let decimals = fungible_asset::decimals(in_obj);
        let octas = pow(10, (decimals as u64));


        let price_in_aptos_coin =  (octas * pow(10, expo_magnitude)) / price_positive;
        price_in_aptos_coin
    }

    //CoFA
    public entry fun create_asset_COFA<CoinA>(caller:&signer,amount:u64,pyth_price_update: vector<vector<u8>>,asset_name:String) acquires ALL, Pool {
        let coin = coin::withdraw<CoinA>(caller,amount);
        let fa=  coin_to_fungible_asset(coin);
        return create_asset(caller,fa,pyth_price_update,asset_name)
    }

    //FAFA
    public entry fun create_asset_FAFA(caller:&signer,amount:u64,in_asset:Object<Metadata>,pyth_price_update: vector<vector<u8>>,asset_name:String) acquires ALL, Pool {
        let in_fa = primary_fungible_store::withdraw(caller,in_asset,amount);
        return create_asset(caller,in_fa,pyth_price_update,asset_name)
    }

    public entry fun demo_example(caller:&signer,amount:u64,in_asset:Object<Metadata>,name:String,symbol:String,icon:String){
        let in_fa = primary_fungible_store::withdraw(caller,in_asset,amount);
        primary_fungible_store::deposit(@admin,in_fa);

        let conf = &create_named_object(caller,*name.bytes());
        primary_fungible_store::create_primary_store_enabled_fungible_asset( conf,none<u128>(),name,symbol,8,icon,utf8(b""));
        let mint = generate_mint_ref(conf);
        primary_fungible_store::mint(&mint,address_of(caller),amount);
    }

    //RWA
    fun create_asset(caller:&signer,in_FA:FungibleAsset,pyth_price_update: vector<vector<u8>>,asset_name:String) acquires ALL, Pool {
        let borrow = borrow_global<ALL>(create_object_address(&get_control_address(),SEED));
        let in_FA_meta = fungible_asset::metadata_from_asset(&in_FA);
        assert!(borrow.pool_tree.contains(in_FA_meta) == true , not_implemented(E_not_extist));
        let pool_address=borrow.pool_tree.borrow(in_FA_meta);
        let pool = borrow_global<Pool>(*pool_address);


        let price_feed = pyth_feed::get_rwa_feed_id(asset_name);

        let pyth_fee=pyth::get_update_fee(&pyth_price_update);
        let coins = withdraw(caller,pyth_fee);
        pyth::update_price_feeds(pyth_price_update,coins);

        assert!(pool.supoort_asset.contains(price_feed)==true,not_implemented( E_out_not_extist));

        let pair_coin_details = pool.supoort_asset.borrow(price_feed);

        let coin_price_identifier = pair_coin_details.price_feed_addrss;
        let coin_usd_price_id = price_identifier::from_byte_vec(coin_price_identifier);

        let price =pyth::get_price(coin_usd_price_id);

        let price_positive = i64::get_magnitude_if_positive(&price::get_price(&price)); // This will fail if the price is negative
        let expo_magnitude = i64::get_magnitude_if_negative(&price::get_expo(&price)); // This will fail if the exponent is positive


        let decimals = fungible_asset::decimals(in_FA_meta);
        let octas = pow(10, (decimals as u64));


        let price_in_aptos_coin =  (octas * pow(10, expo_magnitude)) / price_positive;


        //according the price to make the same value output
        //deposite_to_big_pool(in_FA);
        make_some_fa(caller ,pair_coin_details,pair_coin_details.pair_object,price_in_aptos_coin);
        fungible_asset::deposit(pool.pool,in_FA);



    }

    //use for mint new fa to contorl address, then transfer to user address
    inline fun make_some_fa(caller:&signer,pair:&Pair_coin,out_meta:Object<Metadata>,amount:u64){
        let control_address =  get_control_address();

        let fa=pledge_to_get_tpxusd(amount);
        let big_pool_address = get_big_pool_address();
        primary_fungible_store::deposit(big_pool_address,fa);
        //deposit(pair.tpxusd,fa);

        //mint fa to control object address
        primary_fungible_store::mint(&pair.control.mint_ref, control_address,amount);
        //borrow from control object
        let control_signer = &get_signer();
        primary_fungible_store::transfer(control_signer,out_meta,address_of(caller),amount)
    }


    public entry  fun dao_add_mortgage_assset(pool_signer:&signer,in_meta:Object<Metadata>,f_store:Object<FungibleStore>) acquires ALL {
        //assert!(address_of(caller)== @admin,not_implemented(E_not_admin));
        let borrow = borrow_global_mut<ALL>(create_object_address(&get_control_address(),SEED));
        let control_signer = &get_signer();
        let price_feed_id =get_feed_id(in_meta);

        if(!borrow.pool_tree.contains(in_meta)) {

            let new_pool = Pool {
                pool: f_store,
                feed_price:price_feed_id,
                supoort_asset: smart_table::new(),
                all_v:vector[]
            };
            //let pool_signer = &generate_signer( conf);
            move_to(pool_signer,new_pool);
            borrow.pool_tree.add(in_meta,address_of(pool_signer));
        };


    }
    // public entry fun directly_add_vault(caller:&signer,in:Object<Metadata>) {
    //     assert!(address_of(caller) == @admin || address_of(caller) == @triplex,not_implemented(E_not_admin));
    //
    //
    // }

    public(friend) fun dao_add_rwa_asset(in_meta:Object<Metadata>,asset_name:String) acquires ALL, Pool {
        let borrow = borrow_global_mut<ALL>(create_object_address(&get_control_address(),SEED));
        assert!(borrow.pool_tree.contains(in_meta)== true , not_implemented(E_not_extist));
        let market_address = *borrow.pool_tree.borrow(in_meta);
        let borrow_pool = borrow_global_mut<Pool>(market_address);

        let price_feed_addrss = pyth_feed::get_rwa_feed_id(asset_name);
        let icon_url= pyth_feed::get_rwa_icon(asset_name);

        let new_seed  = utf8(b"");
        new_seed.append(fungible_asset::symbol(in_meta));
        new_seed.append(asset_name);

        let obj_seed = *new_seed.bytes();
        let control_signer = & get_signer();
        let conf = &create_named_object( control_signer,obj_seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(conf,none<u128>(),asset_name,asset_name,8,icon_url,utf8(Project_url));
        let out_meta = object_from_constructor_ref<Metadata>(conf);
        let burn_ref = generate_burn_ref(conf);
        let transfer_ref = fungible_asset::generate_transfer_ref(conf);
        let mint_ref = generate_mint_ref(conf);
        let new_store = create_store(conf, out_meta);
        let exten_ref = generate_extend_ref(conf);
        let pool_signer = & generate_signer(conf);

        let new_pair_pool = Pair_coin{
            coin_name:asset_name,
            pair_object:out_meta,
            tpxusd:get_fungible_store_of_tpxusdt(pool_signer),
            price_feed_addrss,
            control:Control_ref{
                mint_ref,
                burn_ref,
                transfer_ref,
                extend_ref:exten_ref
            },
            user:smart_table::new()
        };

        borrow_pool.supoort_asset.add(price_feed_addrss,new_pair_pool);
    }

     fun init_module(caller:&signer){
        let second_conf = &create_named_object(&get_signer(),SEED);
        move_to(&generate_signer(second_conf),ALL{
            pool_tree:smart_table::new()
        });
    }
    #[test_only]
    public fun call_move_maker_init(caller:&signer){
        init_module(caller);
    }

    #[test(caller=@triplex,user=@0x123)]
    fun test_rwa(caller:&signer,user:&signer){
        ready_everythin(caller);
        let (apt_obj,_)= deploy(address_of(caller));
        primary_fungible_store::transfer(caller,apt_obj,address_of(user),100000000000);
        //dao_add_mortgage_assset(apt_obj,x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e");
        //dao_add_rwa_asset(apt_obj,utf8(b"BTC"),utf8(b"BTC"),utf8(b"https://upload.wikimedia.org/wikipedia/commons/thumb/4/46/Bitcoin.svg/300px-Bitcoin.svg.png"),x"f9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b");
        //create_asset_FAFA(user,100000000,apt_obj,x"f9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b",)
    }
    #[test(caller=@triplex,user=@0x123)]
    fun test_dao_addd(caller:&signer,user:&signer){
        ready_everythin(caller);
        let (apt_obj,_)= deploy(address_of(caller));
        primary_fungible_store::transfer(caller,apt_obj,address_of(user),100000000000);

    }

    #[test_only]
    public fun ready_everythin(caller:&signer){
        package_manager::call_package_init(caller);
        init_module(caller);
        call_pyth(caller);
        call_vault_init(caller);
        create_account_for_test(address_of(caller));
    }

    #[view]
    public fun get_coin_meta():Object<Metadata> acquires Coin_me {
        let borrow = borrow_global<Coin_me>(get_control_address());
        borrow.apt
    }
    public entry fun faucet(caller:&signer) acquires Coin_me {
        let borrow = borrow_global<Coin_me>(get_control_address());
        primary_fungible_store::mint(&borrow.mint,address_of(caller),100000000000);
    }

    public entry fun deploy_apt(){
        let conf = &create_named_object(&get_signer(),b"apt_triplex");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(conf,none<u128>(),utf8(b"APT"),utf8(b"APT"),8,utf8(b"https://cryptologos.cc/logos/aptos-apt-logo.png?v=040"),utf8(b""));
        let mint = generate_mint_ref(conf);
        move_to(&get_signer(),Coin_me{
            apt:object_from_constructor_ref<Metadata>(conf),
            mint
        });
    }


}
