module cetusclmmvault::lpcoin;

use sui::coin_registry;


public struct LPCOIN has drop {}

fun init(witness: LPCOIN, ctx: &mut TxContext) {
    let (builder, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        6, // Decimals
        b"LPCOIN".to_string(), // Symbol
        b"LP Coin".to_string(), // Name
        b"Standard Liquidity Provider Coin".to_string(), // Description
        b"https://example.com/my_coin.png".to_string(), // Icon URL
        ctx,
    );

    let metadata_cap = builder.finalize(ctx);
    transfer::public_transfer(treasury_cap, ctx.sender());
    transfer::public_transfer(metadata_cap, ctx.sender());
}