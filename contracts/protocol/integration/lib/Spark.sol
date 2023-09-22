// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";
// ! NOTE: Likely to delete this  and streamline interaction with Spark into LeverageExtension

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "../../../interfaces/external/spark/IPool.sol";
import {ISavingsDai} from "../../../interfaces/external/spark/ISavingsDai.sol";
import {IJasperVault} from "../../../interfaces/IJasperVault.sol";

/**
 * @title Spark
 * @author JasperVault
 *
 * @notice Collection of helper functions for interacting with Spark protocol integrations.
 */
library Spark {
    /* ============ External ============ */

    /**
     * Get supply calldata for calling Spark's Pool contract from JasperVault
     *
     * @param _asset                The address of the underlying asset to deposit
     * @param _amountNotional       The amount to be deposited
     * @param _onBehalfOf           The address that will receive the aTokens, same as msg.sender if the user
     *                              wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *                              is a different wallet
     * @param _referralCode         Unique code used to register the integrator originating the operation, for potential rewards.
     *                              0 if the action is executed directly by the user, without any middle-man
     *
     * @return bytes                Deposit calldata
     */
    function getSupplyCallData(
        address _asset,
        uint256 _amountNotional,
        address _onBehalfOf,
        uint16 _referralCode
    ) public pure returns (bytes memory) {
        bytes memory callData = abi.encodeWithSignature(
            "supply(address,uint256,address,uint16)",
            _asset,
            _amountNotional,
            _onBehalfOf,
            _referralCode
        );

        return callData;
    }

    /**
     * Invoke supply on Spark Pool from JasperVault
     *
     * Supplies/deposits an `_amountNotional` of underlying asset into the reserve, receiving in return overlying spTokens.
     * - E.g. JasperVault deposits 100 USDC and gets in return 100 spUSDC
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
        bytes memory supplyCallData = getSupplyCallData(
            _asset,
            _amountNotional,
            address(_jasperVault),
            0
        );

        _jasperVault.invoke(address(_lendingPool), 0, supplyCallData);
    }

    /**
     * Get deposit calldata from JasperVault for depositing into sDAI token contract
     *
     * Deposits an `_amountNotional` of DAI into the sDAI contract, receiving in return a corresponding amount of sDAI.
     * - E.g. User deposits 100 DAI and gets in return 100 sDAI
     * @param _amountNotional       The amount to be deposited
     * @param _jasperVault                The JasperVault that is depositing the DAI
     *
     * @return bytes                Deposit calldata
     */
    function getDepositCallData(
        uint256 _amountNotional,
        address _jasperVault
    ) public pure returns (bytes memory) {
        bytes memory callData = abi.encodeWithSignature(
            "deposit(uint256,address)",
            _amountNotional,
            _jasperVault
        );

        return callData;
    }

    /**
     * Invoke deposit on sDAI contract from JasperVault
     *
     * Deposits an `_amountNotional` of DAI into the reserve, receiving in return overlying sDAI.
     * - E.g. JasperVault deposits 100 DAI and gets in return 100 sDAI
     * @param _jasperVault             Address of the JasperVault
     * @param _sDAIContract          Address of the sDAI contract
     * @param _amountNotional       The amount to be deposited
     */
    function invokeDeposit(
        IJasperVault _jasperVault,
        ISavingsDai _sDAIContract,
        uint256 _amountNotional
    ) external {
        bytes memory depositCallData = getDepositCallData(
            _amountNotional,
            address(_jasperVault)
        );

        _jasperVault.invoke(address(_sDAIContract), 0, depositCallData);
    }

    /**
     * Get withdraw calldata from JasperVault
     *
     * Withdraws an `_amountNotional` of underlying asset from the reserve, burning the equivalent aTokens owned
     * - E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param _asset                The address of the underlying asset to withdraw
     * @param _amountNotional       The underlying amount to be withdrawn
     *                              Note: Passing type(uint256).max will withdraw the entire aToken balance
     * @param _receiver             Address that will receive the underlying, same as msg.sender if the user
     *                              wants to receive it on his own wallet, or a different address if the beneficiary is a
     *                              different wallet
     *
     * @return bytes                Withdraw calldata
     */
    function getWithdrawFromSpPoolCallData(
        address _asset,
        uint256 _amountNotional,
        address _receiver
    ) public pure returns (bytes memory) {
        bytes memory callData = abi.encodeWithSignature(
            "withdraw(address,uint256,address)",
            _asset,
            _amountNotional,
            _receiver
        );

        return callData;
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
    function invokeWithdrawFromSpPool(
        IJasperVault _jasperVault,
        IPool _lendingPool,
        address _asset,
        uint256 _amountNotional
    ) external returns (uint256) {
        bytes memory withdrawCallData = getWithdrawFromSpPoolCallData(
            _asset,
            _amountNotional,
            address(_jasperVault)
        );

        return
            abi.decode(
                _jasperVault.invoke(address(_lendingPool), 0, withdrawCallData),
                (uint256)
            );
    }

    /**
     * @notice Get calldata for invoking withdraw on the sDAI token contract
     */
    function getWithdrawFromSDaiCallData(
        uint256 _amountNotional,
        address _receiver
    ) public pure returns (bytes memory) {
        bytes memory callData = abi.encodeWithSignature(
            "withdraw(uint256,address,address)",
            _amountNotional,
            _receiver, // receiver parameter in sDAI.withdraw
            _receiver // owner parameter in sDAI.withdraw
            // in our implementation, both receiver and withdrawer are the JasperVault that deposited DAI
        );

        return callData;
    }

    /**
     * @notice Invoke withdraw on the sDAI token contract using a JasperVault
     */
    function invokeWithdrawFromSDaiContract(
        IJasperVault _jasperVault,
        ISavingsDai _sDAIContract,
        uint256 _amountNotional
    ) external returns (uint256) {
        bytes memory withdrawCallData = getWithdrawFromSDaiCallData(
            _amountNotional,
            address(_jasperVault)
        );

        return
            abi.decode(
                _jasperVault.invoke(
                    address(_sDAIContract),
                    0,
                    withdrawCallData
                ),
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
     * Invoke an asset to be used as collateral on Spark from JasperVault
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
}
