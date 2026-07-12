// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IYieldSource } from "../interfaces/IYieldSource.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

/// @notice Configurable yield venue used by the Meridian test suite.
contract MockYieldSource is IYieldSource {
    using SafeTransferLib for address;

    struct Position {
        uint128 principal;
        uint128 quotedYield;
        uint128 settledYield;
        uint128 manuallyUnlockedPrincipal;
        uint64 unlockTimestamp;
    }

    error Unauthorized(address caller);
    error ZeroAddress();
    error InvalidAsset(address asset);
    error ReentrantCall();
    error DepositsPaused();
    error DepositLimitExceeded(uint256 requested, uint256 available);
    error InvalidYieldAmount(uint256 requested, uint256 available);
    error InvalidPrincipalAmount(uint256 requested, uint256 available);
    error Uint128Overflow(uint256 value);
    error Uint64Overflow(uint256 value);
    error InsufficientSurplus(uint256 requested, uint256 available);

    event AdministratorUpdated(
        address indexed previousAdministrator, address indexed newAdministrator
    );
    event OperatorUpdated(address indexed operator, bool authorized);
    event AccountOperatorUpdated(
        address indexed account, address indexed operator, bool authorized
    );
    event DepositCapacityUpdated(uint256 previousCapacity, uint256 newCapacity);
    event WithdrawalLimitUpdated(uint256 previousLimit, uint256 newLimit);
    event LockDurationUpdated(uint64 previousDuration, uint64 newDuration);
    event DepositStatusUpdated(bool paused);
    event WithdrawalStatusUpdated(bool paused);
    event PositionOpened(
        address indexed caller, address indexed receiver, uint256 assets, uint256 unlockTimestamp
    );
    event PositionWithdrawn(
        address indexed caller,
        address indexed owner,
        address indexed receiver,
        uint256 requested,
        uint256 withdrawn
    );
    event YieldQuoted(address indexed account, uint256 amount, uint256 totalQuotedYield);
    event YieldSettled(address indexed account, uint256 amount, uint256 totalSettledYield);
    event YieldQuoteCancelled(
        address indexed account, uint256 amount, uint256 remainingQuotedYield
    );
    event PrincipalUnlocked(address indexed account, uint256 amount, uint256 totalUnlocked);
    event PrincipalAdjusted(address indexed account, uint256 amount, uint256 remainingPrincipal);
    event RewardsClaimed(address indexed account, address indexed receiver, uint256 amount);
    event SurplusRecovered(address indexed receiver, uint256 amount);

    address public immutable override asset;
    address public administrator;

    uint64 public lockDuration;
    uint256 public depositCapacity;
    uint256 public withdrawalLimit;
    bool public depositPaused;
    bool public withdrawalPaused;

    uint256 public totalPrincipal;
    uint256 public totalQuotedYield;
    uint256 public totalSettledYield;

    mapping(address account => Position position) private _positions;
    mapping(address operator => bool authorized) public isOperator;
    mapping(address account => mapping(address operator => bool authorized)) public
        isAccountOperator;

    uint256 private _reentrancyStatus = 1;

    constructor(address asset_, address administrator_, uint64 lockDuration_) {
        if (asset_ == address(0)) revert InvalidAsset(asset_);
        if (administrator_ == address(0)) revert ZeroAddress();

        asset = asset_;
        administrator = administrator_;
        isOperator[administrator_] = true;
        lockDuration = lockDuration_;
        depositCapacity = type(uint256).max;
        withdrawalLimit = type(uint256).max;

        emit AdministratorUpdated(address(0), administrator_);
        emit OperatorUpdated(administrator_, true);
        emit DepositCapacityUpdated(0, type(uint256).max);
        emit WithdrawalLimitUpdated(0, type(uint256).max);
        emit LockDurationUpdated(0, lockDuration_);
    }

    modifier onlyAdministrator() {
        if (msg.sender != administrator) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyOperator() {
        if (!isOperator[msg.sender]) revert Unauthorized(msg.sender);
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus != 1) revert ReentrantCall();
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    function setAdministrator(address newAdministrator) external onlyAdministrator {
        if (newAdministrator == address(0)) revert ZeroAddress();

        address previousAdministrator = administrator;
        administrator = newAdministrator;
        isOperator[previousAdministrator] = false;
        isOperator[newAdministrator] = true;

        emit AdministratorUpdated(previousAdministrator, newAdministrator);
        emit OperatorUpdated(previousAdministrator, false);
        emit OperatorUpdated(newAdministrator, true);
    }

    function setOperator(address operator, bool authorized) external onlyAdministrator {
        if (operator == address(0)) revert ZeroAddress();
        isOperator[operator] = authorized;
        emit OperatorUpdated(operator, authorized);
    }

    function setAccountOperator(address operator, bool authorized) external {
        if (operator == address(0)) revert ZeroAddress();
        isAccountOperator[msg.sender][operator] = authorized;
        emit AccountOperatorUpdated(msg.sender, operator, authorized);
    }

    function setDepositCapacity(uint256 newCapacity) external onlyOperator {
        uint256 previousCapacity = depositCapacity;
        depositCapacity = newCapacity;
        emit DepositCapacityUpdated(previousCapacity, newCapacity);
    }

    function setWithdrawalLimit(uint256 newLimit) external onlyOperator {
        uint256 previousLimit = withdrawalLimit;
        withdrawalLimit = newLimit;
        emit WithdrawalLimitUpdated(previousLimit, newLimit);
    }

    function setLockDuration(uint64 newDuration) external onlyOperator {
        uint64 previousDuration = lockDuration;
        lockDuration = newDuration;
        emit LockDurationUpdated(previousDuration, newDuration);
    }

    function setDepositPaused(bool paused) external onlyOperator {
        depositPaused = paused;
        emit DepositStatusUpdated(paused);
    }

    function setWithdrawalPaused(bool paused) external onlyOperator {
        withdrawalPaused = paused;
        emit WithdrawalStatusUpdated(paused);
    }

    function positionOf(address account) external view returns (Position memory) {
        return _positions[account];
    }

    function principalOf(address account) external view returns (uint256) {
        return _positions[account].principal;
    }

    function quotedYieldOf(address account) external view returns (uint256) {
        return _positions[account].quotedYield;
    }

    function settledYieldOf(address account) external view returns (uint256) {
        return _positions[account].settledYield;
    }

    function pendingYieldOf(address account) external view returns (uint256) {
        Position storage position = _positions[account];
        return uint256(position.quotedYield) - uint256(position.settledYield);
    }

    function unlockedPrincipalOf(address account) public view returns (uint256) {
        Position storage position = _positions[account];
        if (
            position.principal != 0 && position.unlockTimestamp != 0
                && block.timestamp >= position.unlockTimestamp
        ) {
            return position.principal;
        }

        uint256 manuallyUnlocked = position.manuallyUnlockedPrincipal;
        uint256 principal = position.principal;
        return manuallyUnlocked < principal ? manuallyUnlocked : principal;
    }

    function balanceOfUnderlying(address account) public view override returns (uint256) {
        Position storage position = _positions[account];
        return uint256(position.principal) + uint256(position.quotedYield);
    }

    function liquidBalanceOf(address account) public view override returns (uint256) {
        Position storage position = _positions[account];
        uint256 cash = asset.safeBalanceOf(address(this));
        uint256 rewardLiquidity = cash > totalPrincipal ? cash - totalPrincipal : 0;
        uint256 settled = position.settledYield;
        uint256 liquidYield = settled < rewardLiquidity ? settled : rewardLiquidity;
        return unlockedPrincipalOf(account) + liquidYield;
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (depositPaused || totalPrincipal >= depositCapacity) return 0;
        return depositCapacity - totalPrincipal;
    }

    function maxWithdraw(address account) public view override returns (uint256) {
        if (withdrawalPaused) return 0;

        uint256 liquid = liquidBalanceOf(account);
        return liquid < withdrawalLimit ? liquid : withdrawalLimit;
    }

    function deposit(uint256 assets, address receiver)
        external
        override
        nonReentrant
        returns (uint256 positionUnits)
    {
        if (depositPaused) revert DepositsPaused();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets == 0) return 0;

        uint256 available = maxDeposit(receiver);
        if (assets > available) revert DepositLimitExceeded(assets, available);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        Position storage position = _positions[receiver];
        position.principal = _toUint128(uint256(position.principal) + assets);
        totalPrincipal += assets;

        uint256 unlockTimestamp = block.timestamp + lockDuration;
        if (unlockTimestamp > type(uint64).max) revert Uint64Overflow(unlockTimestamp);
        if (unlockTimestamp > position.unlockTimestamp) {
            position.unlockTimestamp = uint64(unlockTimestamp);
        }

        positionUnits = assets;
        emit PositionOpened(msg.sender, receiver, assets, position.unlockTimestamp);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        external
        override
        nonReentrant
        returns (uint256 withdrawn)
    {
        if (receiver == address(0) || owner == address(0)) revert ZeroAddress();
        if (msg.sender != owner && !isAccountOperator[owner][msg.sender] && !isOperator[msg.sender])
        {
            revert Unauthorized(msg.sender);
        }
        if (assets == 0 || withdrawalPaused) return 0;

        uint256 available = maxWithdraw(owner);
        withdrawn = assets < available ? assets : available;
        if (withdrawn == 0) return 0;

        _consumeLiquidValue(owner, withdrawn);
        asset.safeTransfer(receiver, withdrawn);

        emit PositionWithdrawn(msg.sender, owner, receiver, assets, withdrawn);
    }

    function claimRewards(address receiver)
        external
        override
        nonReentrant
        returns (uint256 rewardAssets)
    {
        if (receiver == address(0)) revert ZeroAddress();

        Position storage position = _positions[msg.sender];
        uint256 settled = position.settledYield;
        uint256 cash = asset.safeBalanceOf(address(this));
        uint256 rewardLiquidity = cash > totalPrincipal ? cash - totalPrincipal : 0;
        rewardAssets = settled < rewardLiquidity ? settled : rewardLiquidity;
        if (rewardAssets == 0) return 0;

        position.settledYield = _toUint128(settled - rewardAssets);
        position.quotedYield = _toUint128(uint256(position.quotedYield) - rewardAssets);
        totalSettledYield -= rewardAssets;
        totalQuotedYield -= rewardAssets;

        asset.safeTransfer(receiver, rewardAssets);
        emit RewardsClaimed(msg.sender, receiver, rewardAssets);
    }

    function quoteYield(address account, uint256 amount) external onlyOperator {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        Position storage position = _positions[account];
        position.quotedYield = _toUint128(uint256(position.quotedYield) + amount);
        totalQuotedYield += amount;

        emit YieldQuoted(account, amount, position.quotedYield);
    }

    function settleYield(address account, uint256 amount) external onlyOperator {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        Position storage position = _positions[account];
        uint256 pending = uint256(position.quotedYield) - uint256(position.settledYield);
        if (amount > pending) revert InvalidYieldAmount(amount, pending);

        position.settledYield = _toUint128(uint256(position.settledYield) + amount);
        totalSettledYield += amount;

        emit YieldSettled(account, amount, position.settledYield);
    }

    function settleAllYield(address account) external onlyOperator returns (uint256 settled) {
        if (account == address(0)) revert ZeroAddress();

        Position storage position = _positions[account];
        settled = uint256(position.quotedYield) - uint256(position.settledYield);
        if (settled == 0) return 0;

        position.settledYield = position.quotedYield;
        totalSettledYield += settled;
        emit YieldSettled(account, settled, position.settledYield);
    }

    function cancelYieldQuote(address account, uint256 amount) external onlyOperator {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        Position storage position = _positions[account];
        uint256 cancellable = uint256(position.quotedYield) - uint256(position.settledYield);
        if (amount > cancellable) revert InvalidYieldAmount(amount, cancellable);

        position.quotedYield = _toUint128(uint256(position.quotedYield) - amount);
        totalQuotedYield -= amount;

        emit YieldQuoteCancelled(account, amount, position.quotedYield);
    }

    function unlockPrincipal(address account, uint256 amount) external onlyOperator {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        Position storage position = _positions[account];
        uint256 principal = position.principal;
        uint256 unlocked = unlockedPrincipalOf(account);
        uint256 unlockable = principal - unlocked;
        if (amount > unlockable) revert InvalidPrincipalAmount(amount, unlockable);

        position.manuallyUnlockedPrincipal = _toUint128(unlocked + amount);
        emit PrincipalUnlocked(account, amount, unlocked + amount);
    }

    function adjustPrincipal(address account, uint256 amount) external onlyOperator {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        Position storage position = _positions[account];
        uint256 principal = position.principal;
        if (amount > principal) revert InvalidPrincipalAmount(amount, principal);

        uint256 remaining = principal - amount;
        position.principal = _toUint128(remaining);
        if (position.manuallyUnlockedPrincipal > remaining) {
            position.manuallyUnlockedPrincipal = _toUint128(remaining);
        }
        totalPrincipal -= amount;

        emit PrincipalAdjusted(account, amount, remaining);
    }

    function recoverSurplus(address receiver, uint256 amount) external onlyOperator nonReentrant {
        if (receiver == address(0)) revert ZeroAddress();

        uint256 cash = asset.safeBalanceOf(address(this));
        uint256 obligations = totalPrincipal + totalSettledYield;
        uint256 surplus = cash > obligations ? cash - obligations : 0;
        if (amount > surplus) revert InsufficientSurplus(amount, surplus);

        asset.safeTransfer(receiver, amount);
        emit SurplusRecovered(receiver, amount);
    }

    function _consumeLiquidValue(address account, uint256 amount) internal {
        Position storage position = _positions[account];
        uint256 fromYield = amount < position.settledYield ? amount : position.settledYield;

        if (fromYield != 0) {
            position.settledYield = _toUint128(uint256(position.settledYield) - fromYield);
            position.quotedYield = _toUint128(uint256(position.quotedYield) - fromYield);
            totalSettledYield -= fromYield;
            totalQuotedYield -= fromYield;
        }

        uint256 fromPrincipal = amount - fromYield;
        if (fromPrincipal == 0) return;

        uint256 unlocked = unlockedPrincipalOf(account);
        if (fromPrincipal > unlocked) revert InvalidPrincipalAmount(fromPrincipal, unlocked);

        uint256 remainingPrincipal = uint256(position.principal) - fromPrincipal;
        position.principal = _toUint128(remainingPrincipal);
        if (position.manuallyUnlockedPrincipal > remainingPrincipal) {
            position.manuallyUnlockedPrincipal = _toUint128(remainingPrincipal);
        } else if (position.unlockTimestamp == 0 || block.timestamp < position.unlockTimestamp) {
            position.manuallyUnlockedPrincipal =
                _toUint128(uint256(position.manuallyUnlockedPrincipal) - fromPrincipal);
        }
        totalPrincipal -= fromPrincipal;
    }

    function _toUint128(uint256 value) internal pure returns (uint128 narrowed) {
        if (value > type(uint128).max) revert Uint128Overflow(value);
        narrowed = uint128(value);
    }
}
