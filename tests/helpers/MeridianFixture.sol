// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianValuationPolicy } from "../../src/oracle/MeridianValuationPolicy.sol";
import { MockStablecoin } from "../../src/mocks/MockStablecoin.sol";
import { MockYieldSource } from "../../src/mocks/MockYieldSource.sol";
import { LockedYieldStrategy } from "../../src/strategies/LockedYieldStrategy.sol";
import { ReserveStrategy } from "../../src/strategies/ReserveStrategy.sol";
import { MeridianTypes } from "../../src/types/MeridianTypes.sol";
import { MeridianFeePolicy } from "../../src/vault/MeridianFeePolicy.sol";
import { MeridianVault } from "../../src/vault/MeridianVault.sol";
import { StrategyRegistry } from "../../src/vault/StrategyRegistry.sol";
import { TestBase } from "./TestBase.sol";

abstract contract MeridianFixture is TestBase {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant KEEPER = address(0xBEEF);
    address internal constant ALLOCATOR = address(0xA110C);
    address internal constant GUARDIAN = address(0x600D);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant ALICE = address(0xB0B);
    address internal constant BOB = address(0xCAFE);
    address internal constant OUTSIDER = address(0xBAD);

    uint256 internal constant UNIT = 1e6;
    uint256 internal constant SHARE_UNIT = 1e9;
    uint256 internal constant TOKEN_CAP = 100_000_000 * UNIT;
    uint256 internal constant VAULT_CAP = 20_000_000 * UNIT;
    uint256 internal constant USER_BALANCE = 10_000_000 * UNIT;
    uint256 internal constant MINIMUM_DEPOSIT = 1 * UNIT;
    uint256 internal constant STRATEGY_DEBT_LIMIT = 10_000_000 * UNIT;
    uint256 internal constant RESERVE_CAPACITY = 5_000_000 * UNIT;
    uint256 internal constant RESERVE_FLOOR = 50 * UNIT;
    uint64 internal constant LOCK_DURATION = 7 days;

    MockStablecoin internal stablecoin;
    MeridianValuationPolicy internal valuationPolicy;
    StrategyRegistry internal registry;
    MeridianFeePolicy internal feePolicy;
    MeridianVault internal vault;
    MockYieldSource internal yieldSource;
    LockedYieldStrategy internal lockedStrategy;
    ReserveStrategy internal reserveStrategy;

    function setUp() public virtual {
        stablecoin = new MockStablecoin(ADMIN, "Meridian USD", "mUSD", 6, TOKEN_CAP);

        MeridianValuationPolicy.Bounds memory bounds = MeridianValuationPolicy.Bounds({
            maxIncreaseBps: 50_000,
            maxDecreaseBps: 10_000,
            minimumLiquidityBps: 0,
            minimumDelay: 0,
            maximumDelay: 30 days,
            configured: true
        });
        valuationPolicy = new MeridianValuationPolicy(ADMIN, bounds);
        registry = new StrategyRegistry(ADMIN, address(stablecoin), valuationPolicy);
        feePolicy = new MeridianFeePolicy(ADMIN, TREASURY, 0, 0, 0);
        vault = new MeridianVault(
            ADMIN,
            address(stablecoin),
            registry,
            feePolicy,
            "Meridian Stable Vault",
            "msvUSD",
            VAULT_CAP,
            MINIMUM_DEPOSIT
        );

        vm.prank(ADMIN);
        registry.bindVault(address(vault));

        yieldSource = new MockYieldSource(address(stablecoin), ADMIN, LOCK_DURATION);
        lockedStrategy = new LockedYieldStrategy(
            address(stablecoin), address(vault), address(registry), address(yieldSource)
        );
        reserveStrategy = new ReserveStrategy(
            address(stablecoin), address(vault), address(registry), RESERVE_CAPACITY, RESERVE_FLOOR
        );

        vm.startPrank(ADMIN);
        registry.addStrategy(_strategyConfig(address(lockedStrategy)));
        registry.addStrategy(_strategyConfig(address(reserveStrategy)));

        address[] memory queue = new address[](2);
        queue[0] = address(reserveStrategy);
        queue[1] = address(lockedStrategy);
        registry.setWithdrawalQueue(queue);

        vault.grantRole(vault.KEEPER_ROLE(), KEEPER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), ALLOCATOR);
        vault.grantRole(vault.GUARDIAN_ROLE(), GUARDIAN);

        stablecoin.mint(ALICE, USER_BALANCE);
        stablecoin.mint(BOB, USER_BALANCE);
        vm.stopPrank();

        vm.prank(ALICE);
        stablecoin.approve(address(vault), type(uint256).max);
        vm.prank(BOB);
        stablecoin.approve(address(vault), type(uint256).max);
    }

    function _strategyConfig(address strategy)
        internal
        pure
        returns (MeridianTypes.StrategyConfig memory config)
    {
        config = MeridianTypes.StrategyConfig({
            strategy: strategy,
            debtLimit: uint128(STRATEGY_DEBT_LIMIT),
            minDebtChange: uint96(UNIT),
            targetBps: 0,
            maxBps: 10_000,
            status: MeridianTypes.StrategyStatus.Active
        });
    }

    function _deposit(address account, uint256 assets) internal returns (uint256 shares) {
        vm.prank(account);
        shares = vault.deposit(assets, account);
    }

    function _allocate(address strategy, uint256 assets) internal returns (uint256 allocated) {
        vm.prank(ALLOCATOR);
        allocated = vault.allocate(strategy, assets);
    }

    function _fundSettledYield(uint256 assets) internal {
        vm.startPrank(ADMIN);
        stablecoin.mint(address(yieldSource), assets);
        yieldSource.quoteYield(address(lockedStrategy), assets);
        yieldSource.settleYield(address(lockedStrategy), assets);
        vm.stopPrank();
    }

    function _setVaultFees(uint16 depositFeeBps, uint16 withdrawalFeeBps, uint16 performanceFeeBps)
        internal
    {
        vm.prank(ADMIN);
        feePolicy.setVaultSchedule(
            address(vault), depositFeeBps, withdrawalFeeBps, performanceFeeBps
        );
    }
}
