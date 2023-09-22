// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";
// ! NOTE: Probably going to delete this extension and streamline interaction with Spark into the LeverageExtensionV2 + AaveLeverageModuleV2. Pending discussion.

import {IJasperVault} from "../../interfaces/IJasperVault.sol";
import {IWETH} from "@setprotocol/set-protocol-v2/contracts/interfaces/external/IWETH.sol";
import {ISparkStakingModule} from "../../interfaces/ISparkStakingModule.sol";
import {IPool} from "../../interfaces/external/spark/IPool.sol";
import {IPoolAddressesProvider} from "../../interfaces/external/spark/IPoolAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseGlobalExtension} from "../lib/BaseGlobalExtension.sol";
import {IDelegatedManager} from "../interfaces/IDelegatedManager.sol";
import {IManagerCore} from "../interfaces/IManagerCore.sol";

import {ISignalSuscriptionModule} from "../../interfaces/ISignalSuscriptionModule.sol";

/**
 * @title SparkExtension
 * @author JasperVault
 *
 * ! NOTE: Probably going to delete this extension and streamline interaction with Spark into the LeverageExtensionV2 + AaveLeverageModuleV2. Pending discussion.
 * @notice Extension for invoking repay, borrow, lever, and delever on Spark's spToken Pool, which is a fork of AaveV3's aToken Pool
 * @dev If you wish to invoke supply* or withdraw* related functions, use the WrapExtension with the SparkWrapV2Adapter
 */
