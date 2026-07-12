// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMeridianStrategy {
    function asset() external view returns (address);
    function vault() external view returns (address);

    function estimatedTotalAssets() external view returns (uint256);
    function liquidTotalAssets() external view returns (uint256);
    function maxDeposit() external view returns (uint256);
    function maxWithdraw() external view returns (uint256);

    /// @notice Accounts for assets transferred to the strategy by its vault.
    function deposit(uint256 assets) external returns (uint256 deployed);

    function withdraw(uint256 assets, address receiver)
        external
        returns (uint256 withdrawn, uint256 loss);

    function withdrawAll(address receiver) external returns (uint256 withdrawn, uint256 loss);

    function harvest(bytes calldata data)
        external
        returns (uint256 realizedGain, uint256 realizedLoss);

    function emergencyExit(address receiver) external returns (uint256 withdrawn, uint256 loss);
}
