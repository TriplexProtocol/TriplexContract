module triplex::pyth_feed {

    use std::error::not_implemented;
    use std::signer::address_of;
    use std::string::{String, utf8};
    use std::vector;

    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Object, address_to_object, object_address};

    const E_not_admin:u64 =1;
    ///without this feed id
    const E_not_exists_feed_id:u64 =2;
    ///without rwa icon
    const E_not_exists_rwa_icon:u64=3;
    ///without rwa feed id
    const E_not_exists_rwa_feed_id:u64=4;

    struct Price_feed has key,store{
        feed:SmartTable<address,vector<u8>>,
        rwa_asset:SmartTable<String,vector<u8>>,
        rwa_icon:SmartTable<String,String>
    }
    fun init_module(caller:&signer){
        move_to(caller,Price_feed{
            feed:smart_table::new(),
            rwa_asset:smart_table::new(),
            rwa_icon:smart_table::new()
        })
    }
    #[test_only]
    public fun call_pyth(caller:&signer) acquires Price_feed {
        init_module(caller);
        add_const (caller);
        add_rwa_const_asset(caller);
        add_rwa_const_icon(caller);
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

    const Rwa_feed_id:vector<vector<u8>> =vector[
        x"abb1a3382ab1c96282e4ee8c847acc0efdb35f0564924b35f3246e8f401b2a3d",//Google stock
        x"fbfb437d8a13c891ca7a27c8334ce1f4b23f7ec798edbaf161a3467291b24c18",//AVGO stock
        x"0b9c164fe24d3fcde513c7a5514a28bb0bcc1660ea4714c996d77d31142c331b",//MSTR stock
        x"30a19158f5a54c0adf8fb7560627343f22a1bc852b89d56be1accdc5dbf96d0e",//Gold
        x"321ba4d608fa75ba76d6d73daa715abcbdeb9dba02257f05a1b59178b49f599b",//silver
        x"c1b12769f6633798d45adfd62bfc70114839232e2949b01fb3d3f927d2606154",//EUR
        x"20a938f54b68f1f2ef18ea0328f6dd0747f8ea11486d22b021e83a900be89776",//JPY
        x"796d24444ff50728b58e94b1f53dc3a406b2f1ba9d0d0b91d4406c37491a6feb",//CHF
        x"31775e1d6897129e8a84eeba975778fb50015b88039e9bc140bbd839694ac0ae",//DOGE

    ];
    const Rwa_asset:vector<vector<u8>> =vector[
        b"Google",
        b"AVGO",
        b"MSTR",
        b"GOLD",
        b"SLIVER",
        b"EUR",
        b"JPY",
        b"CHF",
        b"DOGE",
    ];
    const RWA_icon:vector<vector<u8>> =vector[
        b"https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/48px-Google_%22G%22_logo.svg.png?20230822192911", //google icon
        b"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRdhAAiaZyXFYJjVZt0i_C26MTEUaQSbfCHWQ&s", //avgo
        b"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQkIhnD-2I5gD2HmOyOUbX8v6N2lRK7vdaCtg&s",//mstr
        b"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcS6seGydOKBUqE1ELrBNsfLkAjND4t4XlENhQ&s",//gold
        b"https://cdn-icons-png.flaticon.com/512/16680/16680504.png",//sliver
        b"https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/Euro_symbol.svg/2048px-Euro_symbol.svg.png",//eur
        b"https://ardlazaward.com/wp-content/uploads/2021/06/jpn.png",//jpy
        b"https://upload.wikimedia.org/wikipedia/commons/thumb/0/08/Flag_of_Switzerland_%28Pantone%29.svg/640px-Flag_of_Switzerland_%28Pantone%29.svg.png",//CHF
        b"https://cryptologos.cc/logos/dogecoin-doge-logo.png", // doge

    ];

    public entry fun add_const (caller:&signer) acquires Price_feed {
        //assert!(address_of(caller)==@admin ||address_of(caller)==@triplex,not_implemented(E_not_admin));
        let borrow = borrow_global_mut<Price_feed>(@triplex);
        for(i in 0 ..Feed_id.length() ){
            borrow.feed.add(Feed_coin[i],Feed_id[i])
        };
    }
    public entry fun add_rwa_const_asset (caller:&signer) acquires Price_feed {
        //assert!(address_of(caller)==@admin ||address_of(caller)==@triplex,not_implemented(E_not_admin));
        let borrow = borrow_global_mut<Price_feed>(@triplex);
        for(x in 0 .. Rwa_asset.length()){
            let spfecfic_key =utf8(Rwa_asset[x]);

            let specfic_id =Rwa_feed_id[x];
            borrow.rwa_asset.add(spfecfic_key,specfic_id);

        };
    }
    public entry fun add_rwa_const_icon (caller:&signer) acquires Price_feed {
        //assert!(address_of(caller)==@admin ||address_of(caller)==@triplex,not_implemented(E_not_admin));
        let borrow = borrow_global_mut<Price_feed>(@triplex);
        for(x in 0 .. Rwa_asset.length()){
            let spfecfic_key =utf8(Rwa_asset[x]);
            let specific_icon =utf8(RWA_icon[x]);

            borrow.rwa_icon.add(spfecfic_key,specific_icon);
        };
    }

    #[view]
    public fun get_feed_id (in:Object<Metadata>):vector<u8> acquires Price_feed {
        let borrow = borrow_global<Price_feed>(@triplex);
        let obj_address= object_address<Metadata>(&in);
        assert!(borrow.feed.contains(obj_address) == true ,not_implemented(E_not_exists_feed_id));
        *borrow.feed.borrow(obj_address)
    }

    #[view]
    public fun get_rwa_feed_id (rwa_asset:String):vector<u8> acquires Price_feed {
        let borrow = borrow_global<Price_feed>(@triplex);
        assert!(borrow.rwa_asset.contains(rwa_asset) == true ,not_implemented(E_not_exists_rwa_feed_id));
        *borrow.rwa_asset.borrow(rwa_asset)
    }
    #[view]
    public fun get_rwa_icon (rwa_asset:String):(String) acquires Price_feed {
        let borrow = borrow_global<Price_feed>(@triplex);
        assert!(borrow.rwa_icon.contains(rwa_asset) == true ,not_implemented(E_not_exists_rwa_icon));
        (*borrow.rwa_icon.borrow(rwa_asset))
    }
}
