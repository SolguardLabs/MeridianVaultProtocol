// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ILendingMarket } from "../interfaces/ILendingMarket.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { BaseStrategy } from "./BaseStrategy.sol";

/// @notice Strategy adapter for a lending market with a configurable idle buffer.
contract LendingStrategy is BaseStrategy {
    using SafeTransferLib for address;

    uint16 internal constant MAX_BPS = 10_000;

    error InvalidMarket(address market);
    error AssetMismatch(address expected, address actual);
    error InvalidBufferBps(uint256 bps);
    error IncentiveBelowMinimum(uint256 received, uint256 minimum);

    event LiquidityBufferUpdated(uint16 previousBps, uint16 newBps);
    event RebalanceOnHarvestUpdated(bool enabled);
    event MarketSupplied(uint256 assets, uint256 positionUnits);
    event MarketWithdrawn(uint256 requested, uint256 withdrawn);
    event BufferRebalanced(uint256 idleBefore, uint256 idleAfter, uint256 targetIdle);
    event IncentivesCollected(uint256 assets);

    ILendingMarket public immutable market;

    uint16 public liquidityBufferBps;
    bool public rebalanceOnHarvest;
    uint256 public totalPositionUnitsIssued;
    uint256 public totalIncentivesCollected;

    constructor(address asset_, address vault_, address manager_, address market_)
        BaseStrategy(asset_, vault_, manager_)
    {
        if (market_ == address(0)) revert InvalidMarket(market_);

        address marketAsset = ILendingMarket(market_).asset();
        if (marketAsset != asset_) revert AssetMismatch(asset_, marketAsset);
        market = ILendingMarket(market_);
    }

    function setLiquidityBufferBps(uint16 newBufferBps) external onlyGovernance {
        if (newBufferBps > MAX_BPS) revert InvalidBufferBps(newBufferBps);

        uint16 previousBps = liquidityBufferBps;
        liquidityBufferBps = newBufferBps;
        emit LiquidityBufferUpdated(previousBps, newBufferBps);
    }

    function setRebalanceOnHarvest(bool enabled) external onlyGovernance {
        rebalanceOnHarvest = enabled;
        emit RebalanceOnHarvestUpdated(enabled);
    }

    function marketPosition()
        external
        view
        returns (uint256 principal, uint256 quoted, uint256 liquid)
    {
        principal = market.principalOf(address(this));
        quoted = market.balanceOfUnderlying(address(this));
        liquid = market.liquidBalanceOf(address(this));
    }

    function rebalanceBuffer() external onlyOperator nonReentrant {
        _rebalanceBuffer();
    }

    function _estimatedInvestedAssets() internal view override returns (uint256) {
        return market.balanceOfUnderlying(address(this));
    }

    function _liquidInvestedAssets() internal view override returns (uint256) {
        return market.liquidBalanceOf(address(this));
    }

    function _maxInvestableAssets() internal view override returns (uint256) {
        return market.maxSupply(address(this));
    }

    function _maxWithdrawableInvestedAssets() internal view override returns (uint256) {
        uint256 liquid = market.liquidBalanceOf(address(this));
        uint256 marketLimit = market.maxWithdraw(address(this));
        return liquid < marketLimit ? liquid : marketLimit;
    }

    function _deployFunds(uint256 assets) internal override returns (uint256 deployed) {
        if (assets == 0) return 0;

        uint256 amountToSupply = assets;
        if (liquidityBufferBps != 0) {
            uint256 retained = assets * liquidityBufferBps / MAX_BPS;
            amountToSupply -= retained;
        }
        if (amountToSupply == 0) return 0;

        uint256 capacity = market.maxSupply(address(this));
        if (amountToSupply > capacity) amountToSupply = capacity;
        if (amountToSupply == 0) return 0;

        uint256 balanceBefore = asset.safeBalanceOf(address(this));
        asset.forceApprove(address(market), amountToSupply);
        uint256 positionUnits = market.supply(amountToSupply, address(this));
        asset.forceApprove(address(market), 0);

        uint256 balanceAfter = asset.safeBalanceOf(address(this));
        deployed = balanceBefore > balanceAfter ? balanceBefore - balanceAfter : 0;
        totalPositionUnitsIssued += positionUnits;

        emit MarketSupplied(deployed, positionUnits);
    }

    function _freeFunds(uint256 assets) internal override returns (uint256 withdrawn) {
        if (assets == 0) return 0;

        uint256 balanceBefore = asset.safeBalanceOf(address(this));
        market.withdraw(assets, address(this), address(this));
        uint256 balanceAfter = asset.safeBalanceOf(address(this));
        withdrawn = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

        emit MarketWithdrawn(assets, withdrawn);
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
        uint256 minimumIncentives;
        bool shouldRebalance = rebalanceOnHarvest;

        if (data.length != 0) {
            (minimumIncentives, shouldRebalance) = abi.decode(data, (uint256, bool));
        }

        uint256 balanceBefore = asset.safeBalanceOf(address(this));
        market.claimInterest(address(this));
        market.claimIncentives(address(this));
        uint256 balanceAfter = asset.safeBalanceOf(address(this));
        realizedGain = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

        if (realizedGain < minimumIncentives) {
            revert IncentiveBelowMinimum(realizedGain, minimumIncentives);
        }

        totalIncentivesCollected += realizedGain;
        emit IncentivesCollected(realizedGain);

        if (shouldRebalance) _rebalanceBuffer();
        realizedLoss = 0;
    }

    function _rebalanceBuffer() internal {
        uint256 idleBefore = asset.safeBalanceOf(address(this));
        uint256 total = idleBefore + market.balanceOfUnderlying(address(this));
        uint256 targetIdle = total * liquidityBufferBps / MAX_BPS;

        if (idleBefore > targetIdle) {
            uint256 surplus = idleBefore - targetIdle;
            uint256 capacity = market.maxSupply(address(this));
            if (surplus > capacity) surplus = capacity;
            if (surplus != 0) _supplyExact(surplus);
        } else if (idleBefore < targetIdle) {
            uint256 deficit = targetIdle - idleBefore;
            uint256 available = _maxWithdrawableInvestedAssets();
            if (deficit > available) deficit = available;
            if (deficit != 0) _freeFunds(deficit);
        }

        emit BufferRebalanced(idleBefore, asset.safeBalanceOf(address(this)), targetIdle);
    }

    function _supplyExact(uint256 assets) internal returns (uint256 supplied) {
        uint256 balanceBefore = asset.safeBalanceOf(address(this));
        asset.forceApprove(address(market), assets);
        uint256 positionUnits = market.supply(assets, address(this));
        asset.forceApprove(address(market), 0);

        uint256 balanceAfter = asset.safeBalanceOf(address(this));
        supplied = balanceBefore > balanceAfter ? balanceBefore - balanceAfter : 0;
        totalPositionUnitsIssued += positionUnits;
        emit MarketSupplied(supplied, positionUnits);
    }
}
