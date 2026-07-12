// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRoles } from "../access/MeridianRoles.sol";
import { MathLib } from "../libraries/MathLib.sol";

/// @title MeridianValuationPolicy
/// @notice Bounds strategy checkpoints according to governance risk parameters.
contract MeridianValuationPolicy is MeridianRoles {
    using MathLib for uint256;

    uint256 public constant BASIS_POINTS = 10_000;
    uint16 public constant MAX_CHANGE_BPS = 50_000;
    uint32 public constant MAX_REPORT_WINDOW = 30 days;

    struct Bounds {
        uint16 maxIncreaseBps;
        uint16 maxDecreaseBps;
        uint16 minimumLiquidityBps;
        uint32 minimumDelay;
        uint32 maximumDelay;
        bool configured;
    }

    error MeridianValuationPolicy__InvalidStrategy();
    error MeridianValuationPolicy__InvalidBounds();
    error MeridianValuationPolicy__ReportTooEarly(uint256 nextReportAt);
    error MeridianValuationPolicy__IncreaseOutsideBounds(uint256 previous, uint256 current);
    error MeridianValuationPolicy__DecreaseOutsideBounds(uint256 previous, uint256 current);
    error MeridianValuationPolicy__LiquidityOutsideBounds(uint256 expected, uint256 observed);
    error MeridianValuationPolicy__LiquidValueExceedsEstimate(uint256 liquid, uint256 estimated);

    event DefaultBoundsUpdated(
        uint16 maxIncreaseBps,
        uint16 maxDecreaseBps,
        uint16 minimumLiquidityBps,
        uint32 minimumDelay,
        uint32 maximumDelay
    );
    event StrategyBoundsUpdated(
        address indexed strategy,
        uint16 maxIncreaseBps,
        uint16 maxDecreaseBps,
        uint16 minimumLiquidityBps,
        uint32 minimumDelay,
        uint32 maximumDelay
    );
    event StrategyBoundsCleared(address indexed strategy);

    Bounds private _defaultBounds;
    mapping(address strategy => Bounds bounds) private _strategyBounds;

    constructor(address initialOwner, Bounds memory initialBounds) MeridianRoles(initialOwner) {
        _validateBounds(initialBounds);
        initialBounds.configured = true;
        _defaultBounds = initialBounds;
    }

    function defaultBounds() external view returns (Bounds memory) {
        return _defaultBounds;
    }

    function boundsFor(address strategy) public view returns (Bounds memory bounds) {
        bounds = _strategyBounds[strategy];
        if (!bounds.configured) {
            bounds = _defaultBounds;
        }
    }

    function setDefaultBounds(Bounds calldata newBounds) external onlyRole(ADMIN_ROLE) {
        _validateBounds(newBounds);
        _defaultBounds = Bounds({
            maxIncreaseBps: newBounds.maxIncreaseBps,
            maxDecreaseBps: newBounds.maxDecreaseBps,
            minimumLiquidityBps: newBounds.minimumLiquidityBps,
            minimumDelay: newBounds.minimumDelay,
            maximumDelay: newBounds.maximumDelay,
            configured: true
        });

        emit DefaultBoundsUpdated(
            newBounds.maxIncreaseBps,
            newBounds.maxDecreaseBps,
            newBounds.minimumLiquidityBps,
            newBounds.minimumDelay,
            newBounds.maximumDelay
        );
    }

    function setStrategyBounds(address strategy, Bounds calldata newBounds)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (strategy == address(0)) {
            revert MeridianValuationPolicy__InvalidStrategy();
        }

        _validateBounds(newBounds);
        _strategyBounds[strategy] = Bounds({
            maxIncreaseBps: newBounds.maxIncreaseBps,
            maxDecreaseBps: newBounds.maxDecreaseBps,
            minimumLiquidityBps: newBounds.minimumLiquidityBps,
            minimumDelay: newBounds.minimumDelay,
            maximumDelay: newBounds.maximumDelay,
            configured: true
        });

        emit StrategyBoundsUpdated(
            strategy,
            newBounds.maxIncreaseBps,
            newBounds.maxDecreaseBps,
            newBounds.minimumLiquidityBps,
            newBounds.minimumDelay,
            newBounds.maximumDelay
        );
    }

    function clearStrategyBounds(address strategy) external onlyRole(ADMIN_ROLE) {
        if (strategy == address(0)) {
            revert MeridianValuationPolicy__InvalidStrategy();
        }

        delete _strategyBounds[strategy];
        emit StrategyBoundsCleared(strategy);
    }

    function validateCheckpoint(
        address strategy,
        uint256 previousEstimate,
        uint256 currentEstimate,
        uint256 currentLiquid,
        uint256 lastReport
    ) external view {
        Bounds memory bounds = boundsFor(strategy);

        if (currentLiquid > currentEstimate) {
            revert MeridianValuationPolicy__LiquidValueExceedsEstimate(
                currentLiquid, currentEstimate
            );
        }

        if (lastReport != 0 && block.timestamp < lastReport + bounds.minimumDelay) {
            revert MeridianValuationPolicy__ReportTooEarly(lastReport + bounds.minimumDelay);
        }

        if (previousEstimate != 0 && currentEstimate > previousEstimate) {
            uint256 maximum =
                previousEstimate + previousEstimate.mulDiv(bounds.maxIncreaseBps, BASIS_POINTS);
            if (currentEstimate > maximum) {
                revert MeridianValuationPolicy__IncreaseOutsideBounds(
                    previousEstimate, currentEstimate
                );
            }
        }

        if (previousEstimate != 0 && currentEstimate < previousEstimate) {
            uint256 decrease = previousEstimate - currentEstimate;
            uint256 maximumDecrease = previousEstimate.mulDiv(bounds.maxDecreaseBps, BASIS_POINTS);
            if (decrease > maximumDecrease) {
                revert MeridianValuationPolicy__DecreaseOutsideBounds(
                    previousEstimate, currentEstimate
                );
            }
        }

        if (currentEstimate != 0 && bounds.minimumLiquidityBps != 0) {
            uint256 minimumLiquid = currentEstimate.mulDiv(bounds.minimumLiquidityBps, BASIS_POINTS);
            if (currentLiquid < minimumLiquid) {
                revert MeridianValuationPolicy__LiquidityOutsideBounds(minimumLiquid, currentLiquid);
            }
        }
    }

    function isStale(address strategy, uint256 lastReport) external view returns (bool) {
        Bounds memory bounds = boundsFor(strategy);
        if (lastReport == 0) {
            return true;
        }
        return block.timestamp > lastReport + bounds.maximumDelay;
    }

    function nextReportAt(address strategy, uint256 lastReport) external view returns (uint256) {
        if (lastReport == 0) {
            return block.timestamp;
        }
        return lastReport + boundsFor(strategy).minimumDelay;
    }

    function reportDeadline(address strategy, uint256 lastReport) external view returns (uint256) {
        if (lastReport == 0) {
            return block.timestamp;
        }
        return lastReport + boundsFor(strategy).maximumDelay;
    }

    function _validateBounds(Bounds memory bounds) internal pure {
        if (
            bounds.maxIncreaseBps > MAX_CHANGE_BPS || bounds.maxDecreaseBps > BASIS_POINTS
                || bounds.minimumLiquidityBps > BASIS_POINTS
                || bounds.maximumDelay > MAX_REPORT_WINDOW
                || bounds.maximumDelay < bounds.minimumDelay
        ) {
            revert MeridianValuationPolicy__InvalidBounds();
        }
    }
}
