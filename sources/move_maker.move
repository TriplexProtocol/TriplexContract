module triplex::move_maker {

    use std::error::not_implemented;
    use std::option::{Option, none, };
    use std::signer::address_of;

    use std::string::{String, utf8};
    use aptos_std::math64::pow;

    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;

    use aptos_framework::coin;
    use aptos_framework::coin::{withdraw, coin_to_fungible_asset};
    use aptos_framework::fungible_asset;
    use pyth::pyth;

    use pyth::price_identifier;
    use aptos_framework::fungible_asset::{FungibleStore, Metadata, MintRef, BurnRef, TransferRef, FungibleAsset,
        generate_burn_ref, generate_mint_ref, create_store
    };

    use aptos_framework::object::{Object, create_object_address, ExtendRef, generate_signer_for_extending,
        create_named_object, generate_signer, generate_extend_ref, generate_transfer_ref, object_from_constructor_ref
    };
    use aptos_framework::primary_fungible_store;
    use triplex::package_manager::{get_signer, get_control_address};
    use pyth::price;
    use pyth::i64;

    struct ALL has key,store{
        pool_tree :SmartTable<Object<Metadata>,address>
    }

    struct Pool has key ,store{
        pool:Object<FungibleStore>,
        supoort_asset:SmartTable<Object<Metadata>,Pair_coin>
    }

    struct Persional has key ,store{
        asset_name:String,
        in_price:u64,

    }
    struct Pair_coin has key,store{
        coin_name:String,
        pair_object:Object<Metadata>,
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
    const Project_url:String=utf8(b"");
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

    //CoFA
    public entry fun create_asset_COFA<CoinA>(caller:&signer,amount:u64,out_asset:Object<Metadata>,pyth_price_update: vector<vector<u8>>) acquires ALL, Control_ref, Pool {
        let coin = coin::withdraw<CoinA>(caller,amount);
        let fa=  coin_to_fungible_asset(coin);
        return create_asset(caller,fa,out_asset,pyth_price_update)
    }
    //FAFA
    public entry fun create_asset_FAFA(caller:&signer,amount:u64,in_asset:Object<Metadata>,out_asset:Object<Metadata>,pyth_price_update: vector<vector<u8>>) acquires ALL, Control_ref, Pool {
        let in_fa = primary_fungible_store::withdraw(caller,in_asset,amount);
        return create_asset(caller,in_fa,out_asset,pyth_price_update)
    }
    //RWA
    fun create_asset(caller:&signer,in_FA:FungibleAsset,out_asset:Object<Metadata>,pyth_price_update: vector<vector<u8>>) acquires ALL, Control_ref, Pool {
        let borrow = borrow_global<ALL>(create_object_address(&@triplex,SEED));
        let in_FA_meta = fungible_asset::metadata_from_asset(&in_FA);
        assert!(borrow.pool_tree.contains(in_FA_meta) == true , not_implemented(E_not_extist));
        let pool_address=borrow.pool_tree.borrow(in_FA_meta);
        let pool = borrow_global<Pool>(*pool_address);

        let pyth_fee=pyth::get_update_fee(&pyth_price_update);
        let coins = withdraw(caller,pyth_fee);
        pyth::update_price_feeds(pyth_price_update,coins);

        assert!(pool.supoort_asset.contains(out_asset)==true,not_implemented( E_out_not_extist));

        let pair_coin_details = pool.supoort_asset.borrow(out_asset);

        let coin_price_identifier = pair_coin_details.price_feed_addrss;
        let coin_usd_price_id = price_identifier::from_byte_vec(coin_price_identifier);

        let price =pyth::get_price(coin_usd_price_id);

        let price_positive = i64::get_magnitude_if_positive(&price::get_price(&price)); // This will fail if the price is negative
        let expo_magnitude = i64::get_magnitude_if_negative(&price::get_expo(&price)); // This will fail if the exponent is positive


        let decimals = fungible_asset::decimals(in_FA_meta);
        let octas = pow(10, (decimals as u64));


        let price_in_aptos_coin =  (octas * pow(10, expo_magnitude)) / price_positive;


        //according the price to make the same value output

        make_some_fa(caller ,pair_coin_details,out_asset,price_in_aptos_coin);



    }

    //use for mint new fa to contorl address, then transfer to user address
    inline fun make_some_fa(caller:&signer,pair:&Pair_coin,out_meta:Object<Metadata>,amount:u64){
        let control_address =  get_control_address();
        //mint fa to control object address
        primary_fungible_store::mint(&pair.control.mint_ref, control_address,amount);
        //borrow from control object
        let control_signer = &get_signer();
        primary_fungible_store::transfer(control_signer,out_meta,address_of(caller),amount)
    }


    public(friend) fun dao_add_mortgage_assset(in_meta:Object<Metadata>) acquires ALL {
        let borrow = borrow_global_mut<ALL>(create_object_address(&@triplex,SEED));
        let control_signer = & get_signer();
        let obj_seed = *fungible_asset::symbol(in_meta).bytes();
        if(!borrow.pool_tree.contains(in_meta)) {
            let conf = &create_named_object(control_signer, obj_seed);
            let new_pool = Pool {
                pool: create_store(conf, in_meta),
                supoort_asset: smart_table::new()
            };
            let pool_signer = &generate_signer(conf);
            move_to(pool_signer,new_pool);
            borrow.pool_tree.add(in_meta,create_object_address(&address_of(control_signer), obj_seed));
        }
    }

    public(friend) fun dao_add_rwa_asset(in_meta:Object<Metadata>,name:String,symbol:String,icon_url:String,price_feed_addrss:vector<u8>) acquires ALL, Pool {
        let borrow = borrow_global_mut<ALL>(create_object_address(&@triplex,SEED));
        assert!(borrow.pool_tree.contains(in_meta)== true , not_implemented(E_not_extist));
        let market_address = *borrow.pool_tree.borrow(in_meta);
        let borrow_pool = borrow_global_mut<Pool>(market_address);

       let new_seed  = utf8(b"");
        new_seed.append(fungible_asset::symbol(in_meta));
        new_seed.append(name);

        let obj_seed = *new_seed.bytes();
        let control_signer = & get_signer();
        let conf = &create_named_object( control_signer,obj_seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(conf,none<u128>(),name,symbol,8,icon_url,Project_url);
        let out_meta = object_from_constructor_ref<Metadata>(conf);
        let burn_ref = generate_burn_ref(conf);
        let transfer_ref = fungible_asset::generate_transfer_ref(conf);
        let mint_ref = generate_mint_ref(conf);
        let new_store = create_store(conf, out_meta);
        let exten_ref = generate_extend_ref(conf);

        let new_pair_pool = Pair_coin{
            coin_name:name,
            pair_object:out_meta,
            price_feed_addrss,
            control:Control_ref{
                mint_ref,
                burn_ref,
                transfer_ref,
                extend_ref
            },
            user:smart_table::new()
        };

        borrow_pool.supoort_asset.add(out_meta,new_pair_pool);
    }

    fun init_module(caller:&signer){
        let second_conf = &create_named_object(caller,SEED);
        move_to(&generate_signer(second_conf),ALL{
            pool_tree:smart_table::new()
        });
    }
}
