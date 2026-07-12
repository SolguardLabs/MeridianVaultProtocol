// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { BaseStrategy } from "./BaseStrategy.sol";

/// @notice Strategy adapter for a yield source with separately quoted and liquid balances.
contract LockedYieldStrategy is BaseStrategy {
    using SafeTransferLib for address;

    error InvalidYieldSource(address source);
    error AssetMismatch(address expected, address actual);
    error RewardBelowMinimum(uint256 received, uint256 minimum);

    event RewardsReinvestmentUpdated(bool enabled);
    event FundsDeployed(uint256 assets, uint256 positionUnits);
    event FundsFreed(uint256 requested, uint256 withdrawn);
    event RewardsCollected(uint256 received, bool reinvested);

    IYieldSource public immutable yieldSource;

    bool public reinvestRewards;
    uint256 public totalPositionUnitsIssued;
    uint256 public totalRewardsCollected;

    constructor(address asset_, address vault_, address manager_, address yieldSource_)
        BaseStrategy(asset_, vault_, manager_)
    {
        if (yieldSource_ == address(0)) revert InvalidYieldSource(yieldSource_);

        address sourceAsset = IYieldSource(yieldSource_).asset();
        if (sourceAsset != asset_) revert AssetMismatch(asset_, sourceAsset);
        yieldSource = IYieldSource(yieldSource_);
    }

    function setReinvestRewards(bool enabled) external onlyGovernance {
        reinvestRewards = enabled;
        emit RewardsReinvestmentUpdated(enabled);
    }

    function positionValue() external view returns (uint256 quoted, uint256 liquid) {
        quoted = yieldSource.balanceOfUnderlying(address(this));
        liquid = yieldSource.liquidBalanceOf(address(this));
    }

    function _estimatedInvestedAssets() internal view override returns (uint256) {
        return yieldSource.balanceOfUnderlying(address(this));
    }

    function _liquidInvestedAssets() internal view override returns (uint256) {
        return yieldSource.liquidBalanceOf(address(this));
    }

    function _maxInvestableAssets() internal view override returns (uint256) {
        return yieldSource.maxDeposit(address(this));
    }

    function _maxWithdrawableInvestedAssets() internal view override returns (uint256) {
        uint256 liquid = yieldSource.liquidBalanceOf(address(this));
        uint256 sourceLimit = yieldSource.maxWithdraw(address(this));
        return liquid < sourceLimit ? liquid : sourceLimit;
    }

    function _deployFunds(uint256 assets) internal override returns (uint256 deployed) {
        if (assets == 0) return 0;

        uint256 balanceBefore = asset.safeBalanceOf(address(this));
        asset.forceApprove(address(yieldSource), assets);
        uint256 positionUnits = yieldSource.deposit(assets, address(this));
        asset.forceApprove(address(yieldSource), 0);

        uint256 balanceAfter = asset.safeBalanceOf(address(this));
        deployed = balanceBefore > balanceAfter ? balanceBefore - balanceAfter : 0;
        totalPositionUnitsIssued += positionUnits;

        emit FundsDeployed(deployed, positionUnits);
    }

    function _freeFunds(uint256 assets) internal override returns (uint256 withdrawn) {
        if (assets == 0) return 0;

        uint256 balanceBefore = asset.safeBalanceOf(address(this));
        yieldSource.withdraw(assets, address(this), address(this));
        uint256 balanceAfter = asset.safeBalanceOf(address(this));
        withdrawn = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

        emit FundsFreed(assets, withdrawn);
    }

    function _freeAllFunds() internal override returns (uint256 withdrawn) {
        uint256 available = _maxWithdrawableInvestedAssets();
        if (available == 0) return 0;
        return _freeFunds(available);
    }

    function _harvest(bytes calldata data)
        internal
        override
        returns (uint256 realizedGain, uint256 realizedLoss)
    {
        uint256 minimumRewardAssets;
        bool shouldReinvest = reinvestRewards;

        if (data.length != 0) {
            (minimumRewardAssets, shouldReinvest) = abi.decode(data, (uint256, bool));
        }

        uint256 balanceBefore = asset.safeBalanceOf(address(this));
        yieldSource.claimRewards(address(this));
        uint256 balanceAfter = asset.safeBalanceOf(address(this));
        realizedGain = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

        if (realizedGain < minimumRewardAssets) {
            revert RewardBelowMinimum(realizedGain, minimumRewardAssets);
        }

        totalRewardsCollected += realizedGain;
        bool reinvested;
        if (shouldReinvest && realizedGain != 0) {
            uint256 capacity = yieldSource.maxDeposit(address(this));
            uint256 amountToReinvest = realizedGain < capacity ? realizedGain : capacity;
            if (amountToReinvest != 0) {
                _deployFunds(amountToReinvest);
                reinvested = true;
            }
        }

        emit RewardsCollected(realizedGain, reinvested);
        realizedLoss = 0;
    }
}
