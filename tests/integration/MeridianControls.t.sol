// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRoles } from "../../src/access/MeridianRoles.sol";
import { MeridianVault } from "../../src/vault/MeridianVault.sol";
import { MeridianFixture } from "../helpers/MeridianFixture.sol";

contract MeridianControlsTest is MeridianFixture {
    function testGlobalAndReceiverDepositLimitsCompose() external {
        uint256 configuredCap = 1000 * UNIT;
        vm.prank(ADMIN);
        vault.setDepositCap(configuredCap);

        _deposit(ALICE, 600 * UNIT);
        assertEq(vault.maxDeposit(ALICE), 400 * UNIT);

        vm.prank(ADMIN);
        vault.setReceiverAssetLimit(ALICE, 700 * UNIT);
        assertEq(vault.maxDeposit(ALICE), 100 * UNIT);

        uint256 supplied = 100 * UNIT + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianVault.MeridianVault__DepositLimitExceeded.selector, supplied, 100 * UNIT
            )
        );
        vm.prank(ALICE);
        vault.deposit(supplied, ALICE);

        assertEq(vault.maxDeposit(BOB), 400 * UNIT);
        _deposit(BOB, 400 * UNIT);
        assertEq(vault.totalAssets(), configuredCap);
        assertEq(vault.maxDeposit(ALICE), 0);
        assertEq(vault.maxDeposit(BOB), 0);
    }

    function testGuardianPauseAndAdminResumeDeposits() external {
        vm.prank(GUARDIAN);
        vault.pause();

        assertTrue(vault.paused());
        assertEq(vault.maxDeposit(ALICE), 0);

        vm.expectRevert(MeridianRoles.ContractPaused.selector);
        vm.prank(ALICE);
        vault.deposit(100 * UNIT, ALICE);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, vault.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        vault.unpause();

        vm.prank(ADMIN);
        vault.unpause();
        assertFalse(vault.paused());

        uint256 shares = _deposit(ALICE, 100 * UNIT);
        assertEq(shares, 100 * SHARE_UNIT);
    }

    function testOperationalRolesAreSeparatedAndConfigured() external {
        assertTrue(vault.hasRole(vault.KEEPER_ROLE(), KEEPER));
        assertTrue(vault.hasRole(vault.ALLOCATOR_ROLE(), ALLOCATOR));
        assertTrue(vault.hasRole(vault.GUARDIAN_ROLE(), GUARDIAN));
        assertFalse(vault.hasRole(vault.ALLOCATOR_ROLE(), OUTSIDER));

        _deposit(ALICE, 1000 * UNIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, vault.ALLOCATOR_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        vault.allocate(address(reserveStrategy), 100 * UNIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, vault.KEEPER_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        vault.checkpointStrategy(address(reserveStrategy));

        _allocate(address(reserveStrategy), 100 * UNIT);
        vm.prank(KEEPER);
        vault.checkpointStrategy(address(reserveStrategy));
        vm.prank(GUARDIAN);
        vault.pause();

        assertTrue(vault.paused());
        assertEq(vault.totalDebt(), 100 * UNIT);
    }

    function testIdleReserveAndRiskParameterBoundsAreEnforced() external {
        vm.prank(ADMIN);
        vault.setMinimumIdleBps(2000);
        _deposit(ALICE, 1000 * UNIT);

        _allocate(address(reserveStrategy), 800 * UNIT);
        assertEq(vault.idleAssets(), 200 * UNIT);

        uint256 supplied = 1 * UNIT;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianVault.MeridianVault__IdleReserveViolation.selector, 199 * UNIT, 200 * UNIT
            )
        );
        vm.prank(ALLOCATOR);
        vault.allocate(address(reserveStrategy), supplied);

        uint16 invalidIdleBps = vault.MAX_IDLE_BPS() + 1;
        vm.expectRevert(MeridianVault.MeridianVault__InvalidRiskParameter.selector);
        vm.prank(ADMIN);
        vault.setMinimumIdleBps(invalidIdleBps);

        uint16 invalidLossBps = vault.MAX_WITHDRAWAL_LOSS_BPS() + 1;
        vm.expectRevert(MeridianVault.MeridianVault__InvalidRiskParameter.selector);
        vm.prank(ADMIN);
        vault.setMaximumWithdrawalLossBps(invalidLossBps);
    }
}
