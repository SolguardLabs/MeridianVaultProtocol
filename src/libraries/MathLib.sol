// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library MathLib {
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    enum Rounding {
        Down,
        Up
    }

    error MathDivisionByZero();
    error MathOverflow();
    error InvalidBps(uint256 bpsValue);

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function ceilDiv(uint256 a, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) revert MathDivisionByZero();
        if (a == 0) return 0;
        unchecked {
            return ((a - 1) / denominator) + 1;
        }
    }

    /// @notice Calculates floor(x * y / denominator) with full 512-bit precision.
    function mulDiv(uint256 x, uint256 y, uint256 denominator)
        internal
        pure
        returns (uint256 result)
    {
        unchecked {
            uint256 productLow;
            uint256 productHigh;
            assembly ("memory-safe") {
                let mm := mulmod(x, y, not(0))
                productLow := mul(x, y)
                productHigh := sub(sub(mm, productLow), lt(mm, productLow))
            }

            if (productHigh == 0) {
                if (denominator == 0) revert MathDivisionByZero();
                return productLow / denominator;
            }

            if (denominator <= productHigh) {
                if (denominator == 0) revert MathDivisionByZero();
                revert MathOverflow();
            }

            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(x, y, denominator)
                productHigh := sub(productHigh, gt(remainder, productLow))
                productLow := sub(productLow, remainder)
            }

            uint256 powerOfTwo = denominator & (0 - denominator);
            assembly ("memory-safe") {
                denominator := div(denominator, powerOfTwo)
                productLow := div(productLow, powerOfTwo)
                powerOfTwo := add(div(sub(0, powerOfTwo), powerOfTwo), 1)
            }

            productLow |= productHigh * powerOfTwo;

            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = productLow * inverse;
        }
    }

    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding)
        internal
        pure
        returns (uint256 result)
    {
        result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) != 0) {
            if (result == type(uint256).max) revert MathOverflow();
            unchecked {
                ++result;
            }
        }
    }

    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        return mulDiv(x, y, denominator, Rounding.Up);
    }

    function mulBpsDown(uint256 amount, uint256 bpsValue) internal pure returns (uint256) {
        _validateBps(bpsValue);
        return mulDiv(amount, bpsValue, BPS_DENOMINATOR);
    }

    function mulBpsUp(uint256 amount, uint256 bpsValue) internal pure returns (uint256) {
        _validateBps(bpsValue);
        return mulDiv(amount, bpsValue, BPS_DENOMINATOR, Rounding.Up);
    }

    function complementBps(uint256 bpsValue) internal pure returns (uint256) {
        _validateBps(bpsValue);
        unchecked {
            return BPS_DENOMINATOR - bpsValue;
        }
    }

    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a >= b ? a - b : b - a;
        }
    }

    function _validateBps(uint256 bpsValue) private pure {
        if (bpsValue > BPS_DENOMINATOR) revert InvalidBps(bpsValue);
    }
}
