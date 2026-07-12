// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20, IERC20Metadata } from "../interfaces/IERC20.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IMeridianStrategy } from "../interfaces/IMeridianStrategy.sol";
import { IStrategyRegistry } from "../interfaces/IStrategyRegistry.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { MeridianERC20 } from "../token/MeridianERC20.sol";
import { MeridianRoles } from "../access/MeridianRoles.sol";
import { MeridianTypes } from "../types/MeridianTypes.sol";
import { MeridianFeePolicy } from "./MeridianFeePolicy.sol";

/// @title MeridianVault
/// @notice ERC-4626 stablecoin vault with governed multi-strategy allocation.
contract MeridianVault is MeridianERC20, MeridianRoles, IERC4626 {
    using MathLib for uint256;
    using SafeTransferLib for address;

    uint256 public constant BASIS_POINTS = 10_000;
    uint8 public constant DECIMALS_OFFSET = 3;
    uint16 public constant MAX_IDLE_BPS = 5000;
    uint16 public constant MAX_WITHDRAWAL_LOSS_BPS = 1000;

    error MeridianVault__InvalidAsset();
    error MeridianVault__InvalidRegistry();
    error MeridianVault__InvalidFeePolicy();
    error MeridianVault__InvalidReceiver();
    error MeridianVault__ZeroAssets();
    error MeridianVault__ZeroShares();
    error MeridianVault__DepositTooSmall(uint256 supplied, uint256 minimum);
    error MeridianVault__DepositLimitExceeded(uint256 supplied, uint256 maximum);
    error MeridianVault__MintLimitExceeded(uint256 supplied, uint256 maximum);
    error MeridianVault__WithdrawLimitExceeded(uint256 supplied, uint256 maximum);
    error MeridianVault__RedeemLimitExceeded(uint256 supplied, uint256 maximum);
    error MeridianVault__InsufficientLiquidity(uint256 requested, uint256 available);
    error MeridianVault__WithdrawalLossExceeded(uint256 observed, uint256 maximum);
    error MeridianVault__IdleReserveViolation(uint256 remaining, uint256 required);
    error MeridianVault__InvalidRiskParameter();
    error MeridianVault__AllocationMismatch(uint256 requested, uint256 allocated);
    error MeridianVault__UnsupportedToken(address token);
    error MeridianVault__RegistryAssetMismatch(address expected, address observed);

    event StrategyAllocated(address indexed strategy, uint256 assets);
    event StrategyWithdrawalSkipped(address indexed strategy, bytes reason);
    event StrategyLiquidityRecovered(
        address indexed strategy, uint256 requested, uint256 withdrawn, uint256 loss
    );
    event StrategyCheckpointed(
        address indexed strategy, uint256 estimatedAssets, uint256 liquidAssets, uint256 timestamp
    );
    event StrategyHarvested(
        address indexed strategy, uint256 realizedGain, uint256 realizedLoss, uint256 feeShares
    );
    event FeePolicyUpdated(address indexed previousPolicy, address indexed newPolicy);
    event DepositCapUpdated(uint256 previousCap, uint256 newCap);
    event MinimumDepositUpdated(uint256 previousMinimum, uint256 newMinimum);
    event ReceiverLimitUpdated(address indexed receiver, uint256 previousLimit, uint256 newLimit);
    event IdleReserveUpdated(uint16 previousBps, uint16 newBps);
    event WithdrawalLossLimitUpdated(uint16 previousBps, uint16 newBps);
    event TokenRecovered(address indexed token, address indexed receiver, uint256 amount);

    address private immutable _assetToken;
    IStrategyRegistry public immutable strategyRegistry;
    MeridianFeePolicy public feePolicy;

    uint256 public depositCap;
    uint256 public minimumDeposit;
    uint16 public minimumIdleBps;
    uint16 public maximumWithdrawalLossBps;

    mapping(address receiver => uint256 limit) public receiverAssetLimit;

    constructor(
        address initialOwner,
        address asset_,
        IStrategyRegistry strategyRegistry_,
        MeridianFeePolicy feePolicy_,
        string memory name_,
        string memory symbol_,
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) MeridianERC20(name_, symbol_, _shareDecimals(asset_)) MeridianRoles(initialOwner) {
        if (asset_ == address(0) || asset_.code.length == 0) {
            revert MeridianVault__InvalidAsset();
        }
        if (address(strategyRegistry_) == address(0)) {
            revert MeridianVault__InvalidRegistry();
        }
        if (address(feePolicy_) == address(0) || address(feePolicy_).code.length == 0) {
            revert MeridianVault__InvalidFeePolicy();
        }

        address registryAsset = strategyRegistry_.asset();
        if (registryAsset != asset_) {
            revert MeridianVault__RegistryAssetMismatch(asset_, registryAsset);
        }

        _assetToken = asset_;
        strategyRegistry = strategyRegistry_;
        feePolicy = feePolicy_;
        depositCap = depositCap_;
        minimumDeposit = minimumDeposit_;
        minimumIdleBps = 500;
        maximumWithdrawalLossBps = 100;
    }

    function asset() external view override returns (address) {
        return _assetToken;
    }

    function totalAssets() public view override returns (uint256) {
        return _assetToken.safeBalanceOf(address(this)) + strategyRegistry.totalReportedAssets();
    }

    function idleAssets() public view returns (uint256) {
        return _assetToken.safeBalanceOf(address(this));
    }

    function strategyAssets() external view returns (uint256) {
        return strategyRegistry.totalReportedAssets();
    }

    function totalDebt() external view returns (uint256) {
        return strategyRegistry.totalDebt();
    }

    function liquidAssets() public view returns (uint256 liquid) {
        liquid = idleAssets();
        address[] memory queue = strategyRegistry.withdrawalQueue();
        uint256 length = queue.length;

        for (uint256 i; i < length;) {
            try IMeridianStrategy(queue[i]).maxWithdraw() returns (uint256 available) {
                liquid += available;
            } catch { }

            unchecked {
                ++i;
            }
        }
    }

    function pricePerShare() external view returns (uint256) {
        return _convertToAssets(10 ** decimals, MathLib.Rounding.Down);
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, MathLib.Rounding.Down);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, MathLib.Rounding.Down);
    }

    function maxDeposit(address receiver) public view override returns (uint256 maximum) {
        if (paused || receiver == address(0)) {
            return 0;
        }

        uint256 managed = totalAssets();
        maximum = depositCap == 0 || managed >= depositCap ? 0 : depositCap - managed;
        if (depositCap == 0) {
            maximum = type(uint256).max;
        }

        uint256 receiverLimit = receiverAssetLimit[receiver];
        if (receiverLimit != 0) {
            uint256 receiverAssets = convertToAssets(balanceOf[receiver]);
            uint256 receiverHeadroom =
                receiverAssets >= receiverLimit ? 0 : receiverLimit - receiverAssets;
            maximum = maximum.min(receiverHeadroom);
        }
        if (maximum < minimumDeposit) return 0;
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 fee = feePolicy.depositFee(address(this), assets);
        return _convertToShares(assets - fee, MathLib.Rounding.Down);
    }

    function deposit(uint256 assets, address receiver)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        _validateDepositRequest(assets, receiver);
        uint256 maximum = maxDeposit(receiver);
        if (assets > maximum) {
            revert MeridianVault__DepositLimitExceeded(assets, maximum);
        }

        shares = previewDeposit(assets);
        if (shares == 0) {
            revert MeridianVault__ZeroShares();
        }

        _executeDeposit(msg.sender, receiver, assets, shares);
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maximumAssets = maxDeposit(receiver);
        if (maximumAssets == type(uint256).max) {
            return type(uint256).max;
        }
        uint256 maximumShares = previewDeposit(maximumAssets);
        if (maximumShares != 0 && previewMint(maximumShares) > maximumAssets) {
            maximumShares = previewDeposit(maximumAssets - 1);
        }
        return maximumShares;
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 netAssets = _convertToAssets(shares, MathLib.Rounding.Up);
        return feePolicy.grossDepositAssets(address(this), netAssets);
    }

    function mint(uint256 shares, address receiver)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) {
            revert MeridianVault__ZeroShares();
        }
        if (receiver == address(0)) {
            revert MeridianVault__InvalidReceiver();
        }

        uint256 maximum = maxMint(receiver);
        if (shares > maximum) {
            revert MeridianVault__MintLimitExceeded(shares, maximum);
        }

        assets = previewMint(shares);
        if (assets < minimumDeposit) {
            revert MeridianVault__DepositTooSmall(assets, minimumDeposit);
        }
        uint256 maximumAssets = maxDeposit(receiver);
        if (assets > maximumAssets) {
            revert MeridianVault__DepositLimitExceeded(assets, maximumAssets);
        }

        _executeDeposit(msg.sender, receiver, assets, shares);
    }

    function maxWithdraw(address owner_) public view override returns (uint256) {
        uint256 availableShares = maxRedeem(owner_);
        uint256 maximum = previewRedeem(availableShares);
        if (maximum != 0 && previewWithdraw(maximum) > availableShares) {
            --maximum;
        }
        return maximum;
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 grossAssets = feePolicy.grossWithdrawalAssets(address(this), assets);
        return _convertToShares(grossAssets, MathLib.Rounding.Up);
    }

    function withdraw(uint256 assets, address receiver, address owner_)
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) {
            revert MeridianVault__ZeroAssets();
        }
        _validateWithdrawalParties(receiver, owner_);

        uint256 maximum = maxWithdraw(owner_);
        if (assets > maximum) {
            revert MeridianVault__WithdrawLimitExceeded(assets, maximum);
        }

        shares = previewWithdraw(assets);
        uint256 grossAssets = feePolicy.grossWithdrawalAssets(address(this), assets);
        _executeWithdrawal(msg.sender, receiver, owner_, grossAssets, assets, shares);
    }

    function maxRedeem(address owner_) public view override returns (uint256) {
        uint256 ownerShares = balanceOf[owner_];
        uint256 liquidityShares = _convertToShares(liquidAssets(), MathLib.Rounding.Down);
        return ownerShares.min(liquidityShares);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 grossAssets = _convertToAssets(shares, MathLib.Rounding.Down);
        return grossAssets - feePolicy.withdrawalFee(address(this), grossAssets);
    }

    function redeem(uint256 shares, address receiver, address owner_)
        external
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) {
            revert MeridianVault__ZeroShares();
        }
        _validateWithdrawalParties(receiver, owner_);

        uint256 maximum = maxRedeem(owner_);
        if (shares > maximum) {
            revert MeridianVault__RedeemLimitExceeded(shares, maximum);
        }

        uint256 grossAssets = _convertToAssets(shares, MathLib.Rounding.Down);
        assets = grossAssets - feePolicy.withdrawalFee(address(this), grossAssets);
        if (assets == 0) {
            revert MeridianVault__ZeroAssets();
        }

        _executeWithdrawal(msg.sender, receiver, owner_, grossAssets, assets, shares);
    }

    function allocate(address strategy, uint256 assets)
        public
        onlyRole(ALLOCATOR_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 allocated)
    {
        if (assets == 0) {
            revert MeridianVault__ZeroAssets();
        }

        uint256 idle = idleAssets();
        uint256 requiredIdle = totalAssets().mulDiv(minimumIdleBps, BASIS_POINTS);
        if (idle < assets || idle - assets < requiredIdle) {
            revert MeridianVault__IdleReserveViolation(
                idle < assets ? 0 : idle - assets, requiredIdle
            );
        }

        _assetToken.safeTransfer(strategy, assets);
        allocated = strategyRegistry.allocate(strategy, assets);
        if (allocated != assets) {
            revert MeridianVault__AllocationMismatch(assets, allocated);
        }

        emit StrategyAllocated(strategy, allocated);
    }

    function allocateBatch(MeridianTypes.Allocation[] calldata allocations)
        external
        onlyRole(ALLOCATOR_ROLE)
        whenNotPaused
        returns (uint256 totalAllocated)
    {
        uint256 length = allocations.length;
        for (uint256 i; i < length;) {
            totalAllocated += allocate(allocations[i].strategy, allocations[i].assets);
            unchecked {
                ++i;
            }
        }
    }

    function recoverStrategyLiquidity(address strategy, uint256 assets)
        external
        onlyRole(ALLOCATOR_ROLE)
        nonReentrant
        returns (uint256 withdrawn, uint256 loss)
    {
        (withdrawn, loss) = strategyRegistry.withdraw(strategy, assets, address(this));
        _validateLoss(withdrawn + loss, loss);
        emit StrategyLiquidityRecovered(strategy, assets, withdrawn, loss);
    }

    function recoverAllStrategyLiquidity(address strategy)
        external
        onlyRole(GUARDIAN_ROLE)
        nonReentrant
        returns (uint256 withdrawn, uint256 loss)
    {
        uint256 expected = strategyRegistry.getStrategyState(strategy).lastEstimatedAssets;
        (withdrawn, loss) = strategyRegistry.withdrawAll(strategy, address(this));
        _validateLoss(withdrawn + loss, loss);
        emit StrategyLiquidityRecovered(strategy, expected, withdrawn, loss);
    }

    function emergencyExitStrategy(address strategy)
        external
        onlyRole(GUARDIAN_ROLE)
        nonReentrant
        returns (uint256 withdrawn, uint256 loss)
    {
        uint256 expected = strategyRegistry.getStrategyState(strategy).lastEstimatedAssets;
        (withdrawn, loss) = strategyRegistry.emergencyExit(strategy, address(this));
        emit StrategyLiquidityRecovered(strategy, expected, withdrawn, loss);
    }

    function checkpointStrategy(address strategy)
        public
        onlyRole(KEEPER_ROLE)
        returns (MeridianTypes.StrategyReport memory report)
    {
        report = strategyRegistry.checkpoint(strategy);
        emit StrategyCheckpointed(
            strategy, report.estimatedAssets, report.liquidAssets, report.timestamp
        );
    }

    function checkpointStrategies(address[] calldata strategies)
        external
        onlyRole(KEEPER_ROLE)
        returns (uint256 totalEstimated, uint256 totalLiquid)
    {
        uint256 length = strategies.length;
        for (uint256 i; i < length;) {
            MeridianTypes.StrategyReport memory report = checkpointStrategy(strategies[i]);
            totalEstimated += report.estimatedAssets;
            totalLiquid += report.liquidAssets;
            unchecked {
                ++i;
            }
        }
    }

    function harvestStrategy(address strategy, bytes calldata data)
        external
        onlyRole(KEEPER_ROLE)
        nonReentrant
        returns (MeridianTypes.StrategyReport memory report)
    {
        report = strategyRegistry.harvest(strategy, data);

        uint256 feeShares;
        if (report.realizedGain != 0) {
            uint256 feeAssets = feePolicy.performanceFee(address(this), report.realizedGain);
            feeShares = MathLib.mulDiv(
                feeAssets,
                totalSupply + 10 ** DECIMALS_OFFSET,
                totalAssets() + 1 - feeAssets,
                MathLib.Rounding.Down
            );
            if (feeShares != 0) {
                _mint(feePolicy.treasury(), feeShares);
            }
        }

        emit StrategyHarvested(strategy, report.realizedGain, report.realizedLoss, feeShares);
        emit StrategyCheckpointed(
            strategy, report.estimatedAssets, report.liquidAssets, report.timestamp
        );
    }

    function setFeePolicy(MeridianFeePolicy newPolicy) external onlyRole(ADMIN_ROLE) {
        if (address(newPolicy) == address(0) || address(newPolicy).code.length == 0) {
            revert MeridianVault__InvalidFeePolicy();
        }
        address previous = address(feePolicy);
        feePolicy = newPolicy;
        emit FeePolicyUpdated(previous, address(newPolicy));
    }

    function setDepositCap(uint256 newCap) external onlyRole(ADMIN_ROLE) {
        uint256 previous = depositCap;
        depositCap = newCap;
        emit DepositCapUpdated(previous, newCap);
    }

    function setMinimumDeposit(uint256 newMinimum) external onlyRole(ADMIN_ROLE) {
        uint256 previous = minimumDeposit;
        minimumDeposit = newMinimum;
        emit MinimumDepositUpdated(previous, newMinimum);
    }

    function setReceiverAssetLimit(address receiver, uint256 newLimit)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (receiver == address(0)) {
            revert MeridianVault__InvalidReceiver();
        }
        uint256 previous = receiverAssetLimit[receiver];
        receiverAssetLimit[receiver] = newLimit;
        emit ReceiverLimitUpdated(receiver, previous, newLimit);
    }

    function setMinimumIdleBps(uint16 newBps) external onlyRole(ADMIN_ROLE) {
        if (newBps > MAX_IDLE_BPS) {
            revert MeridianVault__InvalidRiskParameter();
        }
        uint16 previous = minimumIdleBps;
        minimumIdleBps = newBps;
        emit IdleReserveUpdated(previous, newBps);
    }

    function setMaximumWithdrawalLossBps(uint16 newBps) external onlyRole(ADMIN_ROLE) {
        if (newBps > MAX_WITHDRAWAL_LOSS_BPS) {
            revert MeridianVault__InvalidRiskParameter();
        }
        uint16 previous = maximumWithdrawalLossBps;
        maximumWithdrawalLossBps = newBps;
        emit WithdrawalLossLimitUpdated(previous, newBps);
    }

    function recoverToken(address token, address receiver, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        if (token == _assetToken || token == address(this)) {
            revert MeridianVault__UnsupportedToken(token);
        }
        if (receiver == address(0)) {
            revert MeridianVault__InvalidReceiver();
        }
        token.safeTransfer(receiver, amount);
        emit TokenRecovered(token, receiver, amount);
    }

    function _executeDeposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
    {
        uint256 fee = feePolicy.depositFee(address(this), assets);
        _assetToken.safeTransferFrom(caller, address(this), assets);
        if (fee != 0) {
            _assetToken.safeTransfer(feePolicy.treasury(), fee);
        }
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _executeWithdrawal(
        address caller,
        address receiver,
        address owner_,
        uint256 grossAssets,
        uint256 netAssets,
        uint256 shares
    ) internal {
        if (caller != owner_) {
            _spendAllowance(owner_, caller, shares);
        }

        _burn(owner_, shares);
        _ensureLiquidity(grossAssets);

        uint256 fee = grossAssets - netAssets;
        if (fee != 0) {
            _assetToken.safeTransfer(feePolicy.treasury(), fee);
        }
        _assetToken.safeTransfer(receiver, netAssets);
        emit Withdraw(caller, receiver, owner_, netAssets, shares);
    }

    function _ensureLiquidity(uint256 requestedAssets) internal {
        uint256 idle = idleAssets();
        if (idle >= requestedAssets) {
            return;
        }

        uint256 remaining = requestedAssets - idle;
        uint256 totalLoss;
        uint256 totalWithdrawn;
        address[] memory queue = strategyRegistry.withdrawalQueue();
        uint256 length = queue.length;

        for (uint256 i; i < length && remaining != 0;) {
            uint256 request = remaining;
            try strategyRegistry.withdraw(queue[i], request, address(this)) returns (
                uint256 withdrawn, uint256 loss
            ) {
                totalLoss += loss;
                totalWithdrawn += withdrawn;
                remaining = withdrawn >= remaining ? 0 : remaining - withdrawn;
                emit StrategyLiquidityRecovered(queue[i], request, withdrawn, loss);
            } catch (bytes memory reason) {
                emit StrategyWithdrawalSkipped(queue[i], reason);
            }

            unchecked {
                ++i;
            }
        }

        _validateLoss(totalWithdrawn + totalLoss, totalLoss);
        uint256 available = idleAssets();
        if (available < requestedAssets) {
            revert MeridianVault__InsufficientLiquidity(requestedAssets, available);
        }
    }

    function _validateDepositRequest(uint256 assets, address receiver) internal view {
        if (assets == 0) {
            revert MeridianVault__ZeroAssets();
        }
        if (receiver == address(0)) {
            revert MeridianVault__InvalidReceiver();
        }
        if (assets < minimumDeposit) {
            revert MeridianVault__DepositTooSmall(assets, minimumDeposit);
        }
    }

    function _validateWithdrawalParties(address receiver, address owner_) internal pure {
        if (receiver == address(0) || owner_ == address(0)) {
            revert MeridianVault__InvalidReceiver();
        }
    }

    function _validateLoss(uint256 assets, uint256 loss) internal view {
        if (loss == 0 || assets == 0) {
            return;
        }
        uint256 maximum = assets.mulDiv(maximumWithdrawalLossBps, BASIS_POINTS);
        if (loss > maximum) {
            revert MeridianVault__WithdrawalLossExceeded(loss, maximum);
        }
    }

    function _convertToShares(uint256 assets, MathLib.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        return MathLib.mulDiv(
            assets, totalSupply + 10 ** DECIMALS_OFFSET, totalAssets() + 1, rounding
        );
    }

    function _convertToAssets(uint256 shares, MathLib.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        return MathLib.mulDiv(
            shares, totalAssets() + 1, totalSupply + 10 ** DECIMALS_OFFSET, rounding
        );
    }

    function _shareDecimals(address asset_) private view returns (uint8) {
        if (asset_ == address(0) || asset_.code.length == 0) {
            revert MeridianVault__InvalidAsset();
        }
        uint8 assetDecimals = IERC20Metadata(asset_).decimals();
        if (assetDecimals > type(uint8).max - DECIMALS_OFFSET) {
            revert MeridianVault__InvalidAsset();
        }
        return assetDecimals + DECIMALS_OFFSET;
    }
}
