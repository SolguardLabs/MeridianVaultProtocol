// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRiskEngine } from "../../src/risk/MeridianRiskEngine.sol";
import { TestBase } from "../helpers/TestBase.sol";

contract MeridianRiskEngineTest is TestBase {
    MeridianRiskEngine internal engine;

    function setUp() public {
        engine = new MeridianRiskEngine();
    }

    function testHealthyPortfolioProducesDeterministicReport() external view {
        MeridianRiskEngine.Report memory report =
            engine.evaluate(_request(500_000, 250_000), _policy(), _balanced());

        assertEq(report.grossEstimatedAssets, 1_000_000);
        assertEq(report.stressedAssets, 890_000);
        assertEq(report.exitLiquidity, 620_000);
        assertEq(report.expectedStressLoss, 110_000);
        assertEq(report.liquidityGap, 0);
        assertEq(report.concentrationAddOn, 0);
        assertEq(report.capitalBuffer, 50_000);
        assertEq(report.requiredCapital, 160_000);
        assertEq(report.capitalCoverageBps, 10_000);
        assertEq(report.largestStrategyBps, 6250);
        assertEq(report.largestBucketBps, 6250);
        assertEq(report.strategyHhiBps, 5312);
        assertEq(uint256(report.decision), uint256(MeridianRiskEngine.Decision.Healthy));
    }

    function testLiquidityShortfallHaltsAdmissions() external view {
        MeridianRiskEngine.Report memory report =
            engine.evaluate(_request(750_000, 250_000), _policy(), _balanced());

        assertEq(report.exitLiquidity, 620_000);
        assertEq(report.liquidityGap, 130_000);
        assertEq(report.requiredCapital, 290_000);
        assertEq(report.liquidityCoverageBps, 8266);
        assertEq(report.capitalCoverageBps, 8620);
        assertEq(uint256(report.decision), uint256(MeridianRiskEngine.Decision.Halt));
    }

    function testConcentrationCreatesAddOnAndRestriction() external view {
        MeridianRiskEngine.Position[] memory positions = new MeridianRiskEngine.Position[](2);
        positions[0] = _position("locked", 700_000, 500_000, 1000, 500, 0, true);
        positions[1] = _position("reserve", 100_000, 100_000, 500, 0, 1, true);

        MeridianRiskEngine.Report memory report =
            engine.evaluate(_request(500_000, 1_000_000), _policy(), positions);

        assertEq(report.largestStrategyBps, 8750);
        assertEq(report.largestBucketBps, 8750);
        assertEq(report.concentrationAddOn, 240_000);
        assertEq(uint256(report.decision), uint256(MeridianRiskEngine.Decision.Restricted));
    }

    function testInactivePositionsAreExcluded() external view {
        MeridianRiskEngine.Position[] memory positions = _balanced();
        positions[1].active = false;

        MeridianRiskEngine.Report memory report =
            engine.evaluate(_request(300_000, 250_000), _policy(), positions);

        assertEq(report.activePositions, 1);
        assertEq(report.grossEstimatedAssets, 700_000);
        assertEq(report.largestStrategyBps, 10_000);
    }

    function testZeroDemandHasFullLiquidityCoverage() external view {
        MeridianRiskEngine.Report memory report =
            engine.evaluate(_request(0, 250_000), _policy(), _balanced());
        assertEq(report.liquidityCoverageBps, 10_000);
    }

    function testDigestChangesWhenDemandChanges() external view {
        bytes32 first =
            engine.evaluate(_request(500_000, 250_000), _policy(), _balanced()).snapshotDigest;
        bytes32 second =
            engine.evaluate(_request(500_001, 250_000), _policy(), _balanced()).snapshotDigest;
        assertTrue(first != second);
    }

    function testDuplicateStrategyIsRejected() external {
        MeridianRiskEngine.Position[] memory positions = _balanced();
        positions[1].strategyId = positions[0].strategyId;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRiskEngine.MeridianRiskEngine__DuplicateStrategy.selector,
                positions[0].strategyId
            )
        );
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testLiquidAssetsCannotExceedEstimate() external {
        MeridianRiskEngine.Position[] memory positions = _balanced();
        positions[0].liquidAssets = positions[0].estimatedAssets + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRiskEngine.MeridianRiskEngine__LiquidAssetsExceedEstimate.selector,
                0,
                positions[0].liquidAssets,
                positions[0].estimatedAssets
            )
        );
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testInvalidStressBasisPointsAreRejected() external {
        MeridianRiskEngine.Position[] memory positions = _balanced();
        positions[0].stressLossBps = 10_001;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRiskEngine.MeridianRiskEngine__InvalidBasisPoints.selector, 0, 10_001
            )
        );
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testInvalidExitDiscountIsRejected() external {
        MeridianRiskEngine.Position[] memory positions = _balanced();
        positions[0].exitDiscountBps = 10_001;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRiskEngine.MeridianRiskEngine__InvalidBasisPoints.selector, 0, 10_001
            )
        );
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testInvalidBucketIsRejected() external {
        MeridianRiskEngine.Position[] memory positions = _balanced();
        positions[0].correlationBucket = 8;
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRiskEngine.MeridianRiskEngine__InvalidCorrelationBucket.selector, 0, 8
            )
        );
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testZeroStrategyIdIsRejected() external {
        MeridianRiskEngine.Position[] memory positions = _balanced();
        positions[0].strategyId = bytes32(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRiskEngine.MeridianRiskEngine__InvalidStrategyId.selector, 0
            )
        );
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testEmptyPortfolioIsRejected() external {
        MeridianRiskEngine.Position[] memory positions = new MeridianRiskEngine.Position[](0);
        vm.expectRevert(MeridianRiskEngine.MeridianRiskEngine__EmptyPortfolio.selector);
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testPortfolioWithoutActiveValueIsRejected() external {
        MeridianRiskEngine.Position[] memory positions = _balanced();
        positions[0].active = false;
        positions[1].active = false;
        vm.expectRevert(MeridianRiskEngine.MeridianRiskEngine__EmptyPortfolio.selector);
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testTooManyPositionsAreRejected() external {
        MeridianRiskEngine.Position[] memory positions = new MeridianRiskEngine.Position[](17);
        for (uint256 i; i < positions.length; ++i) {
            positions[i] = _position(bytes32(i + 1), 1, 1, 0, 0, uint8(i % 8), true);
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRiskEngine.MeridianRiskEngine__TooManyPositions.selector, 17, 16
            )
        );
        engine.evaluate(_request(1, 1), _policy(), positions);
    }

    function testInvalidPolicyIsRejected() external {
        MeridianRiskEngine.Policy memory policy = _policy();
        policy.maximumStrategyConcentrationBps = 0;
        vm.expectRevert(MeridianRiskEngine.MeridianRiskEngine__InvalidPolicy.selector);
        engine.evaluate(_request(1, 1), policy, _balanced());
    }

    function _balanced() private pure returns (MeridianRiskEngine.Position[] memory positions) {
        positions = new MeridianRiskEngine.Position[](2);
        positions[0] = _position("locked", 500_000, 300_000, 1000, 500, 0, true);
        positions[1] = _position("lending", 300_000, 150_000, 2000, 1000, 1, true);
    }

    function _position(
        bytes32 strategyId,
        uint256 estimatedAssets,
        uint256 liquidAssets,
        uint16 stressLossBps,
        uint16 exitDiscountBps,
        uint8 bucket,
        bool active
    ) private pure returns (MeridianRiskEngine.Position memory) {
        return MeridianRiskEngine.Position({
            strategyId: strategyId,
            estimatedAssets: estimatedAssets,
            liquidAssets: liquidAssets,
            stressLossBps: stressLossBps,
            exitDiscountBps: exitDiscountBps,
            correlationBucket: bucket,
            active: active
        });
    }

    function _request(uint256 demand, uint256 capital)
        private
        pure
        returns (MeridianRiskEngine.Request memory)
    {
        return MeridianRiskEngine.Request({
            idleAssets: 200_000, withdrawalDemand: demand, capitalReserve: capital
        });
    }

    function _policy() private pure returns (MeridianRiskEngine.Policy memory) {
        return MeridianRiskEngine.Policy({
            minimumLiquidityCoverageBps: 9000,
            maximumStrategyConcentrationBps: 7000,
            maximumBucketConcentrationBps: 7500,
            capitalBufferBps: 500,
            restrictedCapitalCoverageBps: 9000
        });
    }
}
