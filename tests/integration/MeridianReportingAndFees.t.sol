// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianTypes } from "../../src/types/MeridianTypes.sol";
import { MeridianFixture } from "../helpers/MeridianFixture.sol";

contract MeridianReportingAndFeesTest is MeridianFixture {
    function testCheckpointRecordsCurrentStrategyValues() external {
        uint256 deposited = 2000 * UNIT;
        uint256 allocation = 1000 * UNIT;
        _deposit(ALICE, deposited);
        _allocate(address(lockedStrategy), allocation);

        vm.prank(KEEPER);
        MeridianTypes.StrategyReport memory report =
            vault.checkpointStrategy(address(lockedStrategy));

        assertEq(report.strategy, address(lockedStrategy));
        assertEq(report.estimatedAssets, allocation);
        assertEq(report.liquidAssets, 0);
        assertEq(report.realizedGain, 0);
        assertEq(report.realizedLoss, 0);
        assertEq(report.debtPayment, 0);
        assertEq(report.timestamp, block.timestamp);

        MeridianTypes.StrategyState memory state =
            registry.getStrategyState(address(lockedStrategy));
        assertEq(state.lastEstimatedAssets, allocation);
        assertEq(state.lastLiquidAssets, 0);
        assertEq(state.lastReport, block.timestamp);
        assertEq(state.totalGain, 0);
        assertEq(state.totalLoss, 0);
        assertEq(vault.totalAssets(), deposited);
    }

    function testFundedSettledYieldCanBeHarvested() external {
        uint256 deposited = 2000 * UNIT;
        uint256 allocation = 1000 * UNIT;
        uint256 gain = 100 * UNIT;
        uint16 performanceFeeBps = 1000;

        _setVaultFees(0, 0, performanceFeeBps);
        _deposit(ALICE, deposited);
        _allocate(address(lockedStrategy), allocation);
        _fundSettledYield(gain);

        uint256 supplyBefore = vault.totalSupply();
        vm.prank(KEEPER);
        MeridianTypes.StrategyReport memory report =
            vault.harvestStrategy(address(lockedStrategy), abi.encode(uint256(0), false));

        uint256 feeAssets = gain * performanceFeeBps / 10_000;
        uint256 expectedFeeShares =
            feeAssets * (supplyBefore + 1000) / (vault.totalAssets() + 1 - feeAssets);

        assertEq(report.strategy, address(lockedStrategy));
        assertEq(report.realizedGain, gain);
        assertEq(report.realizedLoss, 0);
        assertEq(report.estimatedAssets, allocation + gain);
        assertEq(report.liquidAssets, gain);
        assertEq(lockedStrategy.cumulativeRealizedGain(), gain);
        assertEq(stablecoin.balanceOf(address(lockedStrategy)), gain);
        assertEq(yieldSource.quotedYieldOf(address(lockedStrategy)), 0);
        assertEq(yieldSource.settledYieldOf(address(lockedStrategy)), 0);
        assertEq(vault.totalAssets(), deposited + gain);
        assertEq(vault.balanceOf(TREASURY), expectedFeeShares);

        MeridianTypes.StrategyState memory state =
            registry.getStrategyState(address(lockedStrategy));
        assertEq(state.lastEstimatedAssets, allocation + gain);
        assertEq(state.lastLiquidAssets, gain);
        assertEq(state.totalGain, gain);
    }

    function testDepositAndWithdrawalFeesReachTreasury() external {
        uint256 grossDeposit = 1000 * UNIT;
        uint16 depositFeeBps = 100;
        uint16 withdrawalFeeBps = 50;
        _setVaultFees(depositFeeBps, withdrawalFeeBps, 0);

        uint256 aliceBalanceBefore = stablecoin.balanceOf(ALICE);
        uint256 expectedShares = vault.previewDeposit(grossDeposit);
        uint256 shares = _deposit(ALICE, grossDeposit);

        uint256 depositFee = grossDeposit * depositFeeBps / 10_000;
        assertEq(shares, expectedShares);
        assertEq(shares, 990 * SHARE_UNIT);
        assertEq(stablecoin.balanceOf(TREASURY), depositFee);
        assertEq(vault.totalAssets(), grossDeposit - depositFee);

        uint256 expectedAssets = vault.previewRedeem(shares);
        vm.prank(ALICE);
        uint256 redeemedAssets = vault.redeem(shares, ALICE, ALICE);

        uint256 withdrawalFee = (grossDeposit - depositFee) * withdrawalFeeBps / 10_000;
        assertEq(redeemedAssets, expectedAssets);
        assertEq(redeemedAssets, grossDeposit - depositFee - withdrawalFee);
        assertEq(stablecoin.balanceOf(TREASURY), depositFee + withdrawalFee);
        assertEq(stablecoin.balanceOf(ALICE), aliceBalanceBefore - depositFee - withdrawalFee);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }
}
