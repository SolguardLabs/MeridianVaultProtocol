// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MathLib } from "../../src/libraries/MathLib.sol";
import { TestBase } from "../helpers/TestBase.sol";

contract MathLibTest is TestBase {
    function testMulDivRoundsAsRequested() external pure {
        assertEq(MathLib.mulDiv(10, 10, 6), 16);
        assertEq(MathLib.mulDivUp(10, 10, 6), 17);
        assertEq(MathLib.mulDiv(10, 10, 5), 20);
        assertEq(MathLib.mulDivUp(10, 10, 5), 20);
    }

    function testMulDivUsesFullPrecision() external pure {
        uint256 x = type(uint256).max - 1;
        uint256 result = MathLib.mulDiv(x, 8, 16);
        assertEq(result, x / 2);
    }

    function testBasisPointHelpers() external pure {
        assertEq(MathLib.mulBpsDown(1_000_000, 125), 12_500);
        assertEq(MathLib.mulBpsUp(101, 100), 2);
        assertEq(MathLib.complementBps(125), 9875);
    }

    function testFuzzMulDivMatchesSimpleArithmetic(uint128 x, uint64 y, uint64 denominator)
        external
        pure
    {
        if (denominator == 0) denominator = 1;
        uint256 expected = uint256(x) * uint256(y) / uint256(denominator);
        assertEq(MathLib.mulDiv(x, y, denominator), expected);
    }
}
