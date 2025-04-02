module triplex::vault {

    use std::error::not_implemented;
    use std::option;
    use std::option::none;
    use std::signer::address_of;
    use std::string;
    use std::string::{utf8, String};
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{Metadata, MintRef, BurnRef, TransferRef, generate_mint_ref, FungibleStore};
    use aptos_framework::object;
    use aptos_framework::object::{create_named_object, Object, generate_signer, object_from_constructor_ref, ExtendRef,
        create_object_address
    };
    use aptos_framework::primary_fungible_store;
    use aptos_framework::primary_fungible_store::create_primary_store_enabled_fungible_asset;
    use aptos_token_objects::token::generate_burn_ref;
    use triplex::package_manager::{get_signer, get_control_address};

    //tpx-usd
    const TPX_SEED : vector<u8> = b"Tpxseed";
    const ICON_URL : vector<u8> = b"";
    const Project_URL : vector<u8> = b"https://github.com/TriplexProtocol";

    ///E not admin
    const E_not_admin :u64 =1 ;

    struct Control_ref has key,store{
        obj_meta:Object<Metadata>,
        mint_ref : MintRef,
        burn_ref : BurnRef,
        transfer_ref : TransferRef
    }

    struct Table_of_Vault has key,store{
        accept_asset:SmartTable<Object<Metadata>,Object<Vault>>,
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
    }

    public(friend) fun create_vault(caller:&signer,
                                    asset_metadata: Object<Metadata>,
                                    name: String,
                                    symbol: String,
                                    decimals: u8,
    ):Object<Vault> acquires VaultState {
        let constructor_ref = object::create_named_object(caller, *string::bytes(&symbol));
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            string::utf8(b""),  // Collection URI
            string::utf8(b""),  // Project URI
        );

        let share_metadata = object::object_from_constructor_ref<Metadata>(&constructor_ref);

        // Create store for underlying assets
        let asset_store = fungible_asset::create_store(&constructor_ref, asset_metadata);

        // Get mint and burn capabilities
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

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
        };

        move_to(&object::generate_signer(&constructor_ref), vault_config);
        object::object_from_constructor_ref(&constructor_ref)
    }



    public entry fun  pledge_to_get_tpxusd_CO<CoinA>(){

    }

    public entry fun  pledge_to_get_tpxusd_FA(){

    }

    public entry fun  pledge_to_get_tpxusd(){

    }

    public(friend) fun add_to_vault_table(caller:&signer,pledge_asset:Object<Metadata>,name:String,symbol:String) acquires Table_of_Vault, VaultState {
        let borrow = borrow_global_mut<Table_of_Vault>(create_object_address(&get_control_address(),TPX_SEED));
        let new_vault = create_vault(caller,pledge_asset,name,symbol,8);
        borrow.accept_asset.add(pledge_asset,new_vault);
    }


    public entry fun initlize(caller:&signer){
        assert!(address_of(caller)==@admin,not_implemented(E_not_admin));
        let conf = &create_named_object(&get_signer(),TPX_SEED);
        create_primary_store_enabled_fungible_asset(conf ,none<u128>(),utf8(b"TPXusd"),utf8(b"TPXUSD"),8,utf8(ICON_URL),utf8(Project_URL ));
        let new=Table_of_Vault{
            accept_asset:smart_table::new(),
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


}
