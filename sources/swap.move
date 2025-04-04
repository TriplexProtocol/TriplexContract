module triplex::swap {

    use std::error::not_implemented;
    use std::option;
    use std::option::none;
    use std::signer::address_of;
    use std::string::{String, utf8};
    use aptos_std::comparator;
    use aptos_std::debug;
    use aptos_std::math128;
    use aptos_std::math64;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_std::string_utils;
    use aptos_framework::event::emit;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{FungibleStore, MintRef, BurnRef, TransferRef, Metadata, symbol, create_store,
        generate_mint_ref, generate_burn_ref, FungibleAsset, amount, metadata_from_asset
    };
    use aptos_framework::object;
    use aptos_framework::object::{Object, ExtendRef, create_named_object, generate_extend_ref, generate_signer,
        create_object_address, generate_transfer_ref, object_from_constructor_ref, object_address,
        generate_signer_for_extending, address_to_object, address_from_constructor_ref
    };
    use aptos_framework::primary_fungible_store;
    use aptos_framework::primary_fungible_store::{create_primary_store_enabled_fungible_asset, withdraw};
    use pyth::event;
    use triplex::package_manager::{get_signer, get_control_address};
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    #[test_only]
    use triplex::package_manager;

    const SWAP_SEED :vector<u8> = b"swap";

    ///pool exists
    const E_pool_already_exists:u64 = 1;
    ///input wrong object metadata
    const E_not_pool_coin:u64 =2;
    ///zero
    const EZERO_AMOUNT:u64 =3;
    ///LP cant mint
    const EINSUFFICIENT_LIQUIDITY_MINTED:u64 =4;

    struct Pool_tree has key,store{
        pool_tree_extend:ExtendRef,
        pool_table:SmartTable<String,Object<Pool>>
    }
    struct Pool has key,store{
        coin_1:Object<FungibleStore>,
        coin_2:Object<FungibleStore>,
        fee_1: Object<FungibleStore>,
        fee_2 :Object<FungibleStore>,
        init_1:u64,
        init_2:u64,
        extend:ExtendRef,
        LP_ref:LP_control
    }
    struct LP_control has key,store{
        Mint_ref :MintRef,
        Burn_ref:BurnRef,
        Tran_ref :TransferRef,
        extend_ref:ExtendRef
    }
    #[event]
    struct Create_pool has store,copy,drop{

    }

    #[event]
    struct Swap_event has store,copy,drop {}

    #[event]
    struct Add_LP has copy,store ,drop {}
    public entry fun swap(caller:&signer,in:Object<Metadata>,out:Object<Metadata>,in_amount:u64,out_min:u64) acquires Pool_tree, Pool {
        //let is_sort = is_sorted(in,out);
        // if(!is_sort){
        //     return swap(caller,out,in,in_amount,out_min)
        // };
        let (coin_1_balance ,coin_2_balance)=get_pool_balance(in,out);

        let pool_seed= get_pool_seed(in,out);
        let borrow = borrow_global_mut<Pool_tree>(get_pool_tree_address());
        assert!(borrow.pool_table.contains(pool_seed)== true,not_implemented( E_pool_already_exists));

        let pool_obj = borrow.pool_table.borrow_mut(pool_seed);
        let pool = borrow_global_mut<Pool>(object_address(pool_obj));
        let pool_signer = &generate_signer_for_extending(&pool.extend);


        let a=fungible_asset::store_metadata(pool.coin_1);
        let (amount_out,fee) = if(fungible_asset::store_metadata(pool.coin_1) == in){
            get_amount_out(coin_1_balance,coin_2_balance,in_amount,20)
        }else if(fungible_asset::store_metadata(pool.coin_2) == in){
            get_amount_out(coin_2_balance,coin_1_balance,in_amount,20)
        }else{abort E_not_pool_coin};

        let in_fungible_asset = withdraw(caller,in,in_amount);
        if(fungible_asset::store_metadata(pool.coin_1) == in){
            fungible_asset::deposit(pool.coin_1,in_fungible_asset)
        }else if(fungible_asset::store_metadata(pool.coin_2) == in){
            fungible_asset::deposit(pool.coin_2,in_fungible_asset)
        }else{abort E_not_pool_coin};

        let out_fa = if(fungible_asset::store_metadata(pool.coin_1) == in){
            fungible_asset::withdraw(pool_signer,pool.coin_2,amount_out)
        }else if(fungible_asset::store_metadata(pool.coin_2) == in){
            fungible_asset::withdraw(pool_signer,pool.coin_1,amount_out)
        }else{abort E_not_pool_coin};

        let fee_fa = fungible_asset::extract(&mut out_fa,fee);


        if(fungible_asset::store_metadata(pool.fee_1) == fungible_asset::asset_metadata(&fee_fa)){
            fungible_asset::deposit(pool.fee_1,fee_fa);
        }else if(fungible_asset::store_metadata(pool.fee_2) == fungible_asset::asset_metadata(&fee_fa)){
            fungible_asset::deposit(pool.fee_2,fee_fa);
        }else{abort E_not_pool_coin};


        primary_fungible_store::deposit(address_of(caller),out_fa);
        emit(Swap_event{});
    }
    #[view]
    public fun get_amount_out(
        reserve_1:u64,
        reserve_2:u64,
        amount_in: u64,
        fee_1:u64,
    ): (u64, u64){
        let (reserve_in, reserve_out) = (reserve_1 as u256,reserve_2  as u256);
        let fees_amount = math64::mul_div(amount_in,  fee_1, 10000);
        let amount_in = ((amount_in - fees_amount) as u256);
        let amount_out = amount_in * reserve_out / (reserve_in + amount_in);
        ((amount_out as u64), fees_amount)
    }
    #[view]
    public fun get_pool_balance (in:Object<Metadata>,out:Object<Metadata>):(u64,u64) acquires Pool_tree, Pool {
        let pool_seed= get_pool_seed(in,out);
        let borrow = borrow_global<Pool_tree>(get_pool_tree_address());
        let pool_obj = borrow.pool_table.borrow(pool_seed);
        let pool = borrow_global<Pool>(object_address(pool_obj));
        if(in ==fungible_asset::store_metadata(pool.coin_1)){
            return (fungible_asset::balance(pool.coin_1),fungible_asset::balance(pool.coin_2))
        }else if (in ==fungible_asset::store_metadata(pool.coin_2)){
            return (fungible_asset::balance(pool.coin_2),fungible_asset::balance(pool.coin_1))
        }else{abort E_not_pool_coin}
    }

    public fun mint(
        lp: &signer,
        fungible_asset_1: FungibleAsset,
        fungible_asset_2: FungibleAsset,
        pool_address:Object<Pool>,
        pool_signer:&signer,
        pool_data:&mut Pool
    )  {
        // let lp_store = ensure_lp_token_store(address_of(lp), pool_address);
        let token_1 = fungible_asset::metadata_from_asset(&fungible_asset_1);
        let token_2 = fungible_asset::metadata_from_asset(&fungible_asset_2);

        let lp_name = utf8(b"");
        lp_name.append(fungible_asset::name(token_1));
        lp_name.append(fungible_asset::name(token_2));
        lp_name.append(utf8(b"_LP"));

        // debug::print(&string_utils::format1(&b"lp pool signer = {}",address_of(pool_signer)));
        // debug::print(&string_utils::format1(&b"create object address= {}",create_object_address(&address_of(pool_signer),*lp_name.bytes())));
        //debug::print(&string_utils::format1(&b"pool obj = {}",&object::object_address( &pool_address)));
        // debug::print(&object::object_address( &pool_address));
        // debug::print(&*lp_name.bytes());
        // let lp_store =primary_fungible_store::primary_store(create_object_address(&address_of(pool_signer),*lp_name.bytes()),  pool_address);
        // let lp_store =  if(primary_fungible_store::primary_store_exists(
        //     object::object_address( &pool_address),  pool_address
        // )){
        //
        // }else {
        //     primary_fungible_store::create_primary_store(object::object_address( &pool_address),  pool_address)
        // };



        if (!is_sorted(token_1, token_2)) {
            return mint(lp, fungible_asset_2, fungible_asset_1,pool_address,pool_signer,pool_data)
        };
        // The LP store needs to exist before we can mint LP tokens.


        let amount_1 = fungible_asset::amount(&fungible_asset_1);
        let amount_2 = fungible_asset::amount(&fungible_asset_2);
        assert!(amount_1 > 0 && amount_2 > 0, EZERO_AMOUNT);
        //let pool_data = borrow_global<Pool>(object_address(&pool_address));

        let store_1 = pool_data.coin_1;
        let store_2 = pool_data.coin_2;



        // Before depositing the added liquidity, compute the amount of LP tokens the LP will receive.
        let reserve_1 = fungible_asset::balance(store_1);
        let reserve_2 = fungible_asset::balance(store_2);
        // let lp_token_supply = option::destroy_some(fungible_asset::supply( pool_address));
        let lp_token_supply = 0;
        let mint_ref = &pool_data.LP_ref.Mint_ref;
        let liquidity_token_amount = if (lp_token_supply == 0) {
            let total_liquidity = (math128::sqrt((amount_1 as u128) * (amount_2 as u128)) as u64);
            // Permanently lock the first MINIMUM_LIQUIDITY tokens.
            primary_fungible_store::mint(mint_ref, object::object_address(&pool_address) , 1000);
            total_liquidity - 1000
        } else {
            // Only the smaller amount between the token 1 or token 2 is considered. Users should make sure to either
            // use the router module or calculate the optimal amounts to provide before calling this function.
            let token_1_liquidity = math64::mul_div(amount_1, (lp_token_supply as u64), reserve_1);
            let token_2_liquidity = math64::mul_div(amount_2, (lp_token_supply as u64), reserve_2);
            math64::min(token_1_liquidity, token_2_liquidity)
        };
        assert!(liquidity_token_amount > 0, EINSUFFICIENT_LIQUIDITY_MINTED);

        // Deposit the received liquidity into the pool.
        // debug::print(&string_utils::format2(&b"deposite 1 = {} , {}",metadata_from_asset(&fungible_asset_1),fungible_asset::store_metadata(store_1)));
        // debug::print(&string_utils::format2(&b"deposite 2 = {} , {}",metadata_from_asset(&fungible_asset_2),fungible_asset::store_metadata(store_2)));

        fungible_asset::deposit(store_1, fungible_asset_1);
        fungible_asset::deposit(store_2, fungible_asset_2);

        // We need to update the amount of rewards claimable by this LP token store if they already have a previous
        // balance. This ensures that their update balance would not lead to earning a larger portion of the fees
        // retroactively.
        // update_claimable_fees(address_of(lp), pool);

        // Mint the corresponding amount of LP tokens to the LP.
        let lp_tokens = fungible_asset::mint(mint_ref, liquidity_token_amount);
        // fungible_asset::deposit_with_ref(&pool_data.LP_ref.Tran_ref, lp_store, lp_tokens);
        primary_fungible_store::deposit(address_of(lp),lp_tokens)
    }

    fun ensure_lp_token_store<T: key>(lp: address, pool: Object<T>): Object<FungibleStore> acquires Pool {
        primary_fungible_store::ensure_primary_store_exists(lp, pool);
        let store = primary_fungible_store::primary_store(lp, pool);
        if (!fungible_asset::is_frozen(store)) {
            // LPs must call transfer here to transfer the LP tokens so claimable fees can be updated correctly.
            let transfer_ref = &borrow_global<Pool>(object_address(&pool)).LP_ref.Tran_ref;
            fungible_asset::set_frozen_flag(transfer_ref, store, true);
        };
        store
    }


    #[view]
    public fun is_sorted(token_1: Object<Metadata>, token_2: Object<Metadata>): bool {
        let token_1_addr = object::object_address(&token_1);
        let token_2_addr = object::object_address(&token_2);
        comparator::compare(&token_1_addr, &token_2_addr).is_smaller_than()
    }
    inline fun get_pool_seed(pair_1:Object<Metadata>,pair_2:Object<Metadata>):String{
        let is_sort = is_sorted(pair_1,pair_2);
        let r_s = utf8(b"");
        if(is_sort){
            r_s.append(string_utils::to_string(&pair_1));
            r_s.append(string_utils::to_string(&pair_2));
             r_s
        }else{
            r_s.append(string_utils::to_string(&pair_2));
            r_s.append(string_utils::to_string(&pair_1));
             r_s
        }
    }
    fun create_store_for_pool(caller:&signer,in:Object<Metadata>,fee:bool):Object<FungibleStore>{
        let symbol = fungible_asset::symbol(in);
        if(fee){
            symbol.append(utf8(b"_fee"));
        };
        let conf = &create_named_object(caller,*symbol.bytes());
        create_store(conf,in)
    }
    public entry fun add_lp (caller:&signer,in:Object<Metadata>,out:Object<Metadata>,in_amount:u64,out_amount:u64) acquires Pool_tree, Pool {


    let is_sort = is_sorted(in,out);
    if(!is_sort){
        return add_lp(caller,out,in,out_amount,in_amount)
    };
    let coin1 = primary_fungible_store::withdraw(caller,in,in_amount);
    let coin2 =  primary_fungible_store::withdraw(caller,out,out_amount);

    let fa1 = fungible_asset::metadata_from_asset(&coin1);
    let fa2= fungible_asset::metadata_from_asset(&coin2);

    let pool_seed= get_pool_seed(fa1,fa2);
    let borrow = borrow_global_mut<Pool_tree>(get_pool_tree_address());
    assert!(borrow.pool_table.contains(pool_seed)==true,not_implemented( E_pool_already_exists));

    let obj_pool = *borrow.pool_table.borrow(pool_seed);

    //debug::print(&string_utils::format1(&b"swap obj pool = {}",obj_pool));

    let token_1_balance = fungible_asset::amount(&coin1);
    let token_2_balance =fungible_asset::amount(&coin2);

    let borrow =  borrow_global_mut<Pool>(object_address(borrow.pool_table.borrow(pool_seed)));
    let pool_signer = &generate_signer_for_extending(&borrow.extend);
    // if(fungible_asset::store_metadata(borrow.coin_1) == fungible_asset::metadata_from_asset(&coin1)){
    //     fungible_asset::deposit(borrow.coin_1 ,coin1);
    //     fungible_asset::deposit(borrow.coin_2,coin2);
    // }else{
    //     fungible_asset::deposit(borrow.coin_1 ,coin2);
    //     fungible_asset::deposit(borrow.coin_2,coin1);
    // };
    mint(caller, coin1,coin2,obj_pool,pool_signer,borrow);
    borrow.init_1 += token_1_balance ;
    borrow.init_2 += token_2_balance ;
    // borrow.init_price = ((token_2_balance*10000)/token_1_balance)/10000;

    emit(Add_LP{})
    }

     public entry fun add_pool(caller:&signer,pair_1:Object<Metadata>,pair_2:Object<Metadata>) acquires Pool_tree {

         let is_sort = is_sorted(pair_1,pair_2);
         if(!is_sort){
             return add_pool(caller,pair_2,pair_1)
         };

        let pool_seed= get_pool_seed(pair_1,pair_2);
        let borrow = borrow_global_mut<Pool_tree>(get_pool_tree_address());
        assert!(borrow.pool_table.contains(pool_seed)==false,not_implemented( E_pool_already_exists));

        let pool_obj_conf = &create_named_object(&get_signer(),*pool_seed.bytes());
        let pool_signer = & generate_signer(pool_obj_conf);

        let coin_1_store = create_store_for_pool(pool_signer,pair_1,false);
        let coin_2_store = create_store_for_pool(pool_signer,pair_2,false);

        let fee_1_store = create_store_for_pool(pool_signer,pair_1,true);
        let fee_2_store = create_store_for_pool(pool_signer,pair_2,true);

        let pool_extend = generate_extend_ref(pool_obj_conf);

        let lp_name = utf8(b"");
         lp_name.append(fungible_asset::name(pair_1));
         lp_name.append(fungible_asset::name(pair_2));
         lp_name.append(utf8(b"_LP"));
         //debug::print(&*lp_name.bytes());
        let lp_symbol = utf8(b"");
        lp_symbol.append(fungible_asset::symbol(pair_1));
        lp_symbol.append(utf8(b"-"));
        lp_symbol.append(fungible_asset::symbol(pair_2));
        let lp_conf = &create_named_object(pool_signer,*lp_name.bytes());

         // debug::print(&string_utils::format1(&b"create object address= {}",create_object_address(&address_of(pool_signer),*lp_name.bytes())));
         //
         // debug::print(&string_utils::format1(&b"lp pool signer = {}",address_of(pool_signer)));
         //debug::print(&object::address_from_constructor_ref(lp_conf));
        create_primary_store_enabled_fungible_asset(lp_conf,none<u128>(),lp_name, lp_symbol,8, utf8(b""), utf8(b""));
        let lp_mint = generate_mint_ref(lp_conf);
        let lp_burn = generate_burn_ref(lp_conf);
        let lp_tran = fungible_asset::generate_transfer_ref(lp_conf);
        let lp_extend = generate_extend_ref(lp_conf);

         //primary_fungible_store::mint(&lp_mint,address_from_constructor_ref(lp_conf),1);

        let new_pool = Pool{
            coin_1:coin_1_store,
            coin_2:coin_2_store,
            fee_1:fee_1_store,
            fee_2:fee_2_store,
            init_1:0,
            init_2:0,
            extend:pool_extend,
            LP_ref:LP_control {
                Mint_ref: lp_mint,
                Burn_ref: lp_burn,
                Tran_ref: lp_tran,
                extend_ref: lp_extend
            }
        };
        move_to(pool_signer,new_pool);
        let obj_pool = object_from_constructor_ref<Pool>(pool_obj_conf);
         //debug::print(&string_utils::format1(&b"Add LP obj pool = {}",obj_pool));
        borrow.pool_table.add(pool_seed, obj_pool);

        emit( Create_pool{});
    }

    inline fun get_pool_tree_address():address{
        let control_signer = &get_control_address();
        create_object_address(control_signer,SWAP_SEED)
    }

    fun init_module(caller:&signer){
        let control_signer = &get_signer();
        let conf = &create_named_object(control_signer,SWAP_SEED);
        let obj_extend = generate_extend_ref(conf);
        let pool_tree_signer = &generate_signer(conf);
        move_to(pool_tree_signer,Pool_tree{
            pool_tree_extend:obj_extend,
            pool_table:smart_table::new()
        });
    }
    #[view]
    public fun get_LP_metadata(pool_1:Object<Metadata>,pool_2:Object<Metadata>):Object<Metadata> acquires Pool_tree, Pool {
        let pool_seed= get_pool_seed(pool_1,pool_2);
        let borrow = borrow_global<Pool_tree>(get_pool_tree_address());
        assert!(borrow.pool_table.contains(pool_seed)==true,not_implemented( E_pool_already_exists));
        let pool_obj=borrow.pool_table.borrow( pool_seed);
        let pool = borrow_global<Pool>(object_address(pool_obj));
        let obj =object::address_to_object<Metadata>(object::address_from_extend_ref(&pool.LP_ref.extend_ref));
        obj
    }


    #[test(caller=@triplex,user=@0x1234)]
    fun test_swap (caller:&signer,user:&signer) acquires Pool_tree, Pool {
        ready_everythin(caller,user);
        let(apt_obj,gold_obj )=deploy(address_of(caller));
        primary_fungible_store::transfer(caller,apt_obj,address_of(user),100000000000);

        add_pool(caller,apt_obj,gold_obj);

        add_lp(caller,apt_obj,gold_obj,200000000000,200000000000);

        swap(user,apt_obj,gold_obj,5000000000,10000000);

        // debug::print(&utf8(b"Triplex balance"));
        // print_apt_balance(caller,apt_obj);
        // print_gold_balance(caller,gold_obj);
        //
        //
        // debug::print(&utf8(b"User balance"));
        // print_apt_balance(user,apt_obj);
        // print_gold_balance(user,gold_obj);

    }
    #[test(caller=@triplex,user=@0x1234)]
    fun test_add_pool (caller:&signer,user:&signer) acquires Pool_tree {
        ready_everythin(caller,user);
        let(apt_obj,gold_obj )=deploy(address_of(caller));
        add_pool(caller,apt_obj,gold_obj);
    }
    #[test(caller=@triplex,user=@0x1234)]
    fun test_add_lp (caller:&signer,user:&signer) {
        // ready_everythin(caller,user);
        // let(apt_obj,gold_obj )=deploy(address_of(caller));
        // add_pool(caller,apt_obj,gold_obj);
        // add_lp(caller,apt_obj,gold_obj,200000000000,200000000000);
        //
        // let lp_meta = get_LP_metadata(apt_obj,gold_obj);
        // debug::print(&string_utils::format1(&b"Balance of LP = {}",primary_fungible_store::balance(address_of(caller),lp_meta)));
    }

    #[test_inly]
    fun print_gold_balance(caller:&signer,gold:Object<Metadata>){
       let b= primary_fungible_store::balance(address_of(caller),gold);
        debug::print(&string_utils::format1(&b"Balance of Golf = {}",b/100000000));
    }
    #[test_inly]
    public fun print_apt_balance(caller:&signer,apt:Object<Metadata>){
        let b= primary_fungible_store::balance(address_of(caller),apt);
        debug::print(&string_utils::format1(&b"Balance of apt = {}",b/100000000));
    }
    #[test_only]
    public fun ready_everythin(caller:&signer,user:&signer){
        package_manager::call_package_init(caller);
        init_module(caller);
        create_account_for_test(address_of(caller));
    }
    #[test_only]
    public fun deploy(caller:address):(Object<Metadata>,Object<Metadata>){
        let coin_1_conf = &create_named_object(&get_signer(),b"coin1");
        let coin_2_conf = &create_named_object(&get_signer(),b"coin2");
        create_primary_store_enabled_fungible_asset(coin_1_conf,none<u128>(),utf8(b"APT"),utf8(b"APT"),8,utf8(b"https://cryptologos.cc/logos/aptos-apt-logo.png?v=040"),utf8(b""));
        create_primary_store_enabled_fungible_asset(coin_2_conf,none<u128>(),utf8(b"BTC"),utf8(b"BTC"),8,utf8(b"https://upload.wikimedia.org/wikipedia/commons/thumb/4/46/Bitcoin.svg/300px-Bitcoin.svg.png"),utf8(b""));
        let coin_1_mint = &generate_mint_ref(coin_1_conf);
        let coin_2_mint = &generate_mint_ref(coin_2_conf);


        primary_fungible_store::mint( coin_1_mint,caller,500000000000);
        primary_fungible_store::mint( coin_2_mint,caller,500000000000);

        (object_from_constructor_ref<Metadata>(coin_1_conf),object_from_constructor_ref<Metadata>(coin_2_conf))
    }
}
