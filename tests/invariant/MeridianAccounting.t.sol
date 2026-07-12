// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianFixture } from "../helpers/MeridianFixture.sol";

contract MeridianAccountingProperties is MeridianFixture {
    function testFuzzDepositRedeemRoundTrip(uint96 rawAssets) external {
        uint256 assets = bound(rawAssets, MINIMUM_DEPOSIT, 5_000_000 * UNIT);
        uint256 balanceBefore = stablecoin.balanceOf(ALICE);
        uint256 shares = _deposit(ALICE, assets);

        vm.prank(ALICE);
        uint256 redeemed = vault.redeem(shares, ALICE, ALICE);

        assertApproxEqAbs(redeemed, assets, 1);
        assertApproxEqAbs(stablecoin.balanceOf(ALICE), balanceBefore, 1);
        assertEq(vault.balanceOf(ALICE), 0);
    }

    function testFuzzAllocationConservesManagedAssets(uint96 rawDeposit, uint16 rawBps) external {
        uint256 assets = bound(rawDeposit, 100 * UNIT, 5_000_000 * UNIT);
        uint256 allocationBps = bound(rawBps, 1000, 9000);
        uint256 allocation = assets * allocationBps / 10_000;

        _deposit(ALICE, assets);
        uint256 managedBefore = vault.totalAssets();
        _allocate(address(lockedStrategy), allocation);

        assertApproxEqAbs(vault.totalAssets(), managedBefore, 1);
        assertEq(registry.totalDebt(), allocation);
        assertEq(yieldSource.principalOf(address(lockedStrategy)), allocation);
    }

    function testFuzzProRataSharesRemainConsistent(uint96 rawAssets) external {
        uint256 assets = bound(rawAssets, MINIMUM_DEPOSIT, 4_000_000 * UNIT);
        uint256 aliceShares = _deposit(ALICE, assets);
        uint256 bobShares = _deposit(BOB, assets);

        assertApproxEqAbs(aliceShares, bobShares, 1);
        assertApproxEqAbs(vault.convertToAssets(aliceShares), assets, 1);
        assertApproxEqAbs(vault.convertToAssets(bobShares), assets, 1);
    }
}
