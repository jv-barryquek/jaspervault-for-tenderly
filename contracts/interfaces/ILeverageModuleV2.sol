// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.10;
import {IJasperVault} from "./IJasperVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface for LeverageModule including additional functions introduced in AaveV3
 */
interface ILeverageModuleV2 {
  function initialize(IJasperVault _jasperVault) external;

  function borrow(
    IJasperVault _jasperVault,
    IERC20 _borrowAsset,
    uint256 _borrowQuantityUnits
  ) external;

  function repay(
    IJasperVault _jasperVault,
    IERC20 _repayAsset,
    uint256 _redeemQuantityUnits,
    bool _isAllRepay
  ) external;

  function repayWithPermit(
    IJasperVault _jasperVault,
    IERC20 _repayAsset,
    uint256 _redeemQuantityUnits,
    bool _isAllRepay,
    uint256 _signatureExpiry,
    bytes memory _permitSignature
  ) external;

  function repayWithATokens(
    IJasperVault _jasperVault,
    IERC20 _repayAsset,
    uint256 _redeemQuantityUnits,
    bool _isAllRepay
  ) external; // this function is specific to AaveLeverageModuleV2, but we include it in the general interface to avoid complicating repayment logic with code branching

  function lever(
    IJasperVault _jasperVault,
    IERC20 _borrowAsset,
    IERC20 _collateralAsset,
    uint256 _borrowQuantityUnits,
    uint256 _minReceiveQuantityUnits,
    string memory _tradeAdapterName,
    bytes memory _tradeData
  ) external;

  function leverWithPermit(
    IJasperVault _jasperVault,
    IERC20 _borrowAsset,
    IERC20 _collateralAsset,
    uint256 _borrowQuantityUnits,
    uint256 _minReceiveQuantityUnits,
    string memory _tradeAdapterName,
    bytes memory _tradeData,
    uint256 _signatureExpiry,
    bytes memory _permitSignature
  ) external;

  function delever(
    IJasperVault _jasperVault,
    IERC20 _collateralAsset,
    IERC20 _repayAsset,
    uint256 _redeemQuantityUnits,
    uint256 _minRepayQuantityUnits,
    string memory _tradeAdapterName,
    bytes memory _tradeData
  ) external;

  // todo: do deleverWithPermit after initial testing is done

  function deleverToZeroBorrowBalance(
    IJasperVault _jasperVault,
    IERC20 _collateralAsset,
    IERC20 _repayAsset,
    uint256 _redeemQuantityUnits,
    string memory _tradeAdapterName,
    bytes memory _tradeData
  ) external;
}
