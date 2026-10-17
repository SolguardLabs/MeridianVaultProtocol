// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MathLib } from "../libraries/MathLib.sol";

/// @title MeridianRiskEngine
/// @notice Deterministic portfolio stress and liquidity assessment for Meridian vault operators.
/// @dev The engine is stateless. Callers provide an immutable snapshot and persist the report
/// off-chain.
contract MeridianRiskEngine {
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_POSITIONS = 16;
    uint256 public constant MAX_CORRELATION_BUCKETS = 8;

    enum Decision {
        Healthy,
        Restricted,
        Halt
    }

    struct Position {
        bytes32 strategyId;
        uint256 estimatedAssets;
        uint256 liquidAssets;
        uint16 stressLossBps;
        uint16 exitDiscountBps;
        uint8 correlationBucket;
        bool active;
    }

    struct Policy {
        uint16 minimumLiquidityCoverageBps;
        uint16 maximumStrategyConcentrationBps;
        uint16 maximumBucketConcentrationBps;
        uint16 capitalBufferBps;
        uint16 restrictedCapitalCoverageBps;
    }

    struct Request {
        uint256 idleAssets;
        uint256 withdrawalDemand;
        uint256 capitalReserve;
    }

    struct Report {
        uint256 grossEstimatedAssets;
        uint256 stressedAssets;
        uint256 exitLiquidity;
        uint256 expectedStressLoss;
        uint256 liquidityGap;
        uint256 concentrationAddOn;
        uint256 capitalBuffer;
        uint256 requiredCapital;
        uint256 availableCapital;
        uint256 liquidityCoverageBps;
        uint256 capitalCoverageBps;
        uint256 largestStrategyBps;
        uint256 largestBucketBps;
        uint256 strategyHhiBps;
        uint256 activePositions;
        Decision decision;
        bytes32 snapshotDigest;
    }

    error MeridianRiskEngine__EmptyPortfolio();
    error MeridianRiskEngine__TooManyPositions(uint256 supplied, uint256 maximum);
    error MeridianRiskEngine__InvalidPolicy();
    error MeridianRiskEngine__InvalidStrategyId(uint256 index);
    error MeridianRiskEngine__DuplicateStrategy(bytes32 strategyId);
    error MeridianRiskEngine__InvalidBasisPoints(uint256 index, uint256 value);
    error MeridianRiskEngine__InvalidCorrelationBucket(uint256 index, uint256 bucket);
    error MeridianRiskEngine__LiquidAssetsExceedEstimate(
        uint256 index, uint256 liquidAssets, uint256 estimatedAssets
    );

    function evaluate(
        Request calldata request,
        Policy calldata policy,
        Position[] calldata positions
    ) external pure returns (Report memory report) {
        _validatePolicy(policy);
        if (positions.length == 0) revert MeridianRiskEngine__EmptyPortfolio();
        if (positions.length > MAX_POSITIONS) {
            revert MeridianRiskEngine__TooManyPositions(positions.length, MAX_POSITIONS);
        }

        uint256 totalEstimated;
        uint256 stressedStrategyAssets;
        uint256 exitStrategyLiquidity;
        uint256 largestStrategy;
        uint256[8] memory bucketAssets;

        for (uint256 i; i < positions.length;) {
            Position calldata position = positions[i];
            _validatePosition(positions, position, i);

            if (position.active) {
                uint256 stressedValue = MathLib.mulBpsDown(
                    position.estimatedAssets, BASIS_POINTS - position.stressLossBps
                );
                uint256 exitValue = MathLib.mulBpsDown(
                    position.liquidAssets, BASIS_POINTS - position.exitDiscountBps
                );

                totalEstimated += position.estimatedAssets;
                stressedStrategyAssets += stressedValue;
                exitStrategyLiquidity += exitValue;
                bucketAssets[position.correlationBucket] += position.estimatedAssets;
                largestStrategy = MathLib.max(largestStrategy, position.estimatedAssets);
                unchecked {
                    ++report.activePositions;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (report.activePositions == 0 || totalEstimated == 0) {
            revert MeridianRiskEngine__EmptyPortfolio();
        }

        report.grossEstimatedAssets = request.idleAssets + totalEstimated;
        report.stressedAssets = request.idleAssets + stressedStrategyAssets;
        report.exitLiquidity = request.idleAssets + exitStrategyLiquidity;
        report.expectedStressLoss = totalEstimated - stressedStrategyAssets;
        report.liquidityGap = request.withdrawalDemand > report.exitLiquidity
            ? request.withdrawalDemand - report.exitLiquidity
            : 0;
        report.largestStrategyBps = MathLib.mulDiv(largestStrategy, BASIS_POINTS, totalEstimated);

        (report.largestBucketBps, report.strategyHhiBps) =
            _concentrationMetrics(positions, bucketAssets, totalEstimated);
        report.concentrationAddOn = _concentrationAddOn(
            largestStrategy,
            report.largestStrategyBps,
            bucketAssets,
            report.largestBucketBps,
            totalEstimated,
            policy
        );
        report.capitalBuffer =
            MathLib.mulBpsUp(report.grossEstimatedAssets, policy.capitalBufferBps);
        report.requiredCapital = report.expectedStressLoss + report.liquidityGap
            + report.concentrationAddOn + report.capitalBuffer;
        report.availableCapital = request.capitalReserve;
        report.liquidityCoverageBps = _coverage(report.exitLiquidity, request.withdrawalDemand);
        report.capitalCoverageBps = _coverage(report.availableCapital, report.requiredCapital);
        report.decision = _decision(report, policy);
        report.snapshotDigest = keccak256(
            abi.encode(
                request,
                policy,
                positions,
                report.grossEstimatedAssets,
                report.stressedAssets,
                report.exitLiquidity,
                report.requiredCapital,
                report.decision
            )
        );
    }

    function _validatePolicy(Policy calldata policy) private pure {
        if (
            policy.minimumLiquidityCoverageBps > BASIS_POINTS
                || policy.maximumStrategyConcentrationBps > BASIS_POINTS
                || policy.maximumBucketConcentrationBps > BASIS_POINTS
                || policy.capitalBufferBps > BASIS_POINTS
                || policy.restrictedCapitalCoverageBps > BASIS_POINTS
                || policy.maximumStrategyConcentrationBps == 0
                || policy.maximumBucketConcentrationBps == 0
        ) revert MeridianRiskEngine__InvalidPolicy();
    }

    function _validatePosition(
        Position[] calldata positions,
        Position calldata position,
        uint256 index
    ) private pure {
        if (position.strategyId == bytes32(0)) {
            revert MeridianRiskEngine__InvalidStrategyId(index);
        }
        if (position.stressLossBps > BASIS_POINTS) {
            revert MeridianRiskEngine__InvalidBasisPoints(index, position.stressLossBps);
        }
        if (position.exitDiscountBps > BASIS_POINTS) {
            revert MeridianRiskEngine__InvalidBasisPoints(index, position.exitDiscountBps);
        }
        if (position.correlationBucket >= MAX_CORRELATION_BUCKETS) {
            revert MeridianRiskEngine__InvalidCorrelationBucket(index, position.correlationBucket);
        }
        if (position.liquidAssets > position.estimatedAssets) {
            revert MeridianRiskEngine__LiquidAssetsExceedEstimate(
                index, position.liquidAssets, position.estimatedAssets
            );
        }
        for (uint256 j; j < index;) {
            if (positions[j].strategyId == position.strategyId) {
                revert MeridianRiskEngine__DuplicateStrategy(position.strategyId);
            }
            unchecked {
                ++j;
            }
        }
    }

    function _concentrationMetrics(
        Position[] calldata positions,
        uint256[8] memory bucketAssets,
        uint256 totalEstimated
    ) private pure returns (uint256 largestBucketBps, uint256 hhiBps) {
        for (uint256 i; i < positions.length;) {
            if (positions[i].active) {
                uint256 weightBps =
                    MathLib.mulDiv(positions[i].estimatedAssets, BASIS_POINTS, totalEstimated);
                hhiBps += MathLib.mulDiv(weightBps, weightBps, BASIS_POINTS);
            }
            unchecked {
                ++i;
            }
        }
        for (uint256 bucket; bucket < MAX_CORRELATION_BUCKETS;) {
            uint256 weightBps = MathLib.mulDiv(bucketAssets[bucket], BASIS_POINTS, totalEstimated);
            largestBucketBps = MathLib.max(largestBucketBps, weightBps);
            unchecked {
                ++bucket;
            }
        }
    }

    function _concentrationAddOn(
        uint256 largestStrategy,
        uint256 largestStrategyBps,
        uint256[8] memory bucketAssets,
        uint256 largestBucketBps,
        uint256 totalEstimated,
        Policy calldata policy
    ) private pure returns (uint256 addOn) {
        if (largestStrategyBps > policy.maximumStrategyConcentrationBps) {
            uint256 permitted =
                MathLib.mulBpsDown(totalEstimated, policy.maximumStrategyConcentrationBps);
            addOn += largestStrategy - permitted;
        }
        if (largestBucketBps > policy.maximumBucketConcentrationBps) {
            uint256 largestBucket;
            for (uint256 bucket; bucket < MAX_CORRELATION_BUCKETS;) {
                largestBucket = MathLib.max(largestBucket, bucketAssets[bucket]);
                unchecked {
                    ++bucket;
                }
            }
            uint256 permitted =
                MathLib.mulBpsDown(totalEstimated, policy.maximumBucketConcentrationBps);
            addOn += largestBucket - permitted;
        }
    }

    function _coverage(uint256 available, uint256 required) private pure returns (uint256) {
        if (required == 0) return BASIS_POINTS;
        return MathLib.min(BASIS_POINTS, MathLib.mulDiv(available, BASIS_POINTS, required));
    }

    function _decision(Report memory report, Policy calldata policy)
        private
        pure
        returns (Decision)
    {
        if (
            report.liquidityCoverageBps < policy.minimumLiquidityCoverageBps
                || report.capitalCoverageBps < policy.restrictedCapitalCoverageBps
        ) return Decision.Halt;
        if (
            report.largestStrategyBps > policy.maximumStrategyConcentrationBps
                || report.largestBucketBps > policy.maximumBucketConcentrationBps
                || report.capitalCoverageBps < BASIS_POINTS
        ) return Decision.Restricted;
        return Decision.Healthy;
    }
}
