// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IMeridianStrategy } from "../interfaces/IMeridianStrategy.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

interface IMeridianVaultGovernance {
    function owner() external view returns (address);
}

/// @notice Common lifecycle and permissions for Meridian strategy adapters.
abstract contract BaseStrategy is IMeridianStrategy {
    using SafeTransferLib for address;

    error Unauthorized(address caller);
    error ZeroAddress();
    error StrategyIsShutdown();
    error ReentrantCall();
    error DepositAboveLimit(uint256 requested, uint256 limit);
    error InsufficientIdleAssets(uint256 available, uint256 requested);
    error InvalidManagedAmount(uint256 managed, uint256 requested);
    error InvalidRealization(uint256 gain, uint256 loss);
    error ProtectedAsset();

    event ManagerUpdated(address indexed previousManager, address indexed newManager);
    event KeeperUpdated(address indexed previousKeeper, address indexed newKeeper);
    event ShutdownUpdated(bool shutdown);
    event AssetsManaged(uint256 assets, uint256 deployed, uint256 accountedAssets);
    event AssetsReturned(
        address indexed receiver,
        uint256 requested,
        uint256 withdrawn,
        uint256 loss,
        uint256 accountedAssets
    );
    event StrategyHarvested(
        address indexed caller,
        uint256 realizedGain,
        uint256 realizedLoss,
        uint256 estimatedAssets,
        uint256 liquidAssets
    );
    event EmergencyExitExecuted(address indexed receiver, uint256 withdrawn, uint256 loss);
    event TokenRecovered(address indexed token, address indexed receiver, uint256 amount);

    address public immutable override asset;
    address public immutable override vault;

    address public manager;
    address public keeper;
    bool public shutdown;

    uint64 public lastHarvest;
    uint256 public accountedAssets;
    uint256 public cumulativeDeposits;
    uint256 public cumulativeWithdrawals;
    uint256 public cumulativeRealizedGain;
    uint256 public cumulativeRealizedLoss;

    uint256 private _reentrancyStatus;

    constructor(address asset_, address vault_, address manager_) {
        if (asset_ == address(0) || vault_ == address(0) || manager_ == address(0)) {
            revert ZeroAddress();
        }

        asset = asset_;
        vault = vault_;
        manager = manager_;
        keeper = manager_;
        _reentrancyStatus = 1;

        emit ManagerUpdated(address(0), manager_);
        emit KeeperUpdated(address(0), manager_);
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyManagerOrVault() {
        if (msg.sender != manager && msg.sender != vault) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyGovernance() {
        address vaultOwner = IMeridianVaultGovernance(vault).owner();
        if (msg.sender != manager && msg.sender != vault && msg.sender != vaultOwner) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != manager && msg.sender != keeper && msg.sender != vault) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus != 1) revert ReentrantCall();
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    function setManager(address newManager) external onlyGovernance {
        if (newManager == address(0)) revert ZeroAddress();

        address previousManager = manager;
        manager = newManager;
        emit ManagerUpdated(previousManager, newManager);
    }

    function setKeeper(address newKeeper) external onlyGovernance {
        if (newKeeper == address(0)) revert ZeroAddress();

        address previousKeeper = keeper;
        keeper = newKeeper;
        emit KeeperUpdated(previousKeeper, newKeeper);
    }

    function setShutdown(bool shutdown_) external onlyGovernance {
        shutdown = shutdown_;
        emit ShutdownUpdated(shutdown_);
    }

    /// @notice Returns idle assets plus the adapter's current quoted position value.
    function estimatedTotalAssets() public view virtual override returns (uint256) {
        return asset.safeBalanceOf(address(this)) + _estimatedInvestedAssets();
    }

    /// @notice Returns the portion currently transferable or withdrawable from the venue.
    function liquidTotalAssets() public view virtual override returns (uint256) {
        uint256 estimated = estimatedTotalAssets();
        uint256 liquid = asset.safeBalanceOf(address(this)) + _liquidInvestedAssets();
        return liquid < estimated ? liquid : estimated;
    }

    function maxDeposit() public view virtual override returns (uint256) {
        if (shutdown) return 0;
        return _maxInvestableAssets();
    }

    function maxWithdraw() public view virtual override returns (uint256) {
        uint256 idle = asset.safeBalanceOf(address(this));
        uint256 venueLimit = _maxWithdrawableInvestedAssets();
        uint256 operationalLimit;

        unchecked {
            operationalLimit =
                type(uint256).max - idle < venueLimit ? type(uint256).max : idle + venueLimit;
        }

        uint256 liquid = liquidTotalAssets();
        return operationalLimit < liquid ? operationalLimit : liquid;
    }

    /// @inheritdoc IMeridianStrategy
    function deposit(uint256 assets)
        external
        virtual
        override
        onlyManagerOrVault
        nonReentrant
        returns (uint256 deployed)
    {
        if (shutdown) revert StrategyIsShutdown();
        if (assets == 0) return 0;

        uint256 limit = maxDeposit();
        if (assets > limit) revert DepositAboveLimit(assets, limit);

        uint256 idle = asset.safeBalanceOf(address(this));
        if (assets > idle) revert InsufficientIdleAssets(idle, assets);

        deployed = _deployFunds(assets);
        if (deployed > assets) revert InvalidManagedAmount(deployed, assets);

        accountedAssets += assets;
        cumulativeDeposits += assets;

        emit AssetsManaged(assets, deployed, accountedAssets);
    }

    /// @inheritdoc IMeridianStrategy
    function withdraw(uint256 assets, address receiver)
        external
        virtual
        override
        onlyManagerOrVault
        nonReentrant
        returns (uint256 withdrawn, uint256 loss)
    {
        if (receiver == address(0)) revert ZeroAddress();
        return _withdrawAssets(assets, receiver);
    }

    /// @inheritdoc IMeridianStrategy
    function withdrawAll(address receiver)
        external
        virtual
        override
        onlyManagerOrVault
        nonReentrant
        returns (uint256 withdrawn, uint256 loss)
    {
        if (receiver == address(0)) revert ZeroAddress();

        uint256 expected = accountedAssets;
        _freeAllFunds();
        return _settlePositionExit(receiver, expected);
    }

    /// @inheritdoc IMeridianStrategy
    function harvest(bytes calldata data)
        external
        virtual
        override
        onlyManagerOrVault
        nonReentrant
        returns (uint256 realizedGain, uint256 realizedLoss)
    {
        (realizedGain, realizedLoss) = _harvest(data);
        if (realizedGain != 0 && realizedLoss != 0) {
            revert InvalidRealization(realizedGain, realizedLoss);
        }

        if (realizedGain != 0) {
            accountedAssets += realizedGain;
            cumulativeRealizedGain += realizedGain;
        } else if (realizedLoss != 0) {
            uint256 recognized = realizedLoss < accountedAssets ? realizedLoss : accountedAssets;
            accountedAssets -= recognized;
            cumulativeRealizedLoss += realizedLoss;
        }

        lastHarvest = uint64(block.timestamp);
        emit StrategyHarvested(
            msg.sender, realizedGain, realizedLoss, estimatedTotalAssets(), liquidTotalAssets()
        );
    }

    /// @inheritdoc IMeridianStrategy
    function emergencyExit(address receiver)
        external
        virtual
        override
        onlyManagerOrVault
        nonReentrant
        returns (uint256 withdrawn, uint256 loss)
    {
        if (receiver == address(0)) revert ZeroAddress();

        if (!shutdown) {
            shutdown = true;
            emit ShutdownUpdated(true);
        }

        uint256 expected = accountedAssets;
        _emergencyFreeFunds();
        (withdrawn, loss) = _settlePositionExit(receiver, expected);
        emit EmergencyExitExecuted(receiver, withdrawn, loss);
    }

    function recoverToken(address token, address receiver, uint256 amount)
        external
        onlyGovernance
        nonReentrant
    {
        if (token == asset) revert ProtectedAsset();
        if (token == address(0) || receiver == address(0)) revert ZeroAddress();

        token.safeTransfer(receiver, amount);
        emit TokenRecovered(token, receiver, amount);
    }

    function _withdrawAssets(uint256 assets, address receiver)
        internal
        returns (uint256 withdrawn, uint256 loss)
    {
        if (assets == 0) return (0, 0);

        uint256 idle = asset.safeBalanceOf(address(this));
        if (idle < assets) {
            uint256 needed = assets - idle;
            uint256 venueLimit = _maxWithdrawableInvestedAssets();
            uint256 requestedFromVenue = needed < venueLimit ? needed : venueLimit;
            if (requestedFromVenue != 0) _freeFunds(requestedFromVenue);
            idle = asset.safeBalanceOf(address(this));
        }

        withdrawn = assets < idle ? assets : idle;
        loss = assets - withdrawn;

        if (withdrawn != 0) asset.safeTransfer(receiver, withdrawn);

        uint256 accountedReduction = assets < accountedAssets ? assets : accountedAssets;
        accountedAssets -= accountedReduction;
        cumulativeWithdrawals += withdrawn;
        cumulativeRealizedLoss += loss;

        emit AssetsReturned(receiver, assets, withdrawn, loss, accountedAssets);
    }

    function _settlePositionExit(address receiver, uint256 expected)
        internal
        returns (uint256 withdrawn, uint256 loss)
    {
        withdrawn = asset.safeBalanceOf(address(this));
        uint256 remainingValue = _estimatedInvestedAssets();
        uint256 recoveredValue = withdrawn + remainingValue;
        loss = expected > recoveredValue ? expected - recoveredValue : 0;

        uint256 reduction = withdrawn + loss;
        if (reduction > expected) reduction = expected;
        accountedAssets = expected - reduction;
        cumulativeWithdrawals += withdrawn;
        cumulativeRealizedLoss += loss;

        if (withdrawn != 0) asset.safeTransfer(receiver, withdrawn);
        emit AssetsReturned(receiver, expected, withdrawn, loss, accountedAssets);
    }

    function _estimatedInvestedAssets() internal view virtual returns (uint256);

    function _liquidInvestedAssets() internal view virtual returns (uint256);

    function _maxInvestableAssets() internal view virtual returns (uint256);

    function _maxWithdrawableInvestedAssets() internal view virtual returns (uint256);

    function _deployFunds(uint256 assets) internal virtual returns (uint256 deployed);

    function _freeFunds(uint256 assets) internal virtual returns (uint256 withdrawn);

    function _freeAllFunds() internal virtual returns (uint256 withdrawn);

    function _harvest(bytes calldata data)
        internal
        virtual
        returns (uint256 realizedGain, uint256 realizedLoss);

    function _emergencyFreeFunds() internal virtual returns (uint256 withdrawn) {
        return _freeAllFunds();
    }
}
