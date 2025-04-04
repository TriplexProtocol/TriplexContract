module triplex::package_manager {

    use aptos_framework::object::{ExtendRef, create_object_address, generate_signer_for_extending, create_named_object,
        generate_signer, generate_extend_ref
    };

    friend triplex::move_maker;
    friend triplex::dao;
    friend triplex::vault;
    friend  triplex::swap;




    const Seed :vector<u8> = b"asd";

    struct Control_ref has key,store{
        exten:ExtendRef
    }

    public(friend) fun get_signer():signer acquires Control_ref {
        let borrow = borrow_global<Control_ref>(create_object_address(&@triplex, Seed));
        generate_signer_for_extending(&borrow.exten)
    }

    public(friend) fun get_control_address():address{
        create_object_address(&@triplex, Seed)
    }


    fun init_module(caller:&signer){
        let conf = &create_named_object(caller,Seed);
        move_to(&generate_signer( conf),Control_ref{
            exten:generate_extend_ref(conf)
        })
    }
    #[test_only]
    public fun call_package_init(caller:&signer){
        init_module(caller);

    }
}
