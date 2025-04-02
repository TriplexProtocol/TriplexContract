module triplex::dao {

    use std::acl::empty;
    use std::option::{Option, none, some};
    use std::string::String;
    use std::vector;
    use aptos_std::smart_table;

    use aptos_std::smart_table::SmartTable;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Object, create_named_object, generate_signer, create_object_address};
    use triplex::package_manager::{get_control_address};

    const Vote_seed : vector<u8> = b"vote";

    struct Vote_tree has key,store{
        on_vote:vector<Vote>,
        end_vote:SmartTable<String,Vote>
    }


    struct Vote has key,store{
        describe:String,
        mortgage_assset:Object<Metadata>,
        rwa_name:Option<String>,
        rwa_symbol:Option<String>,
        rwa_price_feed:Option<vector<u8>>,
        rwa_icon_url:Option<String>,
        record :Vote_number
    }
    struct Vote_number has key ,store{
        vote_yes:u64,
        vote_no:u64
    }

    #[view]
    public fun get_onvoteing():vector<String> acquires Vote_tree {
        let i =0;
        let control_address = get_control_address();
        let vote_tree = borrow_global<Vote_tree>(create_object_address(&control_address,Vote_seed));
        let r_v = vector::empty<String>()
;       while(i < vote_tree.on_vote.length()){
            r_v.push_back(vote_tree.on_vote[i].describe);
            i += 1;
        };
        r_v
    }

    public entry fun create_vote_for_mortgage_assset(caller:&signer,mortgage_assset:Object<Metadata>,describe:String) acquires Vote_tree {
        let control_address = get_control_address();
        let vote_tree = borrow_global_mut<Vote_tree>(create_object_address(&control_address,Vote_seed));
        let new_vote =Vote{
            describe,
            mortgage_assset,
            rwa_name:none<String>(),
            rwa_symbol:none<String>(),
            rwa_icon_url:none<String>(),
            rwa_price_feed:none<vector<u8>>(),
            record: Vote_number{
                vote_yes:0,
                vote_no:0
            }
        };
        vote_tree.on_vote.push_back(new_vote);
    }
    public entry fun create_vote_for_rwa_assset(caller:&signer,mortgage_assset:Object<Metadata>,describe:String,name:String,symbol:String,icon_url:String,rwa_price_feed:vector<u8>) acquires Vote_tree {
        let control_address = get_control_address();
        let vote_tree = borrow_global_mut<Vote_tree>(create_object_address(&control_address,Vote_seed));
        let new_vote =Vote{
            describe,
            mortgage_assset,
            rwa_name:some(name),
            rwa_symbol:some(symbol),
            rwa_icon_url:some(icon_url),
            rwa_price_feed:some(rwa_price_feed),
            record: Vote_number{
                vote_yes:0,
                vote_no:0
            }
        };
    }

    fun init_module (caller:&signer){
        let conf = &create_named_object(caller,Vote_seed);
        let vote_signer = &generate_signer(conf);
        move_to(vote_signer,Vote_tree{
            on_vote:vector::empty(),
            end_vote:smart_table::new(),
        });
    }
}
