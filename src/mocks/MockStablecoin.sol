// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRoles } from "../access/MeridianRoles.sol";
import { MeridianERC20 } from "../token/MeridianERC20.sol";

/// @title MockStablecoin
/// @notice Configurable capped asset used by local Meridian deployments and tests.
contract MockStablecoin is MeridianERC20, MeridianRoles {
    error MockStablecoin__CapBelowSupply(uint256 suppliedCap, uint256 currentSupply);
    error MockStablecoin__CapExceeded(uint256 resultingSupply, uint256 cap);

    event CapUpdated(uint256 previousCap, uint256 newCap);

    /// @notice Maximum supply. A value of zero leaves the supply uncapped.
    uint256 public cap;

    constructor(
        address initialOwner,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 cap_
    ) MeridianERC20(name_, symbol_, decimals_) MeridianRoles(initialOwner) {
        cap = cap_;
    }

    /// @notice Updates the minting cap. Zero represents an uncapped supply.
    function setCap(uint256 newCap) external onlyRole(ADMIN_ROLE) {
        uint256 supply = totalSupply;
        if (newCap != 0 && newCap < supply) {
            revert MockStablecoin__CapBelowSupply(newCap, supply);
        }

        uint256 previous = cap;
        cap = newCap;
        emit CapUpdated(previous, newCap);
    }

    /// @notice Creates tokens for `receiver` subject to the configured cap.
    function mint(address receiver, uint256 amount) external onlyRole(ADMIN_ROLE) {
        uint256 resultingSupply = totalSupply + amount;
        uint256 currentCap = cap;
        if (currentCap != 0 && resultingSupply > currentCap) {
            revert MockStablecoin__CapExceeded(resultingSupply, currentCap);
        }

        _mint(receiver, amount);
    }

    /// @notice Burns tokens held by the caller.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burns tokens from `account` after consuming the caller's allowance.
    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /// @notice Returns the amount that can be minted before reaching the cap.
    function remainingMintableSupply() external view returns (uint256) {
        uint256 currentCap = cap;
        if (currentCap == 0) {
            return type(uint256).max;
        }
        return currentCap - totalSupply;
    }
}
