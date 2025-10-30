module cetusclmmvault::cetusclmmvault;

use sui::{
    table::{Self, Table},
    balance,
    coin::{Self, TreasuryCap, Coin},
    clock::Clock
};
use cetus_clmm::{
    config::GlobalConfig,
    pool::{Self, Pool},
    position::{Self, Position}
};

const Init_Coin_Amount: u128 = 1000_000_000_000_000;
const VERSION: u64 = 1;

const ETreasuryNotZero: u64 = 1001;

public struct AdminCap has key, store {
    id: UID,
}

public struct VaultManager<phantom T> has key {
    id: UID,
    owner: address,
    position: Option<Position>,
    treasury: TreasuryCap<T>,
    pool_id: ID,
}

public struct GlobalRecord has key {
    id: UID,
    record: Table<ID, ID>,
}

public struct Version has key {
    id: UID,
    version: u64,
}

fun init(ctx: &mut TxContext) {
    let deployer = ctx.sender();
    
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    transfer::public_transfer(admin_cap, deployer);

    let record = GlobalRecord {
        id: object::new(ctx),
        record: table::new<ID, ID>(ctx),
    };
    transfer::share_object(record);

    let version = Version {
        id: object::new(ctx),
        version: VERSION,
    };
    transfer::share_object(version);
}

#[allow(lint(self_transfer))]
public fun create_vault_manager<T>(
    config: &mut GlobalRecord,
    mut treasury: TreasuryCap<T>,
    position: Position,
    _: &AdminCap,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(coin::total_supply(&treasury) == 0, ETreasuryNotZero);
    let liquidity = position::liquidity(&position);
    let init_amount = std::u128::min(liquidity, Init_Coin_Amount);
    let lp_coin = coin::mint<T>(&mut treasury, init_amount as u64, ctx);
    transfer::public_transfer(lp_coin, sender);
    let pool_id = position::pool_id(&position);
    let vault_manager = VaultManager {
        id: object::new(ctx),
        owner: sender,
        position: option::some(position),
        treasury,
        pool_id,
    };
    table::add<ID, ID>(&mut config.record, pool_id, object::id(&vault_manager));
    transfer::share_object(vault_manager);
}

public fun take_position<T>(
    vault_manager: &mut VaultManager<T>,
    _: &AdminCap,
): Position {
    std::option::extract<Position>(&mut vault_manager.position)
}

public fun return_position<T>(
    vault_manager: &mut VaultManager<T>,
    position: Position,
    _: &AdminCap,
) {
    assert!(vault_manager.pool_id == position::pool_id(&position));
    std::option::fill<Position>(&mut vault_manager.position, position);
}

public fun borrow_position<T>(
    vault_manager: &VaultManager<T>,
): &Position {
    std::option::borrow<Position>(&vault_manager.position)
}

public fun borrow_mut_position<T>(
    vault_manager: &mut VaultManager<T>,
    _: &AdminCap,
): &mut Position {
    std::option::borrow_mut<Position>(&mut vault_manager.position)
}

public fun do_deposit<T, CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    vault_manager: &mut VaultManager<T>,
    coin_a: Coin<CoinTypeA>,
    coin_b: Coin<CoinTypeB>,
    delta_liquidity: u128,
    clock: &Clock,
    version: &Version,
    ctx: &mut TxContext,
): Coin<T> {
    check_version(version);
    
    let last_liquidity = position::liquidity(option::borrow(&vault_manager.position));
    let last_total_supply = coin::total_supply(&vault_manager.treasury);

    let receipt = pool::add_liquidity<CoinTypeA, CoinTypeB>(
        config,
        pool,
        option::borrow_mut(&mut vault_manager.position),
        delta_liquidity,
        clock
    );
    pool::repay_add_liquidity(config, pool, coin_a.into_balance(), coin_b.into_balance(), receipt);

    let (fee_a, fee_b) = pool::collect_fee(
        config,
        pool,
        option::borrow(&vault_manager.position),
        false
    );

    transfer::public_transfer(fee_a.into_coin(ctx), vault_manager.owner);
    transfer::public_transfer(fee_b.into_coin(ctx), vault_manager.owner);

    let new_mint_amount = mul_div_u128(last_total_supply as u128, delta_liquidity, last_liquidity) as u64;

    coin::mint<T>(&mut vault_manager.treasury, new_mint_amount, ctx)
}

public fun do_withdraw<T, CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    vault_manager: &mut VaultManager<T>,
    lp_coin: Coin<T>,
    clock: &Clock,
    version: &Version,
    ctx: &mut TxContext,
): (Coin<CoinTypeA>, Coin<CoinTypeB>) {
    check_version(version);

    let last_liquidity = position::liquidity(option::borrow(&vault_manager.position));
    let last_total_supply = coin::total_supply(&vault_manager.treasury);

    let burn_amount = coin::burn<T>(&mut vault_manager.treasury, lp_coin);
    let delta_liquidity = mul_div_u128(burn_amount as u128, last_liquidity, last_total_supply as u128);

    let (mut balance_a, mut balance_b) = pool::remove_liquidity<CoinTypeA, CoinTypeB>(
        config,
        pool,
        option::borrow_mut(&mut vault_manager.position),
        delta_liquidity,
        clock
    );

    let (mut fee_a, mut fee_b) = pool::collect_fee(
        config,
        pool,
        option::borrow(&vault_manager.position),
        false
    );

    let fee_a_user_amount = mul_div_u64(burn_amount, balance::value<CoinTypeA>(&fee_a), last_total_supply);
    let fee_b_user_amount = mul_div_u64(burn_amount, balance::value<CoinTypeB>(&fee_b), last_total_supply);

    let fee_a_user = balance::split<CoinTypeA>(&mut fee_a, fee_a_user_amount);
    let fee_b_user = balance::split<CoinTypeB>(&mut fee_b, fee_b_user_amount);

    balance::join<CoinTypeA>(&mut balance_a, fee_a_user);
    balance::join<CoinTypeB>(&mut balance_b, fee_b_user);

    transfer::public_transfer(fee_a.into_coin(ctx), vault_manager.owner);
    transfer::public_transfer(fee_b.into_coin(ctx), vault_manager.owner);

    (balance_a.into_coin(ctx), balance_b.into_coin(ctx))
}

fun check_version(version: &Version) {
    assert!(version.version == VERSION);
}

public fun update_version(version: &mut Version, _: &AdminCap) {
    assert!(version.version < VERSION);
    version.version = VERSION;
}

public fun update_owner(vault_manager: &mut VaultManager, owner: address, _: &AdminCap) {
    vault_manager.owner = owner;
}

fun mul_div_u64(num1: u64, num2: u64, denom: u64): u64 {
    let r = ((num1 as u128) * (num2 as u128)) / (denom as u128);
    (r as u64)
}

fun mul_div_u128(num1: u128, num2: u128, denom: u128): u128 {
    let r = ((num1 as u256) * (num2 as u256)) / (denom as u256);
    (r as u128)
}
