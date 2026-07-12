// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Shared data structures used by the Meridian vault, registry and strategies.
library MeridianTypes {
    uint16 internal constant MAX_BPS = 10_000;

    enum StrategyStatus {
        Inactive,
        Active,
        Paused,
        Retiring
    }

    struct StrategyConfig {
        address strategy;
        uint128 debtLimit;
        uint96 minDebtChange;
        uint16 targetBps;
        uint16 maxBps;
        StrategyStatus status;
    }

    struct StrategyState {
        uint128 debt;
        uint128 lastEstimatedAssets;
        uint128 lastLiquidAssets;
        uint128 totalGain;
        uint128 totalLoss;
        uint64 lastReport;
        uint64 activation;
    }

    struct StrategyReport {
        address strategy;
        uint256 estimatedAssets;
        uint256 liquidAssets;
        uint256 realizedGain;
        uint256 realizedLoss;
        uint256 debtPayment;
        uint64 timestamp;
    }

    struct Allocation {
        address strategy;
        uint256 assets;
    }

    struct WithdrawalResult {
        uint256 requestedAssets;
        uint256 withdrawnAssets;
        uint256 loss;
    }
}
