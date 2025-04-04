script {
    use triplex::Big_pool;
    use triplex::vault;
    use triplex::pyth_feed::{add_const, add_rwa_const_asset, add_rwa_const_icon};

    fun init_ready(caller:&signer) {
        add_const(caller);
        add_rwa_const_asset(caller);
        add_rwa_const_icon(caller);
        vault::initlize(caller);
        let tpxiusd = vault::get_tpxusd_metadata();
        Big_pool::initlise(caller,tpxiusd);
    }
}
