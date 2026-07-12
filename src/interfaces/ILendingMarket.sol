// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Adapter surface used by Meridian lending strategies.
interface ILendingMarket {
    function asset() external view returns (address);

    function principalOf(address account) external view returns (uint256);
    function balanceOfUnderlying(address account) external view returns (uint256);
    function liquidBalanceOf(address account) external view returns (uint256);

    function maxSupply(address account) external view returns (uint256);
    function maxWithdraw(address account) external view returns (uint256);

    function supply(uint256 assets, address receiver) external returns (uint256 positionUnits);

    function withdraw(uint256 assets, address receiver, address owner)
        external
        returns (uint256 withdrawn);

    function claimInterest(address receiver) external returns (uint256 interestAssets);

    function claimIncentives(address receiver) external returns (uint256 incentiveAssets);
}
