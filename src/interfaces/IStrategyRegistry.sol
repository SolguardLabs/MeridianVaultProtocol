// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianTypes } from "../types/MeridianTypes.sol";

interface IStrategyRegistry {
    function asset() external view returns (address);
    function vault() external view returns (address);
    function totalReportedAssets() external view returns (uint256);
    function totalDebt() external view returns (uint256);

    function strategyCount() external view returns (uint256);
    function strategyAt(uint256 index) external view returns (address);
    function isStrategy(address strategy) external view returns (bool);

    function getStrategyConfig(address strategy)
        external
        view
        returns (MeridianTypes.StrategyConfig memory);

    function getStrategyState(address strategy)
        external
        view
        returns (MeridianTypes.StrategyState memory);

    function withdrawalQueue() external view returns (address[] memory);

    function addStrategy(MeridianTypes.StrategyConfig calldata config) external;
    function updateStrategy(MeridianTypes.StrategyConfig calldata config) external;
    function removeStrategy(address strategy) external;
    function setWithdrawalQueue(address[] calldata strategies) external;

    function allocate(address strategy, uint256 assets) external returns (uint256 allocated);

    function withdraw(address strategy, uint256 assets, address receiver)
        external
        returns (uint256 withdrawn, uint256 loss);

    function withdrawAll(address strategy, address receiver)
        external
        returns (uint256 withdrawn, uint256 loss);

    function emergencyExit(address strategy, address receiver)
        external
        returns (uint256 withdrawn, uint256 loss);

    function checkpoint(address strategy)
        external
        returns (MeridianTypes.StrategyReport memory report);

    function harvest(address strategy, bytes calldata data)
        external
        returns (MeridianTypes.StrategyReport memory report);
}
