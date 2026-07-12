// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { BaseStrategy } from "./BaseStrategy.sol";

/// @notice Liquid strategy used as an operational reserve for the vault.
contract ReserveStrategy is BaseStrategy {
    using SafeTransferLib for address;

    error InvalidReserveConfiguration(uint256 capacity, uint256 withdrawalFloor);

    event CapacityUpdated(uint256 previousCapacity, uint256 newCapacity);
    event WithdrawalFloorUpdated(uint256 previousFloor, uint256 newFloor);
    event ReserveCheckpoint(uint256 balance, uint256 withdrawalFloor);

    uint256 public capacity;
    uint256 public withdrawalFloor;

    constructor(
        address asset_,
        address vault_,
        address manager_,
        uint256 capacity_,
        uint256 withdrawalFloor_
    ) BaseStrategy(asset_, vault_, manager_) {
        if (withdrawalFloor_ > capacity_) {
            revert InvalidReserveConfiguration(capacity_, withdrawalFloor_);
        }

        capacity = capacity_;
        withdrawalFloor = withdrawalFloor_;
        emit CapacityUpdated(0, capacity_);
        emit WithdrawalFloorUpdated(0, withdrawalFloor_);
    }

    function setCapacity(uint256 newCapacity) external onlyGovernance {
        if (withdrawalFloor > newCapacity) {
            revert InvalidReserveConfiguration(newCapacity, withdrawalFloor);
        }

        uint256 previousCapacity = capacity;
        capacity = newCapacity;
        emit CapacityUpdated(previousCapacity, newCapacity);
    }

    function setWithdrawalFloor(uint256 newWithdrawalFloor) external onlyGovernance {
        if (newWithdrawalFloor > capacity) {
            revert InvalidReserveConfiguration(capacity, newWithdrawalFloor);
        }

        uint256 previousFloor = withdrawalFloor;
        withdrawalFloor = newWithdrawalFloor;
        emit WithdrawalFloorUpdated(previousFloor, newWithdrawalFloor);
    }

    function availableAboveFloor() public view returns (uint256) {
        uint256 balance = asset.safeBalanceOf(address(this));
        return balance > withdrawalFloor ? balance - withdrawalFloor : 0;
    }

    function maxWithdraw() public view override returns (uint256) {
        return availableAboveFloor();
    }

    function _estimatedInvestedAssets() internal pure override returns (uint256) {
        return 0;
    }

    function _liquidInvestedAssets() internal pure override returns (uint256) {
        return 0;
    }

    function _maxInvestableAssets() internal view override returns (uint256) {
        uint256 current = accountedAssets;
        return current < capacity ? capacity - current : 0;
    }

    function _maxWithdrawableInvestedAssets() internal pure override returns (uint256) {
        return 0;
    }

    function _deployFunds(uint256 assets) internal pure override returns (uint256 deployed) {
        return assets;
    }

    function _freeFunds(uint256) internal pure override returns (uint256 withdrawn) {
        return 0;
    }

    function _freeAllFunds() internal pure override returns (uint256 withdrawn) {
        return 0;
    }

    function _harvest(bytes calldata)
        internal
        override
        returns (uint256 realizedGain, uint256 realizedLoss)
    {
        emit ReserveCheckpoint(asset.safeBalanceOf(address(this)), withdrawalFloor);
        return (0, 0);
    }
}
