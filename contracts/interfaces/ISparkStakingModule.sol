// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.10;
import {IJasperVault} from "./IJasperVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "./external/spark/IPool.sol";

/**
 * @dev Interface for SparkStakingModule-- functionality is limited to just supply and withdraw for now to do Proof of Concept
 */
interface ISparkStakingModule {
    function initialize(IJasperVault _jasperVault) external;

    function supplyToSpPool(
        IJasperVault _jasperVault,
        IPool _lendingPool,
        IERC20 _asset,
        uint256 _notionalQuantity
    ) external;

    function depositDAIForSDAI(
        IJasperVault _jasperVault,
        uint256 _notionalQuantiy
    ) external;

    function withdrawFromSpPool(
        IJasperVault _jasperVault,
        IPool _lendingPool,
        IERC20 _asset,
        uint256 _notionalQuantity
    ) external;

    function withdrawDAIDeposit(
        IJasperVault _jasperVault,
        uint256 _notionalQuantity
    ) external;
}
