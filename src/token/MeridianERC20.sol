// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20, IERC20Metadata, IERC20Permit } from "../interfaces/IERC20.sol";

contract MeridianERC20 is IERC20Metadata, IERC20Permit {
    string public override name;
    string public override symbol;
    uint8 public immutable override decimals;

    uint256 public override totalSupply;
    mapping(address account => uint256 balance) public override balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public override allowance;
    mapping(address owner => uint256 nonce) public override nonces;

    uint256 private immutable _initialChainId;
    bytes32 private immutable _initialDomainSeparator;

    bytes32 private constant _EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant _PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant _VERSION_HASH = keccak256("1");
    uint256 private constant _SECP256K1N_HALF =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);
    error ERC20InsufficientBalance(address account, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowanceValue, uint256 needed);
    error PermitExpired(uint256 deadline);
    error InvalidPermitSignature();

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        _initialChainId = block.chainid;
        _initialDomainSeparator = _computeDomainSeparator();
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return
            block.chainid == _initialChainId ? _initialDomainSeparator : _computeDomainSeparator();
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        if (block.timestamp > deadline) revert PermitExpired(deadline);
        if (owner == address(0) || spender == address(0)) revert InvalidPermitSignature();
        if (v != 27 && v != 28) revert InvalidPermitSignature();
        if (uint256(s) > _SECP256K1N_HALF) revert InvalidPermitSignature();

        uint256 nonce = nonces[owner];
        bytes32 structHash =
            keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != owner) revert InvalidPermitSignature();

        unchecked {
            nonces[owner] = nonce + 1;
        }
        _approve(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        if (from == address(0)) revert ERC20InvalidSender(from);
        if (to == address(0)) revert ERC20InvalidReceiver(to);

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) {
            revert ERC20InsufficientBalance(from, fromBalance, amount);
        }
        unchecked {
            balanceOf[from] = fromBalance - amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal virtual {
        if (to == address(0)) revert ERC20InvalidReceiver(to);

        _beforeTokenTransfer(address(0), to, amount);
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
        _afterTokenTransfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        if (from == address(0)) revert ERC20InvalidSender(from);

        _beforeTokenTransfer(from, address(0), amount);

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) {
            revert ERC20InsufficientBalance(from, fromBalance, amount);
        }
        unchecked {
            balanceOf[from] = fromBalance - amount;
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
        _afterTokenTransfer(from, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        if (owner == address(0)) revert ERC20InvalidApprover(owner);
        if (spender == address(0)) revert ERC20InvalidSpender(spender);
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance[owner][spender];
        if (currentAllowance == type(uint256).max) return;
        if (currentAllowance < amount) {
            revert ERC20InsufficientAllowance(spender, currentAllowance, amount);
        }
        unchecked {
            allowance[owner][spender] = currentAllowance - amount;
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual { }

    function _computeDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                _VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }
}
