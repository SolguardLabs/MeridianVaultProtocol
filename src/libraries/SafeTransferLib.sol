// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "../interfaces/IERC20.sol";

library SafeTransferLib {
    error TransferFailed(address token, address to, uint256 amount);
    error TransferFromFailed(address token, address from, address to, uint256 amount);
    error ApproveFailed(address token, address spender, uint256 amount);
    error BalanceQueryFailed(address token, address account);
    error ETHTransferFailed(address to, uint256 amount);

    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory result) =
            token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        if (!_callSucceeded(success, result)) revert TransferFailed(token, to, amount);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory result) =
            token.call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        if (!_callSucceeded(success, result)) {
            revert TransferFromFailed(token, from, to, amount);
        }
    }

    function safeApprove(address token, address spender, uint256 amount) internal {
        if (!_tryApprove(token, spender, amount)) revert ApproveFailed(token, spender, amount);
    }

    /// @notice Supports tokens which require allowance to be reset before replacement.
    function forceApprove(address token, address spender, uint256 amount) internal {
        if (_tryApprove(token, spender, amount)) return;
        if (!_tryApprove(token, spender, 0) || !_tryApprove(token, spender, amount)) {
            revert ApproveFailed(token, spender, amount);
        }
    }

    function safeBalanceOf(address token, address account)
        internal
        view
        returns (uint256 tokenBalance)
    {
        (bool success, bytes memory result) =
            token.staticcall(abi.encodeCall(IERC20.balanceOf, (account)));
        if (!success || result.length < 32) revert BalanceQueryFailed(token, account);
        assembly ("memory-safe") {
            tokenBalance := mload(add(result, 0x20))
        }
    }

    function safeTransferETH(address to, uint256 amount) internal {
        (bool success,) = to.call{ value: amount }("");
        if (!success) revert ETHTransferFailed(to, amount);
    }

    function _tryApprove(address token, address spender, uint256 amount) private returns (bool) {
        (bool success, bytes memory result) =
            token.call(abi.encodeCall(IERC20.approve, (spender, amount)));
        return _callSucceeded(success, result);
    }

    function _callSucceeded(bool success, bytes memory result) private pure returns (bool) {
        if (!success) return false;
        if (result.length == 0) return true;
        if (result.length < 32) return false;

        uint256 returnedValue;
        assembly ("memory-safe") {
            returnedValue := mload(add(result, 0x20))
        }
        return returnedValue == 1;
    }
}
