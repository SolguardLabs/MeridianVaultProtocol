// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRoles } from "../../src/access/MeridianRoles.sol";
import { MeridianValuationPolicy } from "../../src/oracle/MeridianValuationPolicy.sol";
import { TestBase } from "../helpers/TestBase.sol";

contract MeridianValuationPolicyTest is TestBase {
    MeridianValuationPolicy internal policy;

    address internal constant OWNER = address(0xA11CE);
    address internal constant STRATEGY = address(0xB0B);
    address internal constant OTHER_STRATEGY = address(0xC0FFEE);
    address internal constant OUTSIDER = address(0xD00D);

    uint16 internal constant MAX_INCREASE_BPS = 2000;
    uint16 internal constant MAX_DECREASE_BPS = 1000;
    uint16 internal constant MINIMUM_LIQUIDITY_BPS = 2500;
    uint32 internal constant MINIMUM_DELAY = 1 hours;
    uint32 internal constant MAXIMUM_DELAY = 1 days;

    function setUp() public {
        policy = new MeridianValuationPolicy(
            OWNER,
            _bounds(
                MAX_INCREASE_BPS,
                MAX_DECREASE_BPS,
                MINIMUM_LIQUIDITY_BPS,
                MINIMUM_DELAY,
                MAXIMUM_DELAY
            )
        );
    }

    function testConstructorSetsConfiguredDefaultBounds() external view {
        assertEq(policy.owner(), OWNER);
        MeridianValuationPolicy.Bounds memory configured = policy.defaultBounds();
        _assertBounds(
            configured,
            MAX_INCREASE_BPS,
            MAX_DECREASE_BPS,
            MINIMUM_LIQUIDITY_BPS,
            MINIMUM_DELAY,
            MAXIMUM_DELAY,
            true
        );
    }

    function testConstructorValidatesIncreaseLimit() external {
        MeridianValuationPolicy.Bounds memory invalid = _bounds(50_001, 0, 0, 0, 0);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidBounds.selector);
        new MeridianValuationPolicy(OWNER, invalid);
    }

    function testConstructorValidatesDecreaseLimit() external {
        MeridianValuationPolicy.Bounds memory invalid = _bounds(0, 10_001, 0, 0, 0);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidBounds.selector);
        new MeridianValuationPolicy(OWNER, invalid);
    }

    function testConstructorValidatesLiquidityLimit() external {
        MeridianValuationPolicy.Bounds memory invalid = _bounds(0, 0, 10_001, 0, 0);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidBounds.selector);
        new MeridianValuationPolicy(OWNER, invalid);
    }

    function testConstructorValidatesMaximumReportWindow() external {
        MeridianValuationPolicy.Bounds memory invalid =
            _bounds(0, 0, 0, 0, policy.MAX_REPORT_WINDOW() + 1);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidBounds.selector);
        new MeridianValuationPolicy(OWNER, invalid);
    }

    function testConstructorValidatesDelayOrdering() external {
        MeridianValuationPolicy.Bounds memory invalid = _bounds(0, 0, 0, 2, 1);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidBounds.selector);
        new MeridianValuationPolicy(OWNER, invalid);
    }

    function testAllMaximumBoundsAreAccepted() external {
        MeridianValuationPolicy.Bounds memory maximums = _bounds(
            policy.MAX_CHANGE_BPS(),
            uint16(policy.BASIS_POINTS()),
            uint16(policy.BASIS_POINTS()),
            policy.MAX_REPORT_WINDOW(),
            policy.MAX_REPORT_WINDOW()
        );

        vm.prank(OWNER);
        policy.setDefaultBounds(maximums);

        MeridianValuationPolicy.Bounds memory configured = policy.defaultBounds();
        _assertBounds(
            configured,
            policy.MAX_CHANGE_BPS(),
            uint16(policy.BASIS_POINTS()),
            uint16(policy.BASIS_POINTS()),
            policy.MAX_REPORT_WINDOW(),
            policy.MAX_REPORT_WINDOW(),
            true
        );
    }

    function testSetDefaultBoundsUpdatesFallback() external {
        MeridianValuationPolicy.Bounds memory replacement = _bounds(100, 200, 300, 4, 5);

        vm.prank(OWNER);
        policy.setDefaultBounds(replacement);

        MeridianValuationPolicy.Bounds memory defaults = policy.defaultBounds();
        MeridianValuationPolicy.Bounds memory fallbackBounds = policy.boundsFor(STRATEGY);
        _assertBounds(defaults, 100, 200, 300, 4, 5, true);
        _assertBounds(fallbackBounds, 100, 200, 300, 4, 5, true);
    }

    function testSetDefaultBoundsRevertsForInvalidBounds() external {
        MeridianValuationPolicy.Bounds memory invalid = _bounds(0, 0, 0, 2, 1);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidBounds.selector);
        vm.prank(OWNER);
        policy.setDefaultBounds(invalid);
    }

    function testSetDefaultBoundsRequiresAdminRole() external {
        MeridianValuationPolicy.Bounds memory replacement = _bounds(100, 200, 300, 4, 5);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, policy.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        policy.setDefaultBounds(replacement);
    }

    function testStrategyBoundsOverrideDefaultOnlyForSelectedStrategy() external {
        MeridianValuationPolicy.Bounds memory replacement = _bounds(100, 200, 300, 4, 5);

        vm.prank(OWNER);
        policy.setStrategyBounds(STRATEGY, replacement);

        MeridianValuationPolicy.Bounds memory strategyBounds = policy.boundsFor(STRATEGY);
        MeridianValuationPolicy.Bounds memory otherBounds = policy.boundsFor(OTHER_STRATEGY);
        _assertBounds(strategyBounds, 100, 200, 300, 4, 5, true);
        _assertBounds(
            otherBounds,
            MAX_INCREASE_BPS,
            MAX_DECREASE_BPS,
            MINIMUM_LIQUIDITY_BPS,
            MINIMUM_DELAY,
            MAXIMUM_DELAY,
            true
        );
    }

    function testClearStrategyBoundsRestoresDefault() external {
        MeridianValuationPolicy.Bounds memory replacement = _bounds(100, 200, 300, 4, 5);

        vm.prank(OWNER);
        policy.setStrategyBounds(STRATEGY, replacement);
        vm.prank(OWNER);
        policy.clearStrategyBounds(STRATEGY);

        MeridianValuationPolicy.Bounds memory strategyBounds = policy.boundsFor(STRATEGY);
        _assertBounds(
            strategyBounds,
            MAX_INCREASE_BPS,
            MAX_DECREASE_BPS,
            MINIMUM_LIQUIDITY_BPS,
            MINIMUM_DELAY,
            MAXIMUM_DELAY,
            true
        );
    }

    function testStrategyBoundsFunctionsRejectZeroStrategy() external {
        MeridianValuationPolicy.Bounds memory replacement = _bounds(100, 200, 300, 4, 5);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidStrategy.selector);
        vm.prank(OWNER);
        policy.setStrategyBounds(address(0), replacement);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidStrategy.selector);
        vm.prank(OWNER);
        policy.clearStrategyBounds(address(0));
    }

    function testSetStrategyBoundsValidatesBounds() external {
        MeridianValuationPolicy.Bounds memory invalid = _bounds(0, 0, 0, 2, 1);

        vm.expectRevert(MeridianValuationPolicy.MeridianValuationPolicy__InvalidBounds.selector);
        vm.prank(OWNER);
        policy.setStrategyBounds(STRATEGY, invalid);
    }

    function testStrategyBoundsFunctionsRequireAdminRole() external {
        MeridianValuationPolicy.Bounds memory replacement = _bounds(100, 200, 300, 4, 5);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, policy.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        policy.setStrategyBounds(STRATEGY, replacement);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, policy.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        policy.clearStrategyBounds(STRATEGY);
    }

    function testValidateCheckpointAcceptsValuesAtEveryBoundary() external view {
        policy.validateCheckpoint(STRATEGY, 1000, 1200, 300, 0);
        policy.validateCheckpoint(STRATEGY, 1000, 900, 225, 0);
        policy.validateCheckpoint(STRATEGY, 1000, 1000, 250, 0);
    }

    function testValidateCheckpointAcceptsFirstReport() external view {
        policy.validateCheckpoint(STRATEGY, 0, 1_000_000, 250_000, 0);
    }

    function testValidateCheckpointRejectsLiquidValueAboveEstimate() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianValuationPolicy.MeridianValuationPolicy__LiquidValueExceedsEstimate
                .selector,
                101,
                100
            )
        );
        policy.validateCheckpoint(STRATEGY, 100, 100, 101, 0);
    }

    function testValidateCheckpointEnforcesMinimumDelay() external {
        vm.warp(4599);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianValuationPolicy.MeridianValuationPolicy__ReportTooEarly.selector, 4600
            )
        );
        policy.validateCheckpoint(STRATEGY, 1000, 1000, 250, 1000);

        vm.warp(4600);
        policy.validateCheckpoint(STRATEGY, 1000, 1000, 250, 1000);
    }

    function testValidateCheckpointRejectsIncreaseAboveBound() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianValuationPolicy.MeridianValuationPolicy__IncreaseOutsideBounds.selector,
                1000,
                1201
            )
        );
        policy.validateCheckpoint(STRATEGY, 1000, 1201, 300, 0);
    }

    function testIncreaseBoundRoundsDown() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianValuationPolicy.MeridianValuationPolicy__IncreaseOutsideBounds.selector,
                3,
                4
            )
        );
        policy.validateCheckpoint(STRATEGY, 3, 4, 1, 0);
    }

    function testValidateCheckpointRejectsDecreaseAboveBound() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianValuationPolicy.MeridianValuationPolicy__DecreaseOutsideBounds.selector,
                1000,
                899
            )
        );
        policy.validateCheckpoint(STRATEGY, 1000, 899, 225, 0);
    }

    function testDecreaseBoundRoundsDown() external {
        policy.validateCheckpoint(STRATEGY, 1001, 901, 225, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianValuationPolicy.MeridianValuationPolicy__DecreaseOutsideBounds.selector,
                1001,
                900
            )
        );
        policy.validateCheckpoint(STRATEGY, 1001, 900, 225, 0);
    }

    function testValidateCheckpointRejectsLiquidityBelowBound() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianValuationPolicy.MeridianValuationPolicy__LiquidityOutsideBounds.selector,
                250,
                249
            )
        );
        policy.validateCheckpoint(STRATEGY, 1001, 1001, 249, 0);
    }

    function testLiquidityBoundRoundsDown() external view {
        policy.validateCheckpoint(STRATEGY, 1001, 1001, 250, 0);
    }

    function testZeroEstimateWithZeroLiquidValueIsAcceptedForInitialReport() external view {
        policy.validateCheckpoint(STRATEGY, 0, 0, 0, 0);
    }

    function testStrategyOverrideIsUsedDuringValidation() external {
        MeridianValuationPolicy.Bounds memory strict = _bounds(0, 0, 10_000, 0, 1 days);
        vm.prank(OWNER);
        policy.setStrategyBounds(STRATEGY, strict);

        policy.validateCheckpoint(STRATEGY, 1000, 1000, 1000, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianValuationPolicy.MeridianValuationPolicy__IncreaseOutsideBounds.selector,
                1000,
                1001
            )
        );
        policy.validateCheckpoint(STRATEGY, 1000, 1001, 1001, 0);
    }

    function testIsStaleUsesStrictDeadlineAndTreatsZeroAsStale() external {
        vm.warp(100_000);
        uint256 lastReport = block.timestamp - MAXIMUM_DELAY;

        assertTrue(policy.isStale(STRATEGY, 0));
        assertFalse(policy.isStale(STRATEGY, lastReport));

        vm.warp(100_001);
        assertTrue(policy.isStale(STRATEGY, lastReport));
    }

    function testNextReportAtAndDeadlineForExistingReport() external view {
        uint256 lastReport = 12_345;

        assertEq(policy.nextReportAt(STRATEGY, lastReport), lastReport + MINIMUM_DELAY);
        assertEq(policy.reportDeadline(STRATEGY, lastReport), lastReport + MAXIMUM_DELAY);
    }

    function testNextReportAtAndDeadlineReturnCurrentTimeForFirstReport() external {
        vm.warp(123_456);

        assertEq(policy.nextReportAt(STRATEGY, 0), block.timestamp);
        assertEq(policy.reportDeadline(STRATEGY, 0), block.timestamp);
    }

    function testTimingHelpersUseStrategyOverride() external {
        MeridianValuationPolicy.Bounds memory replacement = _bounds(0, 0, 0, 10, 20);
        vm.prank(OWNER);
        policy.setStrategyBounds(STRATEGY, replacement);

        assertEq(policy.nextReportAt(STRATEGY, 100), 110);
        assertEq(policy.reportDeadline(STRATEGY, 100), 120);
    }

    function _bounds(
        uint16 maxIncreaseBps,
        uint16 maxDecreaseBps,
        uint16 minimumLiquidityBps,
        uint32 minimumDelay,
        uint32 maximumDelay
    ) internal pure returns (MeridianValuationPolicy.Bounds memory) {
        return MeridianValuationPolicy.Bounds({
            maxIncreaseBps: maxIncreaseBps,
            maxDecreaseBps: maxDecreaseBps,
            minimumLiquidityBps: minimumLiquidityBps,
            minimumDelay: minimumDelay,
            maximumDelay: maximumDelay,
            configured: false
        });
    }

    function _assertBounds(
        MeridianValuationPolicy.Bounds memory configured,
        uint16 maxIncreaseBps,
        uint16 maxDecreaseBps,
        uint16 minimumLiquidityBps,
        uint32 minimumDelay,
        uint32 maximumDelay,
        bool isConfigured
    ) internal pure {
        assertEq(configured.maxIncreaseBps, maxIncreaseBps);
        assertEq(configured.maxDecreaseBps, maxDecreaseBps);
        assertEq(configured.minimumLiquidityBps, minimumLiquidityBps);
        assertEq(configured.minimumDelay, minimumDelay);
        assertEq(configured.maximumDelay, maximumDelay);
        assertEq(configured.configured, isConfigured);
    }
}
