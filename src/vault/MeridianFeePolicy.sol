// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRoles } from "../access/MeridianRoles.sol";
import { MathLib } from "../libraries/MathLib.sol";

/// @title MeridianFeePolicy
/// @notice Central fee schedule shared by Meridian vault deployments.
contract MeridianFeePolicy is MeridianRoles {
    using MathLib for uint256;

    uint256 public constant BASIS_POINTS = 10_000;
    uint16 public constant MAX_DEPOSIT_FEE_BPS = 200;
    uint16 public constant MAX_WITHDRAWAL_FEE_BPS = 200;
    uint16 public constant MAX_PERFORMANCE_FEE_BPS = 3000;

    struct FeeSchedule {
        uint16 depositFeeBps;
        uint16 withdrawalFeeBps;
        uint16 performanceFeeBps;
        bool configured;
    }

    error MeridianFeePolicy__InvalidTreasury();
    error MeridianFeePolicy__DepositFeeTooHigh(uint256 supplied, uint256 maximum);
    error MeridianFeePolicy__WithdrawalFeeTooHigh(uint256 supplied, uint256 maximum);
    error MeridianFeePolicy__PerformanceFeeTooHigh(uint256 supplied, uint256 maximum);
    error MeridianFeePolicy__InvalidVault();

    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event DefaultScheduleUpdated(
        uint16 depositFeeBps, uint16 withdrawalFeeBps, uint16 performanceFeeBps
    );
    event VaultScheduleUpdated(
        address indexed vault,
        uint16 depositFeeBps,
        uint16 withdrawalFeeBps,
        uint16 performanceFeeBps
    );
    event VaultScheduleCleared(address indexed vault);

    address public treasury;
    FeeSchedule private _defaultSchedule;
    mapping(address vault => FeeSchedule schedule) private _vaultSchedules;

    constructor(
        address initialOwner,
        address initialTreasury,
        uint16 depositFeeBps,
        uint16 withdrawalFeeBps,
        uint16 performanceFeeBps
    ) MeridianRoles(initialOwner) {
        if (initialTreasury == address(0)) {
            revert MeridianFeePolicy__InvalidTreasury();
        }

        _validateSchedule(depositFeeBps, withdrawalFeeBps, performanceFeeBps);
        treasury = initialTreasury;
        _defaultSchedule = FeeSchedule({
            depositFeeBps: depositFeeBps,
            withdrawalFeeBps: withdrawalFeeBps,
            performanceFeeBps: performanceFeeBps,
            configured: true
        });
    }

    function defaultSchedule() external view returns (FeeSchedule memory) {
        return _defaultSchedule;
    }

    function scheduleFor(address vault) public view returns (FeeSchedule memory schedule) {
        schedule = _vaultSchedules[vault];
        if (!schedule.configured) {
            schedule = _defaultSchedule;
        }
    }

    function setTreasury(address newTreasury) external onlyRole(ADMIN_ROLE) {
        if (newTreasury == address(0)) {
            revert MeridianFeePolicy__InvalidTreasury();
        }

        address previous = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(previous, newTreasury);
    }

    function setDefaultSchedule(
        uint16 depositFeeBps,
        uint16 withdrawalFeeBps,
        uint16 performanceFeeBps
    ) external onlyRole(ADMIN_ROLE) {
        _validateSchedule(depositFeeBps, withdrawalFeeBps, performanceFeeBps);
        _defaultSchedule = FeeSchedule({
            depositFeeBps: depositFeeBps,
            withdrawalFeeBps: withdrawalFeeBps,
            performanceFeeBps: performanceFeeBps,
            configured: true
        });

        emit DefaultScheduleUpdated(depositFeeBps, withdrawalFeeBps, performanceFeeBps);
    }

    function setVaultSchedule(
        address vault,
        uint16 depositFeeBps,
        uint16 withdrawalFeeBps,
        uint16 performanceFeeBps
    ) external onlyRole(ADMIN_ROLE) {
        if (vault == address(0)) {
            revert MeridianFeePolicy__InvalidVault();
        }

        _validateSchedule(depositFeeBps, withdrawalFeeBps, performanceFeeBps);
        _vaultSchedules[vault] = FeeSchedule({
            depositFeeBps: depositFeeBps,
            withdrawalFeeBps: withdrawalFeeBps,
            performanceFeeBps: performanceFeeBps,
            configured: true
        });

        emit VaultScheduleUpdated(vault, depositFeeBps, withdrawalFeeBps, performanceFeeBps);
    }

    function clearVaultSchedule(address vault) external onlyRole(ADMIN_ROLE) {
        if (vault == address(0)) {
            revert MeridianFeePolicy__InvalidVault();
        }

        delete _vaultSchedules[vault];
        emit VaultScheduleCleared(vault);
    }

    function depositFee(address vault, uint256 grossAssets) public view returns (uint256) {
        FeeSchedule memory schedule = scheduleFor(vault);
        return grossAssets.mulDiv(schedule.depositFeeBps, BASIS_POINTS);
    }

    function withdrawalFee(address vault, uint256 grossAssets) public view returns (uint256) {
        FeeSchedule memory schedule = scheduleFor(vault);
        return grossAssets.mulDiv(schedule.withdrawalFeeBps, BASIS_POINTS);
    }

    function performanceFee(address vault, uint256 gain) public view returns (uint256) {
        FeeSchedule memory schedule = scheduleFor(vault);
        return gain.mulDiv(schedule.performanceFeeBps, BASIS_POINTS);
    }

    function netDepositAssets(address vault, uint256 grossAssets) external view returns (uint256) {
        return grossAssets - depositFee(vault, grossAssets);
    }

    function netWithdrawalAssets(address vault, uint256 grossAssets)
        external
        view
        returns (uint256)
    {
        return grossAssets - withdrawalFee(vault, grossAssets);
    }

    function grossDepositAssets(address vault, uint256 netAssets) external view returns (uint256) {
        FeeSchedule memory schedule = scheduleFor(vault);
        uint256 denominator = BASIS_POINTS - schedule.depositFeeBps;
        return netAssets.mulDivUp(BASIS_POINTS, denominator);
    }

    function grossWithdrawalAssets(address vault, uint256 netAssets)
        external
        view
        returns (uint256)
    {
        FeeSchedule memory schedule = scheduleFor(vault);
        uint256 denominator = BASIS_POINTS - schedule.withdrawalFeeBps;
        return netAssets.mulDivUp(BASIS_POINTS, denominator);
    }

    function _validateSchedule(
        uint16 depositFeeBps,
        uint16 withdrawalFeeBps,
        uint16 performanceFeeBps
    ) internal pure {
        if (depositFeeBps > MAX_DEPOSIT_FEE_BPS) {
            revert MeridianFeePolicy__DepositFeeTooHigh(depositFeeBps, MAX_DEPOSIT_FEE_BPS);
        }
        if (withdrawalFeeBps > MAX_WITHDRAWAL_FEE_BPS) {
            revert MeridianFeePolicy__WithdrawalFeeTooHigh(withdrawalFeeBps, MAX_WITHDRAWAL_FEE_BPS);
        }
        if (performanceFeeBps > MAX_PERFORMANCE_FEE_BPS) {
            revert MeridianFeePolicy__PerformanceFeeTooHigh(
                performanceFeeBps, MAX_PERFORMANCE_FEE_BPS
            );
        }
    }
}
