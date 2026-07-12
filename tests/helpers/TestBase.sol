// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function warp(uint256 newTimestamp) external;
    function roll(uint256 newHeight) external;
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes4 selector) external;
    function expectRevert(bytes calldata revertData) external;
    function assume(bool condition) external;
    function deal(address account, uint256 newBalance) external;
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error AssertionFailed();
    error AssertionEqUint(uint256 left, uint256 right);
    error AssertionEqAddress(address left, address right);
    error AssertionEqBytes32(bytes32 left, bytes32 right);
    error AssertionEqBool(bool left, bool right);
    error AssertionGt(uint256 left, uint256 right);
    error AssertionGe(uint256 left, uint256 right);
    error AssertionLt(uint256 left, uint256 right);
    error AssertionLe(uint256 left, uint256 right);
    error AssertionApprox(uint256 left, uint256 right, uint256 tolerance);

    function assertTrue(bool condition) internal pure {
        if (!condition) revert AssertionFailed();
    }

    function assertFalse(bool condition) internal pure {
        if (condition) revert AssertionFailed();
    }

    function assertEq(uint256 left, uint256 right) internal pure {
        if (left != right) revert AssertionEqUint(left, right);
    }

    function assertEq(address left, address right) internal pure {
        if (left != right) revert AssertionEqAddress(left, right);
    }

    function assertEq(bytes32 left, bytes32 right) internal pure {
        if (left != right) revert AssertionEqBytes32(left, right);
    }

    function assertEq(bool left, bool right) internal pure {
        if (left != right) revert AssertionEqBool(left, right);
    }

    function assertGt(uint256 left, uint256 right) internal pure {
        if (left <= right) revert AssertionGt(left, right);
    }

    function assertGe(uint256 left, uint256 right) internal pure {
        if (left < right) revert AssertionGe(left, right);
    }

    function assertLt(uint256 left, uint256 right) internal pure {
        if (left >= right) revert AssertionLt(left, right);
    }

    function assertLe(uint256 left, uint256 right) internal pure {
        if (left > right) revert AssertionLe(left, right);
    }

    function assertApproxEqAbs(uint256 left, uint256 right, uint256 tolerance) internal pure {
        uint256 difference = left >= right ? left - right : right - left;
        if (difference > tolerance) revert AssertionApprox(left, right, tolerance);
    }

    function bound(uint256 value, uint256 minimum, uint256 maximum)
        internal
        pure
        returns (uint256)
    {
        if (minimum > maximum) revert AssertionFailed();
        if (value >= minimum && value <= maximum) return value;
        uint256 size = maximum - minimum + 1;
        return minimum + (value % size);
    }
}