/* is BaseGlobalExtension */ contract SparkExtension {
    // /* ============ Events ============ */
    // event SparkExtensionInitialized(
    //     address indexed _jasperVault,
    //     address indexed _delegatedManager
    // );
    // event InvokeFail(
    //     address indexed _manage,
    //     address _leverageModule,
    //     string _reason,
    //     bytes _callData
    // );
    // /* ============ State Variables ============ */
    // // Instance of SparkStakingModule
    // ISparkStakingModule public immutable sparkStakingModule;
    // ISignalSuscriptionModule public immutable signalSuscriptionModule;
    // IPool public immutable sparkStakingPool;
    // IERC20 daiTokenAddress;
    // /* ============ Constructor ============ */
    // /**
    //  * Instantiate with ManagerCore address and SparkStakingModule address.
    //  *
    //  * @param _managerCore              Address of ManagerCore contract
    //  * @param _sparkStakingModule               Address of SparkStakingModule contract
    //  * @param _lendingPoolAddressesProvider    Address of Spark PoolAddressesProvider contract
    //  */
    // constructor(
    //     IManagerCore _managerCore,
    //     ISparkStakingModule _sparkStakingModule,
    //     IPoolAddressesProvider _lendingPoolAddressesProvider,
    //     ISignalSuscriptionModule _signalSuscriptionModule,
    //     IERC20 _daiTokenAddress
    // ) public BaseGlobalExtension(_managerCore) {
    //     sparkStakingModule = _sparkStakingModule;
    //     signalSuscriptionModule = _signalSuscriptionModule;
    //     sparkStakingPool = IPool(_lendingPoolAddressesProvider.getPool());
    //     daiTokenAddress = _daiTokenAddress;
    // }
    // /* ============ External Functions ============ */
    // /**
    //  * ONLY OWNER: Initializes SparkStakingModule on the JasperVault associated with the DelegatedManager.
    //  *
    //  * @param _delegatedManager     Instance of the DelegatedManager to initialize the SparkStakingModule for
    //  */
    // function initializeModule(
    //     IDelegatedManager _delegatedManager
    // ) external onlyOwnerAndValidManager(_delegatedManager) {
    //     _initializeModule(_delegatedManager.jasperVault(), _delegatedManager);
    // }
    // /**
    //  * ONLY OWNER: Initializes SparkExtension to the DelegatedManager.
    //  *
    //  * @param _delegatedManager     Instance of the DelegatedManager to initialize
    //  */
    // function initializeExtension(
    //     IDelegatedManager _delegatedManager
    // ) external onlyOwnerAndValidManager(_delegatedManager) {
    //     IJasperVault jasperVault = _delegatedManager.jasperVault();
    //     _initializeExtension(jasperVault, _delegatedManager);
    //     emit SparkExtensionInitialized(
    //         address(jasperVault),
    //         address(_delegatedManager)
    //     );
    // }
    // /**
    //  * ONLY OWNER: Initializes SparkExtension to the DelegatedManager and SparkStakingModule to the JasperVault
    //  *
    //  * @param _delegatedManager     Instance of the DelegatedManager to initialize
    //  */
    // function initializeModuleAndExtension(
    //     IDelegatedManager _delegatedManager
    // ) external onlyOwnerAndValidManager(_delegatedManager) {
    //     IJasperVault jasperVault = _delegatedManager.jasperVault();
    //     _initializeExtension(jasperVault, _delegatedManager);
    //     _initializeModule(jasperVault, _delegatedManager);
    //     emit SparkExtensionInitialized(
    //         address(jasperVault),
    //         address(_delegatedManager)
    //     );
    // }
    // /**
    //  * ONLY MANAGER: Remove an existing JasperVault and DelegatedManager tracked by the WrapExtension
    //  */
    // function removeExtension() external override {
    //     IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
    //     IJasperVault jasperVault = delegatedManager.jasperVault();
    //     _removeExtension(jasperVault, delegatedManager);
    // }
    // function supplyToSpPool(
    //     IJasperVault _jasperVault,
    //     IERC20 _supplyAsset,
    //     uint256 _supplyAssetQuantity
    // )
    //     external
    //     onlyReset(_jasperVault)
    //     onlyOperator(_jasperVault)
    //     onlyAllowedAsset(_jasperVault, address(_supplyAsset))
    // {
    //     bytes memory callData = abi.encodeWithSelector(
    //         ISparkStakingModule.supplyToSpPool.selector,
    //         _jasperVault,
    //         sparkStakingPool,
    //         _supplyAsset,
    //         _supplyAssetQuantity
    //     );
    //     _invokeManager(
    //         _manager(_jasperVault),
    //         address(sparkStakingModule),
    //         callData
    //     );
    // }
    // function depositDAIForSDAI(
    //     IJasperVault _jasperVault,
    //     uint256 _depositQuantity
    // )
    //     external
    //     onlyReset(_jasperVault)
    //     onlyOperator(_jasperVault)
    //     onlyAllowedAsset(_jasperVault, address(daiTokenAddress))
    // {
    //     bytes memory callData = abi.encodeWithSelector(
    //         ISparkStakingModule.depositDAIForSDAI.selector,
    //         _jasperVault,
    //         daiTokenAddress,
    //         _depositQuantity
    //     );
    //     _invokeManager(
    //         _manager(_jasperVault),
    //         address(sparkStakingModule),
    //         callData
    //     );
    // }
    // function withdrawFromSpPool(
    //     IJasperVault _jasperVault,
    //     uint256 _redeemQuantityUnits
    // )
    //     external
    //     onlyReset(_jasperVault)
    //     onlyOperator(_jasperVault)
    //     onlyAllowedAsset(_jasperVault, address(daiTokenAddress))
    // {
    //     bytes memory callData = abi.encodeWithSelector(
    //         ISparkStakingModule.withdrawFromSpPool.selector,
    //         _jasperVault,
    //         _redeemQuantityUnits
    //     );
    //     _invokeManager(
    //         _manager(_jasperVault),
    //         address(sparkStakingModule),
    //         callData
    //     );
    // }
    // function withdrawDAIDeposit(
    //     IJasperVault _jasperVault,
    //     uint256 _redeemQuantityUnits
    // )
    //     external
    //     onlyReset(_jasperVault)
    //     onlyOperator(_jasperVault)
    //     onlyAllowedAsset(_jasperVault, address(daiTokenAddress))
    // {
    //     bytes memory callData = abi.encodeWithSelector(
    //         ISparkStakingModule.withdrawDAIDeposit.selector,
    //         _jasperVault,
    //         _redeemQuantityUnits
    //     );
    //     _invokeManager(
    //         _manager(_jasperVault),
    //         address(sparkStakingModule),
    //         callData
    //     );
    // }
    // function supplyOrWithdrawWithFollowers(
    //     IJasperVault _jasperVault,
    //     IERC20 _asset,
    //     uint256 _assetNotionalQuantity,
    //     bool _invokeSupply
    // )
    //     external
    //     onlyReset(_jasperVault)
    //     onlyOperator(_jasperVault)
    //     onlyAllowedAsset(_jasperVault, address(_asset))
    // {
    //     bytes4 funcSelector = _invokeSupply
    //         ? ISparkStakingModule.supplyToSpPool.selector
    //         : ISparkStakingModule.withdrawFromSpPool.selector;
    //     bytes memory callData = abi.encodeWithSelector(
    //         funcSelector,
    //         _jasperVault,
    //         sparkStakingPool,
    //         _asset,
    //         _assetNotionalQuantity
    //     );
    //     _invokeManager(
    //         _manager(_jasperVault),
    //         address(sparkStakingModule),
    //         callData
    //     );
    //     // todo: fix casing of get_followers
    //     address[] memory followers = signalSuscriptionModule.get_followers(
    //         address(_jasperVault)
    //     );
    //     for (uint256 i = 0; i < followers.length; i++) {
    //         callData = abi.encodeWithSelector(
    //             funcSelector,
    //             IJasperVault(followers[i]),
    //             _asset,
    //             _assetNotionalQuantity
    //         );
    //         _execute(
    //             _manager(IJasperVault(followers[i])),
    //             address(sparkStakingModule),
    //             callData
    //         );
    //     }
    //     callData = abi.encodeWithSelector(
    //         // todo: fix spelling of method here
    //         ISignalSuscriptionModule.exectueFollowStart.selector,
    //         address(_jasperVault)
    //     );
    //     _invokeManager(
    //         _manager(_jasperVault),
    //         address(signalSuscriptionModule),
    //         callData
    //     );
    // }
    // /* ============ Internal Functions ============ */
    // function _execute(
    //     IDelegatedManager manager,
    //     address module,
    //     bytes memory callData
    // ) internal {
    //     try manager.interactManager(module, callData) {} catch Error(
    //         string memory reason
    //     ) {
    //         emit InvokeFail(address(manager), module, reason, callData);
    //     }
    // }
    // /**
    //  * Internal function to initialize SparkStakingModule on the JasperVault associated with the DelegatedManager.
    //  *
    //  * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
    //  * @param _delegatedManager     Instance of the DelegatedManager to initialize the SparkStakingModule for
    //  */
    // function _initializeModule(
    //     IJasperVault _jasperVault,
    //     IDelegatedManager _delegatedManager
    // ) internal {
    //     bytes memory callData = abi.encodeWithSelector(
    //         ISparkStakingModule.initialize.selector,
    //         _jasperVault
    //     );
    //     _invokeManager(
    //         _delegatedManager,
    //         address(sparkStakingModule),
    //         callData
    //     );
    // }
}
