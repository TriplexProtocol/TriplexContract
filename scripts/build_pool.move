
script {
    use std::string::utf8;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::paired_metadata;
    use triplex::dao;
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
    fun buuild_pool(caller:&signer) {
        let apt_pair_Data =paired_metadata<AptosCoin>();
        dao::directly_add_mortgage(caller,apt_pair_Data.destroy_some());
        for (i in 0..Rwa_asset.length()){
            let specfic_string = utf8(Rwa_asset[i]);
            dao::directly_add_rwa(caller,apt_pair_Data.destroy_some(),specfic_string)
        };
    }
}
