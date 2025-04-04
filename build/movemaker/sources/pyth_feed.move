module triplex::pyth_feed {

    use std::error::not_implemented;
    use std::signer::address_of;

    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Object, address_to_object, object_address};

    const E_not_admin:u64 =1;
    ///without this feed id
    const E_not_exists_feed_id:u64 =2;

    struct Price_feed has key,store{
        feed:SmartTable<address,vector<u8>>
    }
    fun init_module(caller:&signer){
        move_to(caller,Price_feed{
            feed:smart_table::new()
        })
    }

    const Feed_id:vector<vector<u8>> = vector[
        x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e",//apt
        x"3b570b23359717a161e6f0ab8b5c742f3aafe6ab0b6b2d3bd9013c054ecd9daf",//stapt
        x"f9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b",//zbtc
        x"ca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6",//lzETH
    ];
    const Feed_coin :vector<address> = vector[
        @0xa,
        @0xb614bfdf9edc39b330bbf9c3c5bcd0473eee2f6d4e21748629cc367869ece627,
        @0xa64d2d6f5e26daf6a3552f51d4110343b1a8c8046d0a9e72fa4086a337f3236c,
        @0xae02f68520afd221a5cd6fda6f5500afedab8d0a2e19a916d6d8bc2b36e758db,
    ];

    public entry fun add_const (caller:&signer) acquires Price_feed {
        assert!(address_of(caller)==@admin,not_implemented(E_not_admin));
        let borrow = borrow_global_mut<Price_feed>(@triplex);
        for(i in 0 ..Feed_id.length() ){
            borrow.feed.add(Feed_coin[i],Feed_id[i]);
        };
    }

    #[view]
    public fun get_feed_id (in:Object<Metadata>):vector<u8> acquires Price_feed {
        let borrow = borrow_global<Price_feed>(@triplex);
        let obj_address= object_address<Metadata>(&in);
        assert!(borrow.feed.contains(obj_address) == true ,not_implemented(E_not_exists_feed_id));
        *borrow.feed.borrow(obj_address)
    }
}
