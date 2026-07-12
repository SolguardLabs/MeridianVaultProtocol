// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IMeridianStrategy } from "../interfaces/IMeridianStrategy.sol";
import { IStrategyRegistry } from "../interfaces/IStrategyRegistry.sol";
import { QueueLib } from "../libraries/QueueLib.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { MeridianRoles } from "../access/MeridianRoles.sol";
import { MeridianTypes } from "../types/MeridianTypes.sol";
import { MeridianValuationPolicy } from "../oracle/MeridianValuationPolicy.sol";

interface IMeridianVaultAccounting {
    function totalAssets() external view returns (uint256);
}

interface IMeridianStrategyAdministration {
    function setKeeper(address newKeeper) external;
    function setShutdown(bool shutdown) external;
}

/// @title StrategyRegistry
/// @notice Stores strategy policy, debt and the latest accepted accounting reports.
contract StrategyRegistry is IStrategyRegistry, MeridianRoles {
    using QueueLib for QueueLib.AddressQueue;
    using MathLib for uint256;

    uint256 private constant BASIS_POINTS = 10_000;

    error StrategyRegistry__InvalidAsset();
    error StrategyRegistry__InvalidValuationPolicy();
    error StrategyRegistry__InvalidVault();
    error StrategyRegistry__VaultAlreadyBound(address vault);
    error StrategyRegistry__OnlyVault(address caller);
    error StrategyRegistry__InvalidStrategy(address strategy);
    error StrategyRegistry__StrategyAlreadyRegistered(address strategy);
    error StrategyRegistry__StrategyNotRegistered(address strategy);
    error StrategyRegistry__StrategyAssetMismatch(address expected, address observed);
    error StrategyRegistry__StrategyVaultMismatch(address expected, address observed);
    error StrategyRegistry__InvalidConfiguration();
    error StrategyRegistry__TargetAllocationExceeded(uint256 configuredBps);
    error StrategyRegistry__StrategyUnavailable(address strategy);
    error StrategyRegistry__DebtLimitExceeded(uint256 resultingDebt, uint256 limit);
    error StrategyRegistry__ExposureLimitExceeded(uint256 resultingDebt, uint256 limit);
    error StrategyRegistry__DebtOutstanding(uint256 debt);
    error StrategyRegistry__AssetsOutstanding(uint256 assets);
    error StrategyRegistry__QueueStrategyUnavailable(address strategy);
    error StrategyRegistry__Uint128Overflow(uint256 value);
    error StrategyRegistry__Uint64Overflow(uint256 value);

    event VaultBound(address indexed vault);
    event ValuationPolicyUpdated(address indexed previousPolicy, address indexed newPolicy);
    event StrategyAdded(
        address indexed strategy, uint256 debtLimit, uint16 targetBps, uint16 maxBps
    );
    event StrategyUpdated(
        address indexed strategy,
        uint256 debtLimit,
        uint16 targetBps,
        uint16 maxBps,
        MeridianTypes.StrategyStatus status
    );
    event StrategyRemoved(address indexed strategy);
    event StrategyOperationsUpdated(
        address indexed strategy, address indexed keeper, bool shutdown
    );
    event WithdrawalQueueUpdated(address[] strategies);
    event DebtAllocated(address indexed strategy, uint256 assets, uint256 resultingDebt);
    event DebtRecovered(
        address indexed strategy,
        address indexed receiver,
        uint256 requested,
        uint256 withdrawn,
        uint256 loss,
        uint256 resultingDebt
    );
    event StrategyReported(
        address indexed strategy,
        uint256 previousEstimate,
        uint256 currentEstimate,
        uint256 liquidAssets,
        uint256 gain,
        uint256 loss
    );

    address public immutable override asset;
    address public override vault;
    MeridianValuationPolicy public valuationPolicy;

    uint256 public override totalReportedAssets;
    uint256 public override totalDebt;

    QueueLib.AddressQueue private _strategies;
    QueueLib.AddressQueue private _withdrawalQueue;
    mapping(address strategy => MeridianTypes.StrategyConfig config) private _configs;
    mapping(address strategy => MeridianTypes.StrategyState state) private _states;

    constructor(address initialOwner, address asset_, MeridianValuationPolicy valuationPolicy_)
        MeridianRoles(initialOwner)
    {
        if (asset_ == address(0) || asset_.code.length == 0) {
            revert StrategyRegistry__InvalidAsset();
        }
        if (address(valuationPolicy_) != address(0) && address(valuationPolicy_).code.length == 0) {
            revert StrategyRegistry__InvalidValuationPolicy();
        }
        asset = asset_;
        valuationPolicy = valuationPolicy_;
    }

    modifier onlyVault() {
        if (msg.sender != vault) {
            revert StrategyRegistry__OnlyVault(msg.sender);
        }
        _;
    }

    function bindVault(address vault_) external onlyOwner {
        if (vault != address(0)) {
            revert StrategyRegistry__VaultAlreadyBound(vault);
        }
        if (vault_ == address(0) || vault_.code.length == 0) {
            revert StrategyRegistry__InvalidVault();
        }
        vault = vault_;
        emit VaultBound(vault_);
    }

    function setValuationPolicy(MeridianValuationPolicy newPolicy) external onlyRole(ADMIN_ROLE) {
        if (address(newPolicy) != address(0) && address(newPolicy).code.length == 0) {
            revert StrategyRegistry__InvalidValuationPolicy();
        }
        address previous = address(valuationPolicy);
        valuationPolicy = newPolicy;
        emit ValuationPolicyUpdated(previous, address(newPolicy));
    }

    function strategyCount() external view override returns (uint256) {
        return _strategies.length();
    }

    function strategyAt(uint256 index) external view override returns (address) {
        return _strategies.at(index);
    }

    function isStrategy(address strategy) public view override returns (bool) {
        return _strategies.contains(strategy);
    }

    function getStrategyConfig(address strategy)
        external
        view
        override
        returns (MeridianTypes.StrategyConfig memory)
    {
        _requireStrategy(strategy);
        return _configs[strategy];
    }

    function getStrategyState(address strategy)
        external
        view
        override
        returns (MeridianTypes.StrategyState memory)
    {
        _requireStrategy(strategy);
        return _states[strategy];
    }

    function withdrawalQueue() external view override returns (address[] memory) {
        return _withdrawalQueue.values();
    }

    function addStrategy(MeridianTypes.StrategyConfig calldata config)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        address strategy = config.strategy;
        if (isStrategy(strategy)) {
            revert StrategyRegistry__StrategyAlreadyRegistered(strategy);
        }
        _validateConfiguration(config);
        _validateStrategyContract(strategy);
        _validateTargetAllocation(address(0), config.targetBps);

        _configs[strategy] = config;
        _states[strategy].activation = _toUint64(block.timestamp);
        _strategies.enqueue(strategy);

        emit StrategyAdded(strategy, config.debtLimit, config.targetBps, config.maxBps);
    }

    function updateStrategy(MeridianTypes.StrategyConfig calldata config)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        _requireStrategy(config.strategy);
        _validateConfiguration(config);
        _validateStrategyContract(config.strategy);
        _validateTargetAllocation(config.strategy, config.targetBps);
        _configs[config.strategy] = config;

        emit StrategyUpdated(
            config.strategy, config.debtLimit, config.targetBps, config.maxBps, config.status
        );
    }

    function removeStrategy(address strategy) external override onlyRole(ADMIN_ROLE) {
        _requireStrategy(strategy);
        MeridianTypes.StrategyState memory state = _states[strategy];
        if (state.debt != 0) {
            revert StrategyRegistry__DebtOutstanding(state.debt);
        }
        if (state.lastEstimatedAssets != 0) {
            revert StrategyRegistry__AssetsOutstanding(state.lastEstimatedAssets);
        }

        _withdrawalQueue.tryRemove(strategy);
        _strategies.remove(strategy);
        delete _configs[strategy];
        delete _states[strategy];
        emit StrategyRemoved(strategy);
    }

    function configureStrategyOperations(address strategy, address keeper, bool shutdown)
        external
        onlyRole(ADMIN_ROLE)
    {
        _requireStrategy(strategy);
        if (keeper == address(0)) revert StrategyRegistry__InvalidConfiguration();
        IMeridianStrategyAdministration(strategy).setKeeper(keeper);
        IMeridianStrategyAdministration(strategy).setShutdown(shutdown);
        emit StrategyOperationsUpdated(strategy, keeper, shutdown);
    }

    function setWithdrawalQueue(address[] calldata strategies)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        uint256 length = strategies.length;
        for (uint256 i; i < length;) {
            address strategy = strategies[i];
            _requireStrategy(strategy);
            if (_configs[strategy].status == MeridianTypes.StrategyStatus.Inactive) {
                revert StrategyRegistry__QueueStrategyUnavailable(strategy);
            }
            unchecked {
                ++i;
            }
        }
        _withdrawalQueue.replace(strategies);
        emit WithdrawalQueueUpdated(strategies);
    }

    function allocate(address strategy, uint256 assets)
        external
        override
        onlyVault
        returns (uint256 allocated)
    {
        _requireStrategy(strategy);
        MeridianTypes.StrategyConfig storage config = _configs[strategy];
        if (config.status != MeridianTypes.StrategyStatus.Active) {
            revert StrategyRegistry__StrategyUnavailable(strategy);
        }
        if (assets == 0) return 0;
        if (assets < config.minDebtChange) {
            revert StrategyRegistry__InvalidConfiguration();
        }

        MeridianTypes.StrategyState storage state = _states[strategy];
        uint256 resultingDebt = uint256(state.debt) + assets;
        if (resultingDebt > config.debtLimit) {
            revert StrategyRegistry__DebtLimitExceeded(resultingDebt, config.debtLimit);
        }

        uint256 managed = IMeridianVaultAccounting(vault).totalAssets() + assets;
        uint256 maximumExposure = managed.mulDiv(config.maxBps, BASIS_POINTS);
        if (resultingDebt > maximumExposure) {
            revert StrategyRegistry__ExposureLimitExceeded(resultingDebt, maximumExposure);
        }

        uint256 deployed = IMeridianStrategy(strategy).deposit(assets);
        state.debt = _toUint128(resultingDebt);
        state.lastEstimatedAssets = _toUint128(uint256(state.lastEstimatedAssets) + assets);
        state.lastLiquidAssets = _toUint128(IMeridianStrategy(strategy).liquidTotalAssets());
        totalDebt += assets;
        totalReportedAssets += assets;
        allocated = assets;

        emit DebtAllocated(strategy, assets, resultingDebt);
        if (deployed > assets) revert StrategyRegistry__InvalidConfiguration();
    }

    function withdraw(address strategy, uint256 assets, address receiver)
        external
        override
        onlyVault
        returns (uint256 withdrawn, uint256 loss)
    {
        _requireStrategy(strategy);
        if (receiver == address(0)) revert StrategyRegistry__InvalidVault();
        if (assets == 0) return (0, 0);

        uint256 available = IMeridianStrategy(strategy).maxWithdraw();
        uint256 request = assets.min(available);
        if (request == 0) return (0, 0);
        (withdrawn, loss) = IMeridianStrategy(strategy).withdraw(request, receiver);
        _recordWithdrawal(strategy, request, withdrawn, loss, receiver);
    }

    function withdrawAll(address strategy, address receiver)
        external
        override
        onlyVault
        returns (uint256 withdrawn, uint256 loss)
    {
        _requireStrategy(strategy);
        if (receiver == address(0)) revert StrategyRegistry__InvalidVault();
        uint256 requested = _states[strategy].debt;
        (withdrawn, loss) = IMeridianStrategy(strategy).withdrawAll(receiver);
        _recordWithdrawal(strategy, requested, withdrawn, loss, receiver);
    }

    function emergencyExit(address strategy, address receiver)
        external
        override
        onlyVault
        returns (uint256 withdrawn, uint256 loss)
    {
        _requireStrategy(strategy);
        if (receiver == address(0)) revert StrategyRegistry__InvalidVault();
        uint256 requested = _states[strategy].debt;
        (withdrawn, loss) = IMeridianStrategy(strategy).emergencyExit(receiver);
        _recordWithdrawal(strategy, requested, withdrawn, loss, receiver);
    }

    function checkpoint(address strategy)
        external
        override
        onlyVault
        returns (MeridianTypes.StrategyReport memory report)
    {
        _requireStrategy(strategy);
        report = _checkpoint(strategy, true);
    }

    function harvest(address strategy, bytes calldata data)
        external
        override
        onlyVault
        returns (MeridianTypes.StrategyReport memory report)
    {
        _requireStrategy(strategy);
        (uint256 realizedGain, uint256 realizedLoss) = IMeridianStrategy(strategy).harvest(data);
        report = _checkpoint(strategy, true);
        report.realizedGain = realizedGain;
        report.realizedLoss = realizedLoss;
    }

    function _recordWithdrawal(
        address strategy,
        uint256 requested,
        uint256 withdrawn,
        uint256 loss,
        address receiver
    ) internal {
        MeridianTypes.StrategyState storage state = _states[strategy];
        uint256 reduction = (withdrawn + loss).min(state.debt);
        state.debt = _toUint128(uint256(state.debt) - reduction);
        totalDebt -= reduction;
        if (loss != 0) {
            state.totalLoss = _toUint128(uint256(state.totalLoss) + loss);
        }
        _refreshAfterWithdrawal(strategy, withdrawn, loss);
        emit DebtRecovered(strategy, receiver, requested, withdrawn, loss, state.debt);
    }

    function _refreshAfterWithdrawal(address strategy, uint256 withdrawn, uint256 realizedLoss)
        internal
    {
        MeridianTypes.StrategyState storage state = _states[strategy];
        uint256 previous = state.lastEstimatedAssets;
        uint256 reduction = (withdrawn + realizedLoss).min(previous);
        uint256 estimated = previous - reduction;
        uint256 liquid = IMeridianStrategy(strategy).liquidTotalAssets();
        totalReportedAssets -= reduction;
        state.lastEstimatedAssets = _toUint128(estimated);
        state.lastLiquidAssets = _toUint128(liquid);
        emit StrategyReported(strategy, previous, estimated, liquid, 0, realizedLoss);
    }

    function _checkpoint(address strategy, bool validate)
        internal
        returns (MeridianTypes.StrategyReport memory report)
    {
        MeridianTypes.StrategyState storage state = _states[strategy];
        uint256 previous = state.lastEstimatedAssets;
        uint256 estimated = IMeridianStrategy(strategy).estimatedTotalAssets();
        uint256 liquid = IMeridianStrategy(strategy).liquidTotalAssets();

        MeridianValuationPolicy policy = valuationPolicy;
        if (validate && address(policy) != address(0)) {
            policy.validateCheckpoint(strategy, previous, estimated, liquid, state.lastReport);
        }

        uint256 gain;
        uint256 reportLoss;
        if (estimated >= previous) {
            gain = estimated - previous;
            state.totalGain = _toUint128(uint256(state.totalGain) + gain);
            totalReportedAssets += gain;
        } else {
            reportLoss = previous - estimated;
            state.totalLoss = _toUint128(uint256(state.totalLoss) + reportLoss);
            totalReportedAssets -= reportLoss;
        }

        uint64 timestamp = _toUint64(block.timestamp);
        state.lastEstimatedAssets = _toUint128(estimated);
        state.lastLiquidAssets = _toUint128(liquid);
        state.lastReport = timestamp;
        report = MeridianTypes.StrategyReport({
            strategy: strategy,
            estimatedAssets: estimated,
            liquidAssets: liquid,
            realizedGain: 0,
            realizedLoss: 0,
            debtPayment: 0,
            timestamp: timestamp
        });
        emit StrategyReported(strategy, previous, estimated, liquid, gain, reportLoss);
    }

    function _validateStrategyContract(address strategy) internal view {
        if (strategy == address(0) || strategy.code.length == 0) {
            revert StrategyRegistry__InvalidStrategy(strategy);
        }
        address observedAsset = IMeridianStrategy(strategy).asset();
        if (observedAsset != asset) {
            revert StrategyRegistry__StrategyAssetMismatch(asset, observedAsset);
        }
        address observedVault = IMeridianStrategy(strategy).vault();
        if (observedVault != vault) {
            revert StrategyRegistry__StrategyVaultMismatch(vault, observedVault);
        }
    }

    function _validateConfiguration(MeridianTypes.StrategyConfig calldata config) internal pure {
        if (
            config.strategy == address(0) || config.targetBps > config.maxBps
                || config.maxBps > BASIS_POINTS
                || config.status == MeridianTypes.StrategyStatus.Inactive
        ) {
            revert StrategyRegistry__InvalidConfiguration();
        }
    }

    function _validateTargetAllocation(address replaced, uint16 targetBps) internal view {
        uint256 total = targetBps;
        uint256 length = _strategies.length();
        for (uint256 i; i < length;) {
            address strategy = _strategies.at(i);
            if (strategy != replaced) total += _configs[strategy].targetBps;
            unchecked {
                ++i;
            }
        }
        if (total > BASIS_POINTS) {
            revert StrategyRegistry__TargetAllocationExceeded(total);
        }
    }

    function _requireStrategy(address strategy) internal view {
        if (!isStrategy(strategy)) {
            revert StrategyRegistry__StrategyNotRegistered(strategy);
        }
    }

    function _toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) revert StrategyRegistry__Uint128Overflow(value);
        return uint128(value);
    }

    function _toUint64(uint256 value) internal pure returns (uint64) {
        if (value > type(uint64).max) revert StrategyRegistry__Uint64Overflow(value);
        return uint64(value);
    }
}
