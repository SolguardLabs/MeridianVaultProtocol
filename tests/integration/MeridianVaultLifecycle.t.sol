// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianTypes } from "../../src/types/MeridianTypes.sol";
import { MeridianFixture } from "../helpers/MeridianFixture.sol";

contract MeridianVaultLifecycleTest is MeridianFixture {
    function testDepositMintRedeemAndWithdrawLifecycle() external {
        uint256 depositAssets = 1000 * UNIT;
        uint256 expectedDepositShares = vault.previewDeposit(depositAssets);

        vm.prank(ALICE);
        uint256 depositShares = vault.deposit(depositAssets, ALICE);

        assertEq(depositShares, expectedDepositShares);
        assertEq(depositShares, 1000 * SHARE_UNIT);
        assertEq(vault.balanceOf(ALICE), depositShares);
        assertEq(vault.totalAssets(), depositAssets);

        uint256 sharesToMint = 250 * SHARE_UNIT;
        uint256 expectedMintAssets = vault.previewMint(sharesToMint);
        uint256 bobBalanceBefore = stablecoin.balanceOf(BOB);

        vm.prank(BOB);
        uint256 mintAssets = vault.mint(sharesToMint, BOB);

        assertEq(mintAssets, expectedMintAssets);
        assertEq(mintAssets, 250 * UNIT);
        assertEq(stablecoin.balanceOf(BOB), bobBalanceBefore - mintAssets);
        assertEq(vault.balanceOf(BOB), sharesToMint);

        uint256 sharesToRedeem = 250 * SHARE_UNIT;
        uint256 expectedRedeemedAssets = vault.previewRedeem(sharesToRedeem);
        uint256 aliceBalanceBefore = stablecoin.balanceOf(ALICE);

        vm.prank(ALICE);
        uint256 redeemedAssets = vault.redeem(sharesToRedeem, ALICE, ALICE);

        assertEq(redeemedAssets, expectedRedeemedAssets);
        assertEq(redeemedAssets, 250 * UNIT);
        assertEq(stablecoin.balanceOf(ALICE), aliceBalanceBefore + redeemedAssets);

        uint256 assetsToWithdraw = 100 * UNIT;
        uint256 expectedBurnedShares = vault.previewWithdraw(assetsToWithdraw);

        vm.prank(BOB);
        uint256 burnedShares = vault.withdraw(assetsToWithdraw, BOB, BOB);

        assertEq(burnedShares, expectedBurnedShares);
        assertEq(burnedShares, 100 * SHARE_UNIT);
        assertEq(vault.balanceOf(BOB), 150 * SHARE_UNIT);
        assertEq(vault.totalAssets(), 900 * UNIT);
        assertEq(vault.totalSupply(), 900 * SHARE_UNIT);
    }

    function testAllocationKeepsManagedAssetsConstant() external {
        uint256 deposited = 2000 * UNIT;
        uint256 allocation = 1200 * UNIT;
        _deposit(ALICE, deposited);

        uint256 managedBefore = vault.totalAssets();
        uint256 allocated = _allocate(address(lockedStrategy), allocation);

        assertEq(allocated, allocation);
        assertEq(vault.totalAssets(), managedBefore);
        assertEq(vault.idleAssets(), deposited - allocation);
        assertEq(vault.strategyAssets(), allocation);
        assertEq(vault.totalDebt(), allocation);
        assertEq(registry.totalReportedAssets(), allocation);
        assertEq(yieldSource.principalOf(address(lockedStrategy)), allocation);
        assertEq(lockedStrategy.accountedAssets(), allocation);

        MeridianTypes.StrategyState memory state =
            registry.getStrategyState(address(lockedStrategy));
        assertEq(state.debt, allocation);
        assertEq(state.lastEstimatedAssets, allocation);
        assertEq(state.lastLiquidAssets, 0);
    }

    function testUnlockedCapitalCanBeRecoveredToIdleBalance() external {
        uint256 deposited = 2000 * UNIT;
        uint256 allocation = 1500 * UNIT;
        uint256 requested = 600 * UNIT;
        _deposit(ALICE, deposited);
        _allocate(address(lockedStrategy), allocation);

        vm.warp(block.timestamp + LOCK_DURATION + 1);

        vm.prank(ALLOCATOR);
        (uint256 withdrawn, uint256 loss) =
            vault.recoverStrategyLiquidity(address(lockedStrategy), requested);

        assertEq(withdrawn, requested);
        assertEq(loss, 0);
        assertEq(vault.idleAssets(), deposited - allocation + requested);
        assertEq(yieldSource.principalOf(address(lockedStrategy)), allocation - requested);
        assertEq(vault.totalDebt(), allocation - requested);
        assertEq(vault.totalAssets(), deposited);

        MeridianTypes.StrategyState memory state =
            registry.getStrategyState(address(lockedStrategy));
        assertEq(state.debt, allocation - requested);
        assertEq(state.lastEstimatedAssets, allocation - requested);
        assertEq(state.lastLiquidAssets, allocation - requested);
    }

    function testWithdrawalQueueUsesBothStrategiesInOrder() external {
        uint256 deposited = 2000 * UNIT;
        uint256 reserveAllocation = 500 * UNIT;
        uint256 lockedAllocation = 1000 * UNIT;
        uint256 withdrawal = 1200 * UNIT;

        _deposit(ALICE, deposited);
        _allocate(address(reserveStrategy), reserveAllocation);
        _allocate(address(lockedStrategy), lockedAllocation);

        vm.prank(ADMIN);
        yieldSource.unlockPrincipal(address(lockedStrategy), lockedAllocation);

        address[] memory queue = registry.withdrawalQueue();
        assertEq(queue.length, 2);
        assertEq(queue[0], address(reserveStrategy));
        assertEq(queue[1], address(lockedStrategy));

        uint256 expectedShares = vault.previewWithdraw(withdrawal);
        vm.prank(ALICE);
        uint256 burnedShares = vault.withdraw(withdrawal, ALICE, ALICE);

        assertEq(burnedShares, expectedShares);
        assertEq(stablecoin.balanceOf(address(reserveStrategy)), RESERVE_FLOOR);
        assertEq(yieldSource.principalOf(address(lockedStrategy)), lockedAllocation - 250 * UNIT);
        assertEq(vault.totalDebt(), 800 * UNIT);
        assertEq(vault.strategyAssets(), 800 * UNIT);
        assertEq(vault.idleAssets(), 0);
        assertEq(vault.totalAssets(), deposited - withdrawal);
        assertEq(vault.balanceOf(ALICE), 800 * SHARE_UNIT);
    }
}
