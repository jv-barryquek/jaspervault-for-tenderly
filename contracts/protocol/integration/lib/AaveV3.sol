// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "../../../interfaces/external/aave-v3/IPool.sol";
import {IJasperVault} from "../../../interfaces/IJasperVault.sol";

/**
 * @title AaveV3
 * @author JasperVault
 *
 * Collection of helper functions for interacting with AaveV3 integrations.
 * A significant addition to AaveV3 is the ability to supply and repay using permit signatures; it is recommended to read EIP-2612 as background on this.
 */
library AaveV3 {
  /* ============ External ============ */

  /**
   * Get supply (i.e., deposit) calldata from JasperVault
   *
   * Supplies/deposits an `_amountNotional` of underlying asset into the reserve, receiving in return overlying aTokens.
   * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset to deposit
   * @param _amountNotional       The amount to be deposited
   * @param _onBehalfOf           The address that will receive the aTokens, same as msg.sender if the user
   *                              wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
   *                              is a different wallet
   * @param _referralCode         Unique code used to register the integrator originating the operation, for potential rewards.
   *                              0 if the action is executed directly by the user, without any middle-man
   *
   * @return address              Target contract address
   * @return uint256              Call value
   * @return bytes                Deposit calldata
   */
  function getSupplyCallData(
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    address _onBehalfOf,
    uint16 _referralCode
  ) public pure returns (address, uint256, bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "supply(address,uint256,address,uint16)",
      _asset,
      _amountNotional,
      _onBehalfOf,
      _referralCode
    );

    return (address(_lendingPool), 0, callData);
  }

  /**
   * Invoke supply on Pool from JasperVault
   *
   * Supplies/deposits an `_amountNotional` of underlying asset into the reserve, receiving in return overlying aTokens.
   * - E.g. JasperVault deposits 100 USDC and gets in return 100 aUSDC
   * @param _jasperVault             Address of the JasperVault
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset to deposit
   * @param _amountNotional       The amount to be deposited
   */
  function invokeSupply(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional
  ) external {
    (, , bytes memory supplyCallData) = getSupplyCallData(
      _lendingPool,
      _asset,
      _amountNotional,
      address(_jasperVault),
      0
    );

    _jasperVault.invoke(address(_lendingPool), 0, supplyCallData);
  }

  /**
   * Get supplyWithPermit calldata from JasperVault
   *
   * Supplies/deposits an `_amountNotional` of underlying asset into the reserve while skipping a separate tx for approval, receiving in return overlying aTokens.
   * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset to deposit
   * @param _amountNotional       The amount to be deposited
   * @param _onBehalfOf           The address that will receive the aTokens, same as msg.sender if the user
   *                              wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
   *                              is a different wallet
   * @param _referralCode         Unique code used to register the integrator originating the operation, for potential rewards.
   *                              0 if the action is executed directly by the user, without any middle-man
   * @param _deadline             unix timestamp up till which the signature will be valid
   * @param _permitSignature     A ERC-712 signature to be parsed into permit parameters
   *
   * @return address              Target contract address
   * @return uint256              Call value
   * @return bytes                Deposit calldata
   */
  function getSupplyWithPermitCallData(
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    address _onBehalfOf,
    uint16 _referralCode,
    uint256 _deadline,
    bytes memory _permitSignature
  ) public pure returns (address, uint256, bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = _parsePermitSignature(_permitSignature);
    bytes memory callData = abi.encodeWithSignature(
      "supplyWithPermit(address,uint256,address,uint16,uint256,uint8,bytes32,bytes32)",
      _asset,
      _amountNotional,
      _onBehalfOf,
      _referralCode,
      _deadline,
      v,
      r,
      s
    );

    return (address(_lendingPool), 0, callData);
  }

  /**
   * Invoke supplyWithPermit on AaveV3.Pool from JasperVault

   * This function removes the need for the call to _jasperVault.invokeApprove in _deposit function of AaveLeverageModule
   * AaveLeverageModule._deposit is used as part of its `lever` function
   * The Pool is permitted to spend the supplied tokens via the permit parameters.
   * The docs state that the "Permit signature must be signed by msg.sender with spender as Pool address." msg.sender in this case would be the _jasperVault instance.

   * Supplies/deposits an `_amountNotional` of underlying asset into the reserve, receiving in return overlying aTokens.
   * - E.g. JasperVault deposits 100 USDC and gets in return 100 aUSDC
   * @param _jasperVault             Address of the JasperVault
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset to deposit
   * @param _amountNotional       The amount to be deposited
   * @param _signatureExpiryDeadline   A unix-timestamp up till which the _permitSignature is valid
   * @param _permitSignature       A ERC-712 signature to be parsed into permit parameters
   */
  function invokeSupplyWithPermit(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _signatureExpiryDeadline,
    bytes memory _permitSignature
  ) external {
    (, , bytes memory supplyWithPermitCallData) = getSupplyWithPermitCallData(
      _lendingPool,
      _asset,
      _amountNotional,
      address(_jasperVault),
      0,
      _signatureExpiryDeadline,
      _permitSignature
    );

    _jasperVault.invoke(address(_lendingPool), 0, supplyWithPermitCallData);
  }

  /**
   * Get withdraw calldata from JasperVault
   *
   * Withdraws an `_amountNotional` of underlying asset from the reserve, burning the equivalent aTokens owned
   * - E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset to withdraw
   * @param _amountNotional       The underlying amount to be withdrawn
   *                              Note: Passing type(uint256).max will withdraw the entire aToken balance
   * @param _receiver             Address that will receive the underlying, same as msg.sender if the user
   *                              wants to receive it on his own wallet, or a different address if the beneficiary is a
   *                              different wallet
   *
   * @return address              Target contract address
   * @return uint256              Call value
   * @return bytes                Withdraw calldata
   */
  function getWithdrawCalldata(
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    address _receiver
  ) public pure returns (address, uint256, bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "withdraw(address,uint256,address)",
      _asset,
      _amountNotional,
      _receiver
    );

    return (address(_lendingPool), 0, callData);
  }

  /**
   * Invoke withdraw on LendingPool from JasperVault
   *
   * Withdraws an `_amountNotional` of underlying asset from the reserve, burning the equivalent aTokens owned
   * - E.g. JasperVault has 100 aUSDC, and receives 100 USDC, burning the 100 aUSDC
   *
   * @param _jasperVault         Address of the JasperVault
   * @param _lendingPool      Address of the LendingPool contract
   * @param _asset            The address of the underlying asset to withdraw
   * @param _amountNotional   The underlying amount to be withdrawn
   *                          Note: Passing type(uint256).max will withdraw the entire aToken balance
   *
   * @return uint256          The final amount withdrawn
   */
  function invokeWithdraw(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional
  ) external returns (uint256) {
    (, , bytes memory withdrawCalldata) = getWithdrawCalldata(
      _lendingPool,
      _asset,
      _amountNotional,
      address(_jasperVault)
    );

    return
      abi.decode(
        _jasperVault.invoke(address(_lendingPool), 0, withdrawCalldata),
        (uint256)
      );
  }

  /**
   * Get borrow calldata from JasperVault
   *
   * Allows users to borrow a specific `_amountNotional` of the reserve underlying `_asset`, provided that
   * the borrower already deposited enough collateral, or he was given enough allowance by a credit delegator
   * on the corresponding debt token (StableDebtToken or VariableDebtToken)
   *
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset to borrow
   * @param _amountNotional       The amount to be borrowed
   * @param _interestRateMode     The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
   * @param _referralCode         Code used to register the integrator originating the operation, for potential rewards.
   *                              0 if the action is executed directly by the user, without any middle-man
   * @param _onBehalfOf           Address of the user who will receive the debt. Should be the address of the borrower itself
   *                              calling the function if he wants to borrow against his own collateral, or the address of the
   *                              credit delegator if he has been given credit delegation allowance
   *
   * @return address              Target contract address
   * @return uint256              Call value
   * @return bytes                Borrow calldata
   */
  function getBorrowCalldata(
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _interestRateMode,
    uint16 _referralCode,
    address _onBehalfOf
  ) public pure returns (address, uint256, bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "borrow(address,uint256,uint256,uint16,address)",
      _asset,
      _amountNotional,
      _interestRateMode,
      _referralCode,
      _onBehalfOf
    );

    return (address(_lendingPool), 0, callData);
  }

  /**
   * Invoke borrow on LendingPool from JasperVault
   *
   * Allows JasperVault to borrow a specific `_amountNotional` of the reserve underlying `_asset`, provided that
   * the JasperVault already deposited enough collateral, or it was given enough allowance by a credit delegator
   * on the corresponding debt token (StableDebtToken or VariableDebtToken)
   * @param _jasperVault             Address of the JasperVault
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset to borrow
   * @param _amountNotional       The amount to be borrowed
   * @param _interestRateMode     The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
   */
  function invokeBorrow(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _interestRateMode
  ) external {
    (, , bytes memory borrowCalldata) = getBorrowCalldata(
      _lendingPool,
      _asset,
      _amountNotional,
      _interestRateMode,
      0,
      address(_jasperVault)
    );

    _jasperVault.invoke(address(_lendingPool), 0, borrowCalldata);
  }

  /**
   * Get repay calldata from JasperVault
   *
   * Repays a borrowed `_amountNotional` on a specific `_asset` reserve, burning the equivalent debt tokens owned
   * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the borrowed underlying asset previously borrowed
   * @param _amountNotional       The amount to repay
   *                              Note: Passing type(uint256).max will repay the whole debt for `_asset` on the specific `_interestRateMode`
   * @param _interestRateMode     The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * @param _onBehalfOf           Address of the user who will get his debt reduced/removed. Should be the address of the
   *                              user calling the function if he wants to reduce/remove his own debt, or the address of any other
   *                              other borrower whose debt should be removed
   *
   * @return address              Target contract address
   * @return uint256              Call value
   * @return bytes                Repay calldata
   */
  function getRepayCalldata(
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _interestRateMode,
    address _onBehalfOf
  ) public pure returns (address, uint256, bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "repay(address,uint256,uint256,address)",
      _asset,
      _amountNotional,
      _interestRateMode,
      _onBehalfOf
    );

    return (address(_lendingPool), 0, callData);
  }

  /**
   * Invoke repay on LendingPool from JasperVault
   *
   * Repays a borrowed `_amountNotional` on a specific `_asset` reserve, burning the equivalent debt tokens owned
   * - E.g. JasperVault repays 100 USDC, burning 100 variable/stable debt tokens
   * @param _jasperVault             Address of the JasperVault
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the borrowed underlying asset previously borrowed
   * @param _amountNotional       The amount to repay
   *                              Note: Passing type(uint256).max will repay the whole debt for `_asset` on the specific `_interestRateMode`
   * @param _interestRateMode     The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   *
   * @return uint256              The final amount repaid
   */
  function invokeRepay(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _interestRateMode
  ) external returns (uint256) {
    (, , bytes memory repayCalldata) = getRepayCalldata(
      _lendingPool,
      _asset,
      _amountNotional,
      _interestRateMode,
      address(_jasperVault)
    );

    return
      abi.decode(
        _jasperVault.invoke(address(_lendingPool), 0, repayCalldata),
        (uint256)
      );
  }

  /**
   * Get repayWithPermit calldata from JasperVault
   *
   * Repays a borrowed `_amountNotional` on a specific `_asset` reserve, burning the equivalent debt tokens owned
   * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the borrowed underlying asset previously borrowed
   * @param _amountNotional       The amount to repay
   *                              Note: Passing type(uint256).max will repay the whole debt for `_asset` on the specific `_interestRateMode`
   * @param _interestRateMode     The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * @param _onBehalfOf           Address of the user who will get his debt reduced/removed. Should be the address of the
   *                              user calling the function if he wants to reduce/remove his own debt, or the address of any other
   *                              other borrower whose debt should be removed
   * @param _deadline             unix timestamp up till which the signature will be valid
   * The following parameters should be parsed from a signature by the JasperVault instance that owns the tokens to be supplied and AaveV3's Pool as the permitted spender
   * @param _permitSignature     ERC712 Signature to be parsed for permit parameters
   *
   * @return address              Target contract address
   * @return uint256              Call value
   * @return bytes                Repay calldata
   */
  function getRepayWithPermitCallData(
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _interestRateMode,
    address _onBehalfOf,
    uint256 _deadline,
    bytes memory _permitSignature
  ) public pure returns (address, uint256, bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = _parsePermitSignature(_permitSignature);
    bytes memory callData = abi.encodeWithSignature(
      "repayWithPermit(address,uint256,uint256,address,uint256,uint8,bytes32,bytes32)",
      _asset,
      _amountNotional,
      _interestRateMode,
      _onBehalfOf,
      _deadline,
      v,
      r,
      s
    );

    return (address(_lendingPool), 0, callData);
  }

  /**
   * Invoke repayWithPermit on LendingPool from JasperVault
   *
   * Repays a borrowed `_amountNotional` on a specific `_asset` reserve, burning the equivalent debt tokens owned, skipping an approve step by using a ERC712 permit signature
   * - E.g. JasperVault repays 100 USDC, burning 100 variable/stable debt tokens
   * @param _jasperVault             Address of the JasperVault
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the borrowed underlying asset previously borrowed
   * @param _amountNotional       The amount to repay
   *                              Note: Passing type(uint256).max will repay the whole debt for `_asset` on the specific `_interestRateMode`
   * @param _interestRateMode     The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * @param _signatureExpiry      A unix timestamp up till which the _permitSignature is valid
   * @param _permitSignature      A ERC712 signature to be parsed into args for repayWithPermit
   *
   * @return uint256              The final amount repaid
   */
  function invokeRepayWithPermit(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _interestRateMode,
    uint256 _signatureExpiry,
    bytes memory _permitSignature
  ) external returns (uint256) {
    (, , bytes memory repayCalldata) = getRepayWithPermitCallData(
      _lendingPool,
      _asset,
      _amountNotional,
      _interestRateMode,
      address(_jasperVault),
      _signatureExpiry,
      _permitSignature
    );

    return
      abi.decode(
        _jasperVault.invoke(address(_lendingPool), 0, repayCalldata),
        (uint256)
      );
  }

  /**
   * Get repayWithATokens calldata for JasperVault
   *
   * Repays a borrowed `_amountNotional` using aTokens of the underlying debt asset without any approvals
   * - E.g. User repays 100 USDC, burning 100 aUSDC tokens
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the borrowed underlying asset
   * @param _amountNotional       The amount to repay
   *                              Note: Use uint256(-1) to pay without leaving aToken dust
   * @param _interestRateMode     The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   *                              user calling the function if he wants to reduce/remove his own debt, or the address of any other
   *                              other borrower whose debt should be removed
   *
   * @return address              Target contract address
   * @return uint256              Call value
   * @return bytes                Repay calldata
   */

  function getRepayWithATokensCallData(
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _interestRateMode
  ) public pure returns (address, uint256, bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "repayWithATokens(address,uint256,uint256)",
      _asset,
      _amountNotional,
      _interestRateMode
    );

    return (address(_lendingPool), 0, callData);
  }

  function invokeRepayWithATokens(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    uint256 _amountNotional,
    uint256 _interestRateMode
  ) external returns (uint256) {
    (, , bytes memory repayWithATokensCallData) = getRepayWithATokensCallData(
      _lendingPool,
      _asset,
      _amountNotional,
      _interestRateMode
    );

    return
      abi.decode(
        _jasperVault.invoke(address(_lendingPool), 0, repayWithATokensCallData),
        (uint256)
      );
  }

  /**
   * Get setUserUseReserveAsCollateral calldata from JasperVault
   *
   * Allows borrower to enable/disable a specific deposited asset as collateral
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset deposited
   * @param _useAsCollateral      true` if the user wants to use the deposit as collateral, `false` otherwise
   *
   * @return address              Target contract address
   * @return uint256              Call value
   * @return bytes                SetUserUseReserveAsCollateral calldata
   */
  function getSetUserUseReserveAsCollateralCalldata(
    IPool _lendingPool,
    address _asset,
    bool _useAsCollateral
  ) public pure returns (address, uint256, bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "setUserUseReserveAsCollateral(address,bool)",
      _asset,
      _useAsCollateral
    );

    return (address(_lendingPool), 0, callData);
  }

  /**
   * Invoke an asset to be used as collateral on Aave from JasperVault
   *
   * Allows JasperVault to enable/disable a specific deposited asset as collateral
   * @param _jasperVault             Address of the JasperVault
   * @param _lendingPool          Address of the LendingPool contract
   * @param _asset                The address of the underlying asset deposited
   * @param _useAsCollateral      true` if the user wants to use the deposit as collateral, `false` otherwise
   */
  function invokeSetUserUseReserveAsCollateral(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    bool _useAsCollateral
  ) external {
    (, , bytes memory callData) = getSetUserUseReserveAsCollateralCalldata(
      _lendingPool,
      _asset,
      _useAsCollateral
    );

    _jasperVault.invoke(address(_lendingPool), 0, callData);
  }

  /**
   * Get swapBorrowRate calldata from JasperVault
   *
   * Allows a borrower to toggle his debt between stable and variable mode
   * @param _lendingPool      Address of the LendingPool contract
   * @param _asset            The address of the underlying asset borrowed
   * @param _rateMode         The rate mode that the user wants to swap to
   *
   * @return address          Target contract address
   * @return uint256          Call value
   * @return bytes            SwapBorrowRate calldata
   */
  function getSwapBorrowRateModeCalldata(
    IPool _lendingPool,
    address _asset,
    uint256 _rateMode
  ) public pure returns (address, uint256, bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "swapBorrowRateMode(address,uint256)",
      _asset,
      _rateMode
    );

    return (address(_lendingPool), 0, callData);
  }

  /**
   * Invoke to swap borrow rate of JasperVault
   *
   * Allows JasperVault to toggle it's debt between stable and variable mode
   * @param _jasperVault         Address of the JasperVault
   * @param _lendingPool      Address of the LendingPool contract
   * @param _asset            The address of the underlying asset borrowed
   * @param _rateMode         The rate mode that the user wants to swap to
   */
  function invokeSwapBorrowRateMode(
    IJasperVault _jasperVault,
    IPool _lendingPool,
    address _asset,
    uint256 _rateMode
  ) external {
    (, , bytes memory callData) = getSwapBorrowRateModeCalldata(
      _lendingPool,
      _asset,
      _rateMode
    );

    _jasperVault.invoke(address(_lendingPool), 0, callData);
  }

  function _parsePermitSignature(
    bytes memory _signature
  ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
    // * note: code for parsing signature from: https://ethereum.stackexchange.com/questions/26434/whats-the-best-way-to-transform-bytes-of-a-signature-into-v-r-s-in-solidity
    assembly {
      r := mload(add(_signature, 32))
      s := mload(add(_signature, 64))
      v := and(mload(add(_signature, 65)), 255)
    }
    if (v < 27) v += 27;
  }
}
