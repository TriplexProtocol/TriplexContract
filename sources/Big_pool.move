module triplex::Big_pool {
    use std::signer::address_of;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{FungibleStore, FungibleAsset, create_store, Metadata};
    use aptos_framework::object::{Object, create_object_address, create_object, object_from_constructor_ref,
        create_named_object, generate_signer
    };
    use triplex::package_manager::{get_control_address, get_signer};

    const E_not_Admin :u64 =1 ;

    const BIG_pool_SEED : vector<u8> = b"asad";
    struct BIG_pool has key,store{
        store:Object<FungibleStore>
    }

    public entry fun initlise(caller:&signer , in:Object<Metadata>){
        assert!(address_of(caller) == @admin,E_not_Admin);
        let conf = create_named_object(&get_signer(),BIG_pool_SEED);
        let st=create_store( &conf,in);
        move_to(&generate_signer(&conf),BIG_pool{
            store:st
        });
    }
    public fun deposite_to_big_pool(in:FungibleAsset) acquires BIG_pool {
        let borrow = borrow_global<BIG_pool>(create_object_address(&get_control_address(), BIG_pool_SEED));
        fungible_asset::deposit(borrow.store,in);
    }
}
