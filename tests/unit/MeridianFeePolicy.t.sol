// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRoles } from "../../src/access/MeridianRoles.sol";
import { MeridianFeePolicy } from "../../src/vault/MeridianFeePolicy.sol";
import { TestBase } from "../helpers/TestBase.sol";

contract MeridianFeePolicyTest is TestBase {
    MeridianFeePolicy internal policy;

    address internal constant OWNER = address(0xA11CE);
    address internal constant TREASURY = address(0xBEEF);
    address internal constant NEW_TREASURY = address(0xCAFE);
    address internal constant VAULT = address(0xB0B);
    address internal constant OTHER_VAULT = address(0xC0FFEE);
    address internal constant OUTSIDER = address(0xD00D);

    uint16 internal constant DEPOSIT_FEE_BPS = 125;
    uint16 internal constant WITHDRAWAL_FEE_BPS = 75;
    uint16 internal constant PERFORMANCE_FEE_BPS = 2000;
    uint16 internal constant INVALID_DEPOSIT_FEE_BPS = 201;
    uint16 internal constant INVALID_WITHDRAWAL_FEE_BPS = 201;
    uint16 internal constant INVALID_PERFORMANCE_FEE_BPS = 3001;

    function setUp() public {
        policy = new MeridianFeePolicy(
            OWNER, TREASURY, DEPOSIT_FEE_BPS, WITHDRAWAL_FEE_BPS, PERFORMANCE_FEE_BPS
        );
    }

    function testConstructorSetsTreasuryAndDefaultSchedule() external view {
        assertEq(policy.owner(), OWNER);
        assertEq(policy.treasury(), TREASURY);

        MeridianFeePolicy.FeeSchedule memory schedule = policy.defaultSchedule();
        _assertSchedule(schedule, DEPOSIT_FEE_BPS, WITHDRAWAL_FEE_BPS, PERFORMANCE_FEE_BPS, true);
    }

    function testConstructorRevertsForZeroTreasury() external {
        vm.expectRevert(MeridianFeePolicy.MeridianFeePolicy__InvalidTreasury.selector);
        new MeridianFeePolicy(OWNER, address(0), 0, 0, 0);
    }

    function testConstructorRevertsWhenDepositFeeExceedsMaximum() external {
        uint256 supplied = uint256(policy.MAX_DEPOSIT_FEE_BPS()) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianFeePolicy.MeridianFeePolicy__DepositFeeTooHigh.selector,
                supplied,
                policy.MAX_DEPOSIT_FEE_BPS()
            )
        );
        new MeridianFeePolicy(OWNER, TREASURY, uint16(supplied), 0, 0);
    }

    function testConstructorRevertsWhenWithdrawalFeeExceedsMaximum() external {
        uint256 supplied = uint256(policy.MAX_WITHDRAWAL_FEE_BPS()) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianFeePolicy.MeridianFeePolicy__WithdrawalFeeTooHigh.selector,
                supplied,
                policy.MAX_WITHDRAWAL_FEE_BPS()
            )
        );
        new MeridianFeePolicy(OWNER, TREASURY, 0, uint16(supplied), 0);
    }

    function testConstructorRevertsWhenPerformanceFeeExceedsMaximum() external {
        uint256 supplied = uint256(policy.MAX_PERFORMANCE_FEE_BPS()) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianFeePolicy.MeridianFeePolicy__PerformanceFeeTooHigh.selector,
                supplied,
                policy.MAX_PERFORMANCE_FEE_BPS()
            )
        );
        new MeridianFeePolicy(OWNER, TREASURY, 0, 0, uint16(supplied));
    }

    function testSetTreasuryUpdatesAddress() external {
        vm.prank(OWNER);
        policy.setTreasury(NEW_TREASURY);

        assertEq(policy.treasury(), NEW_TREASURY);
    }

    function testSetTreasuryRevertsForZeroAddress() external {
        vm.expectRevert(MeridianFeePolicy.MeridianFeePolicy__InvalidTreasury.selector);
        vm.prank(OWNER);
        policy.setTreasury(address(0));
    }

    function testSetTreasuryRevertsForCallerWithoutAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, policy.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        policy.setTreasury(NEW_TREASURY);
    }

    function testSetDefaultScheduleUpdatesFallbackSchedule() external {
        vm.prank(OWNER);
        policy.setDefaultSchedule(50, 60, 700);

        MeridianFeePolicy.FeeSchedule memory defaults = policy.defaultSchedule();
        MeridianFeePolicy.FeeSchedule memory fallbackSchedule = policy.scheduleFor(VAULT);
        _assertSchedule(defaults, 50, 60, 700, true);
        _assertSchedule(fallbackSchedule, 50, 60, 700, true);
    }

    function testMaximumFeeValuesAreAccepted() external {
        uint16 maxDeposit = policy.MAX_DEPOSIT_FEE_BPS();
        uint16 maxWithdrawal = policy.MAX_WITHDRAWAL_FEE_BPS();
        uint16 maxPerformance = policy.MAX_PERFORMANCE_FEE_BPS();

        vm.prank(OWNER);
        policy.setDefaultSchedule(maxDeposit, maxWithdrawal, maxPerformance);

        MeridianFeePolicy.FeeSchedule memory schedule = policy.defaultSchedule();
        _assertSchedule(schedule, maxDeposit, maxWithdrawal, maxPerformance, true);
    }

    function testSetDefaultScheduleValidatesEachFee() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianFeePolicy.MeridianFeePolicy__DepositFeeTooHigh.selector,
                INVALID_DEPOSIT_FEE_BPS,
                policy.MAX_DEPOSIT_FEE_BPS()
            )
        );
        vm.prank(OWNER);
        policy.setDefaultSchedule(INVALID_DEPOSIT_FEE_BPS, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianFeePolicy.MeridianFeePolicy__WithdrawalFeeTooHigh.selector,
                INVALID_WITHDRAWAL_FEE_BPS,
                policy.MAX_WITHDRAWAL_FEE_BPS()
            )
        );
        vm.prank(OWNER);
        policy.setDefaultSchedule(0, INVALID_WITHDRAWAL_FEE_BPS, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianFeePolicy.MeridianFeePolicy__PerformanceFeeTooHigh.selector,
                INVALID_PERFORMANCE_FEE_BPS,
                policy.MAX_PERFORMANCE_FEE_BPS()
            )
        );
        vm.prank(OWNER);
        policy.setDefaultSchedule(0, 0, INVALID_PERFORMANCE_FEE_BPS);
    }

    function testSetDefaultScheduleRevertsForCallerWithoutAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, policy.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        policy.setDefaultSchedule(1, 2, 3);
    }

    function testVaultScheduleOverridesDefaultOnlyForSelectedVault() external {
        vm.prank(OWNER);
        policy.setVaultSchedule(VAULT, 25, 30, 500);

        MeridianFeePolicy.FeeSchedule memory vaultSchedule = policy.scheduleFor(VAULT);
        MeridianFeePolicy.FeeSchedule memory otherSchedule = policy.scheduleFor(OTHER_VAULT);
        _assertSchedule(vaultSchedule, 25, 30, 500, true);
        _assertSchedule(
            otherSchedule, DEPOSIT_FEE_BPS, WITHDRAWAL_FEE_BPS, PERFORMANCE_FEE_BPS, true
        );
    }

    function testClearVaultScheduleRestoresDefault() external {
        vm.prank(OWNER);
        policy.setVaultSchedule(VAULT, 25, 30, 500);
        vm.prank(OWNER);
        policy.clearVaultSchedule(VAULT);

        MeridianFeePolicy.FeeSchedule memory schedule = policy.scheduleFor(VAULT);
        _assertSchedule(schedule, DEPOSIT_FEE_BPS, WITHDRAWAL_FEE_BPS, PERFORMANCE_FEE_BPS, true);
    }

    function testVaultScheduleFunctionsRejectZeroVault() external {
        vm.expectRevert(MeridianFeePolicy.MeridianFeePolicy__InvalidVault.selector);
        vm.prank(OWNER);
        policy.setVaultSchedule(address(0), 0, 0, 0);

        vm.expectRevert(MeridianFeePolicy.MeridianFeePolicy__InvalidVault.selector);
        vm.prank(OWNER);
        policy.clearVaultSchedule(address(0));
    }

    function testSetVaultScheduleValidatesFees() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianFeePolicy.MeridianFeePolicy__DepositFeeTooHigh.selector,
                INVALID_DEPOSIT_FEE_BPS,
                policy.MAX_DEPOSIT_FEE_BPS()
            )
        );
        vm.prank(OWNER);
        policy.setVaultSchedule(VAULT, INVALID_DEPOSIT_FEE_BPS, 0, 0);
    }

    function testVaultScheduleFunctionsRequireAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, policy.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        policy.setVaultSchedule(VAULT, 1, 2, 3);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, policy.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        policy.clearVaultSchedule(VAULT);
    }

    function testFeeCalculationsRoundDown() external view {
        assertEq(policy.depositFee(VAULT, 101), 1);
        assertEq(policy.withdrawalFee(VAULT, 199), 1);
        assertEq(policy.performanceFee(VAULT, 101), 20);

        assertEq(policy.netDepositAssets(VAULT, 101), 100);
        assertEq(policy.netWithdrawalAssets(VAULT, 199), 198);
    }

    function testGrossAssetCalculationsRoundUp() external view {
        assertEq(policy.grossDepositAssets(VAULT, 10_000), 10_127);
        assertEq(policy.grossWithdrawalAssets(VAULT, 10_000), 10_076);
    }

    function testZeroFeeScheduleLeavesAmountsUnchanged() external {
        vm.prank(OWNER);
        policy.setVaultSchedule(VAULT, 0, 0, 0);

        assertEq(policy.depositFee(VAULT, 123), 0);
        assertEq(policy.withdrawalFee(VAULT, 123), 0);
        assertEq(policy.performanceFee(VAULT, 123), 0);
        assertEq(policy.netDepositAssets(VAULT, 123), 123);
        assertEq(policy.netWithdrawalAssets(VAULT, 123), 123);
        assertEq(policy.grossDepositAssets(VAULT, 123), 123);
        assertEq(policy.grossWithdrawalAssets(VAULT, 123), 123);
    }

    function testVaultSpecificFeeCalculationsUseOverride() external {
        vm.prank(OWNER);
        policy.setVaultSchedule(VAULT, 200, 100, 3000);

        assertEq(policy.depositFee(VAULT, 10_000), 200);
        assertEq(policy.withdrawalFee(VAULT, 10_000), 100);
        assertEq(policy.performanceFee(VAULT, 10_000), 3000);
        assertEq(policy.depositFee(OTHER_VAULT, 10_000), 125);
    }

    function _assertSchedule(
        MeridianFeePolicy.FeeSchedule memory schedule,
        uint16 depositFeeBps,
        uint16 withdrawalFeeBps,
        uint16 performanceFeeBps,
        bool configured
    ) internal pure {
        assertEq(schedule.depositFeeBps, depositFeeBps);
        assertEq(schedule.withdrawalFeeBps, withdrawalFeeBps);
        assertEq(schedule.performanceFeeBps, performanceFeeBps);
        assertEq(schedule.configured, configured);
    }
}
