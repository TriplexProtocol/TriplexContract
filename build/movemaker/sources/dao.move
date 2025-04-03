module triplex::dao {

    use std::error::not_implemented;
    use std::option::{Option, none, some};
    use std::signer::address_of;
    use std::string::String;
    use std::vector;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{Metadata, icon_uri};
    use aptos_framework::object::{Object, create_named_object, generate_signer, create_object_address};
    use aptos_framework::timestamp::now_seconds;
    use triplex::move_maker::{dao_add_rwa_asset, dao_add_mortgage_assset};
    use triplex::vault::add_to_vault_table;
    use triplex::package_manager::{get_control_address, get_signer};

    const Vote_seed : vector<u8> = b"vote";

    ///Not admin
   const E_not_admin :u64 =1;

    #[view]
    public fun get_vote_data(vote:String):(u64,u64) acquires Vote_tree {
        let control_address = get_control_address();
        let vote_tree = borrow_global<Vote_tree>(create_object_address(&control_address,Vote_seed));
        let (exiists ,index) = vector::find(&vote_tree.on_vote,|t| search_vote(t,vote));
        return (vote_tree.on_vote[index].record.vote_yes,vote_tree.on_vote[index].record.vote_no)
    }


    struct Vote_tree has key,store{
        on_vote:vector<Vote>,
        end_vote:SmartTable<String,Vote>
    }


    struct Vote has key,store{
        describe:String,
        mortgage_assset:Object<Metadata>,
        in_price_feed:vector<u8>,
        rwa_name:Option<String>,
        rwa_symbol:Option<String>,
        rwa_price_feed:Option<vector<u8>>,
        rwa_icon_url:Option<String>,
        record :Vote_number,
        expired_date:u64
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

    public entry fun create_vote_for_mortgage_assset(caller:&signer,in_price_feed:vector<u8>,mortgage_assset:Object<Metadata>,describe:String,expired_date:u64) acquires Vote_tree {
        assert!(address_of(caller)==@admin,not_implemented(E_not_admin));
        let control_address = get_control_address();
        let vote_tree = borrow_global_mut<Vote_tree>(create_object_address(&control_address,Vote_seed));
        let new_vote =Vote{
            describe,
            mortgage_assset,
            in_price_feed,
            rwa_name:none<String>(),
            rwa_symbol:none<String>(),
            rwa_icon_url:none<String>(),
            rwa_price_feed:none<vector<u8>>(),
            record: Vote_number{
                vote_yes:0,
                vote_no:0
            },
            expired_date
        };
        vote_tree.on_vote.push_back(new_vote);
    }
    public entry fun create_vote_for_rwa_assset(caller:&signer,in_price_feed:vector<u8>,mortgage_assset:Object<Metadata>,describe:String,name:String,symbol:String,icon_url:String,rwa_price_feed:vector<u8>,expired_date:u64) acquires Vote_tree {
        assert!(address_of(caller)==@admin,not_implemented(E_not_admin));
        let control_address = get_control_address();
        let vote_tree = borrow_global_mut<Vote_tree>(create_object_address(&control_address,Vote_seed));
        let new_vote =Vote{
            describe,
            mortgage_assset,
            in_price_feed,
            rwa_name:some(name),
            rwa_symbol:some(symbol),
            rwa_icon_url:some(icon_url),
            rwa_price_feed:some(rwa_price_feed),
            record: Vote_number{
                vote_yes:0,
                vote_no:0
            },
            expired_date
        };
        vote_tree.on_vote.push_back(new_vote);
    }

    public entry fun vote(caller:&signer,vote:String,vote_choose:bool) acquires Vote_tree {
        let control_address = get_control_address();
        let vote_tree = borrow_global_mut<Vote_tree>(create_object_address(&control_address,Vote_seed));
        let (exiists ,index) = vector::find(&vote_tree.on_vote,|t| search_vote(t,vote));
        if(exiists){
            if(vote_choose){
                vote_tree.on_vote[index].record.vote_yes += 1 ;
            }else{ vote_tree.on_vote[index].record.vote_no += 1 ;}
        };
        if(now_seconds() >= vote_tree.on_vote[index].expired_date){
            return end_vote(index)
        }
    }

    fun end_vote (index:u64) acquires Vote_tree {
        let control_address = get_control_address();
        let vote_tree = borrow_global_mut<Vote_tree>(create_object_address(&control_address,Vote_seed));
        let vote = vote_tree.on_vote.remove(index);
        if( vote.record.vote_yes >  vote.record.vote_no){
            //do something
            if(vote.rwa_icon_url.is_some()){
                //rwa
                dao_add_rwa_asset(vote.mortgage_assset,*vote.rwa_name.borrow(),*vote.rwa_symbol.borrow(),*vote.rwa_icon_url.borrow(),*vote.rwa_price_feed.borrow())
            }else{
                let symbol = fungible_asset::symbol(vote.mortgage_assset);
                let name = fungible_asset::name(vote.mortgage_assset);
                add_to_vault_table(&get_signer(),vote.mortgage_assset,name,symbol);
                dao_add_mortgage_assset(vote.mortgage_assset,vote.in_price_feed);
            };
        };
        vote_tree.end_vote.add( vote.describe, vote);
    }

    fun search_vote (v:&Vote,target:String):bool{
        v.describe == target
    }

    fun init_module (caller:&signer){
        let conf = &create_named_object(caller,Vote_seed);
        let vote_signer = &generate_signer(conf);
        move_to(vote_signer,Vote_tree{
            on_vote:vector::empty(),
            end_vote:smart_table::new(),
        });
    }

    public entry fun directly_add_rwa(caller:&signer,in_obj:Object<Metadata>,mortgage_assset:Object<Metadata>,describe:String,name:String,symbol:String,icon_url:String,rwa_price_feed:vector<u8>)  {
        dao_add_rwa_asset(in_obj,name,symbol,icon_url,rwa_price_feed);
    }
    public entry fun directly_add_mortgage(caller:&signer,mortgage_assset:Object<Metadata>,rwa_price_feed:vector<u8>) {

        dao_add_mortgage_assset(mortgage_assset,rwa_price_feed)
    }
}
