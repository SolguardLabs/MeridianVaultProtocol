// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal adapter surface for an external yield venue.
interface IYieldSource {
    function asset() external view returns (address);
    function balanceOfUnderlying(address account) external view returns (uint256);
    function liquidBalanceOf(address account) external view returns (uint256);

    function maxDeposit(address account) external view returns (uint256);
    function maxWithdraw(address account) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 positionUnits);

    function withdraw(uint256 assets, address receiver, address owner)
        external
        returns (uint256 withdrawn);

    function claimRewards(address receiver) external returns (uint256 rewardAssets);
}
