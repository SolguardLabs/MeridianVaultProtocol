// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract MeridianRoles {
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    address public owner;
    address public pendingOwner;
    bool public paused;

    mapping(bytes32 role => mapping(address account => bool granted)) private _roles;

    uint256 private _reentrancyStatus;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    error Unauthorized(address account, bytes32 requiredRole);
    error OnlyOwner(address account);
    error InvalidOwner(address ownerAddress);
    error InvalidRoleAccount(address account);
    error NotPendingOwner(address account);
    error ContractPaused();
    error ContractNotPaused();
    error ReentrantCall();

    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferCanceled(address indexed owner, address indexed canceledPendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert InvalidOwner(initialOwner);
        owner = initialOwner;
        _reentrancyStatus = _NOT_ENTERED;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner(msg.sender);
        _;
    }

    modifier onlyRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier whenPaused() {
        if (!paused) revert ContractNotPaused();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus == _ENTERED) revert ReentrantCall();
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return account == owner || _roles[role][account];
    }

    function grantRole(bytes32 role, address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role) external {
        _revokeRole(role, msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner(newOwner);
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner(msg.sender);
        _transferOwnership(msg.sender);
    }

    function cancelOwnershipTransfer() external onlyOwner {
        address canceled = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferCanceled(owner, canceled);
    }

    function pause() external onlyRole(GUARDIAN_ROLE) whenNotPaused {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) whenPaused {
        _unpause();
    }

    function _checkRole(bytes32 role, address account) internal view {
        if (!hasRole(role, account)) revert Unauthorized(account, role);
    }

    function _grantRole(bytes32 role, address account) internal returns (bool granted) {
        if (account == address(0)) revert InvalidRoleAccount(account);
        if (_roles[role][account]) return false;
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
        return true;
    }

    function _revokeRole(bytes32 role, address account) internal returns (bool revoked) {
        if (!_roles[role][account]) return false;
        delete _roles[role][account];
        emit RoleRevoked(role, account, msg.sender);
        return true;
    }

    function _pause() internal {
        if (paused) revert ContractPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal {
        if (!paused) revert ContractNotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    function _transferOwnership(address newOwner) internal {
        if (newOwner == address(0)) revert InvalidOwner(newOwner);
        address previousOwner = owner;
        owner = newOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}
