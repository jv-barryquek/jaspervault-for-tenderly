// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";
// ! NOTE: this module is likely to be deleted if we streamline interacting with Spark's spPool into the AaveLeverageModuleV2 instead

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Spark} from "../../integration/lib/Spark.sol";
import {ISpToken} from "../../../interfaces/external/spark/ISpToken.sol";
import {IController} from "../../../interfaces/IController.sol";
import {IDebtIssuanceModule} from "../../../interfaces/IDebtIssuanceModule.sol";
import {IExchangeAdapter} from "../../../interfaces/IExchangeAdapter.sol";
import {IPool} from "../../../interfaces/external/spark/IPool.sol";
import {ISavingsDai} from "../../../interfaces/external/spark/ISavingsDai.sol";
import {IPoolAddressesProvider} from "../../../interfaces/external/spark/IPoolAddressesProvider.sol";
import {IModuleIssuanceHook} from "../../../interfaces/IModuleIssuanceHook.sol";
import {IPoolDataProvider} from "../../../interfaces/external/spark/IPoolDataProvider.sol";
import {IJasperVault} from "../../../interfaces/IJasperVault.sol";
import {IVariableDebtToken} from "../../../interfaces/external/spark/IVariableDebtToken.sol";
import {ModuleBase} from "../../lib/ModuleBase.sol";

/**
 * @title SparkStakingModule
 * @author JasperVault
 * ! NOTE: this module is likely to be deleted if we streamline interacting with Spark's spPool into the AaveLeverageModuleV2 instead
 */
contract SparkStakingModule
    /* is ModuleBase */
    /* ReentrancyGuard */
    /* Ownable */
    /* IModuleIssuanceHook */
{
    // using Spark for IJasperVault;

    // /* ============ Structs ============ */

    // struct EnabledAssets {
    //     address[] collateralAssets; // Array of enabled underlying collateral assets for a JasperVault
    //     address[] borrowAssets; // Array of enabled underlying borrow assets for a JasperVault
    // }

    // struct ReserveTokens {
    //     ISpToken spToken; // Reserve's SpToken instance
    //     IVariableDebtToken variableDebtToken; // Reserve's variable debt token instance
    // }

    // /* ============ Events ============ */
    // /// @dev Emitted when `supply` function is successfully invoked
    // /// @param _jasperVault  JasperVault from which the given asset was supplied from
    // /// @param _asset The asset which the JasperVault supplied to the Spark Pool
    // /// @param _notionalQuantity The amount of asset supplied to the Spark Pool
    // event AssetSuppliedToSparkPool(
    //     IJasperVault _jasperVault,
    //     IERC20 _asset,
    //     uint256 _notionalQuantity
    // );

    // /// @dev Emitted when `withdraw` function is successfully invoked
    // /// @param _jasperVault  JasperVault from which the given asset was supplied from, and is now receiving back
    // /// @param _asset The underlying asset which the JasperVault supplied to the Spark Pool, and has now been withdrawn
    // /// @param _notionalQuantity The amount of asset withdrawn from the Spark Pool
    // event AssetWithdrawnFromSparkPool(
    //     IJasperVault _jasperVault,
    //     IERC20 _asset,
    //     uint256 _notionalQuantity
    // );

    // /// @dev Emitted when `deposit` function of sDAI contract is succcessfully invoked
    // event DAIDepositedInSDAIContract(
    //     IJasperVault _depositor,
    //     uint256 _notionalQuantity
    // );

    // /// @dev Emitted when `withdraw` function of sDAI contract is succcessfully invoked
    // event DAIWithdrawnFromSDAIContract(
    //     IJasperVault _withdrawer,
    //     uint256 _notionalQuantity
    // );

    // /**
    //  * @dev Emitted when `underlyingToReserveTokensMappings` is updated
    //  * @param _underlying           Address of the underlying asset
    //  * @param _spToken               Updated spark reserve spToken
    //  * @param _variableDebtToken    Updated spark reserve variable debt token
    //  */
    // event ReserveTokensUpdated(
    //     IERC20 indexed _underlying,
    //     ISpToken _spToken,
    //     IVariableDebtToken indexed _variableDebtToken
    // );

    // /**
    //  * @dev Emitted on updateAllowedSetToken()
    //  * @param _jasperVault JasperVault being whose allowance to initialize this module is being updated
    //  * @param _added    true if added false if removed
    //  */
    // event SetTokenStatusUpdated(
    //     IJasperVault indexed _jasperVault,
    //     bool indexed _added
    // );

    // /**
    //  * @dev Emitted on updateAnySetAllowed()
    //  * @param _anySetAllowed    true if any set is allowed to initialize this module, false otherwise
    //  */
    // event AnySetAllowedUpdated(bool indexed _anySetAllowed);

    // /* ============ Constants ============ */

    // // This module only supports borrowing in variable rate mode from Spark which is represented by 2
    // uint256 internal constant BORROW_RATE_MODE = 2;

    // // String identifying the DebtIssuanceModule in the IntegrationRegistry. Note: Governance must add DefaultIssuanceModule as
    // // the string as the integration name
    // string internal constant DEFAULT_ISSUANCE_MODULE_NAME =
    //     "DefaultIssuanceModule";

    // // 0 index stores protocol fee % on the controller, charged in the _executeTrade function
    // uint256 internal constant PROTOCOL_TRADE_FEE_INDEX = 0;

    // /* ============ State Variables ============ */

    // // Mapping to efficiently fetch reserve token addresses. Tracking Spark reserve token addresses and updating them
    // // upon requirement is more efficient than fetching them each time from Spark.
    // // Note: For an underlying asset to be enabled as collateral/borrow asset on JasperVault, it must be added to this mapping first.
    // mapping(IERC20 => ReserveTokens) public underlyingToReserveTokens;

    // // Used to fetch reserves and user data from Spark
    // IPoolDataProvider public immutable protocolDataProvider;

    // // Used to fetch lendingPool address. This contract is immutable and its address will never change.
    // IPoolAddressesProvider public immutable lendingPoolAddressesProvider;

    // // Internal mapping of enabled collateral and borrow tokens for syncing positions
    // mapping(IJasperVault => EnabledAssets) internal enabledAssets;

    // // sDAI contract used for depositing and withdrawing DAI
    // ISavingsDai public sDAIContract;

    // /* ============ Constructor ============ */

    // /**
    //  * @dev Instantiate addresses. Underlying to reserve tokens mapping is created.
    //  * @param _controller                       Address of controller contract
    //  * @param _lendingPoolAddressesProvider     Address of Spark LendingPoolAddressProvider
    //  */
    // constructor(
    //     IController _controller,
    //     IPoolAddressesProvider _lendingPoolAddressesProvider,
    //     ISavingsDai _sDAIContract
    // ) public ModuleBase(_controller) {
    //     lendingPoolAddressesProvider = _lendingPoolAddressesProvider;
    //     sDAIContract = _sDAIContract;
    //     IPoolDataProvider _protocolDataProvider = IPoolDataProvider(
    //         _lendingPoolAddressesProvider.getPoolDataProvider()
    //     );
    //     protocolDataProvider = _protocolDataProvider;

    //     IPoolDataProvider.TokenData[]
    //         memory reserveTokens = _protocolDataProvider.getAllReservesTokens();
    //     for (uint256 i = 0; i < reserveTokens.length; i++) {
    //         (
    //             address aToken,
    //             ,
    //             address variableDebtToken
    //         ) = _protocolDataProvider.getReserveTokensAddresses(
    //                 reserveTokens[i].tokenAddress
    //             );
    //         underlyingToReserveTokens[
    //             IERC20(reserveTokens[i].tokenAddress)
    //         ] = ReserveTokens(
    //             ISpToken(aToken),
    //             IVariableDebtToken(variableDebtToken)
    //         );
    //     }
    // }

    // /* ============ External Functions ============ */
    // /**
    //  * @dev Invoke supply from JasperVault using Spark library. Mints aTokens for JasperVault.
    //  */
    // function supplyToSpPool(
    //     IJasperVault _jasperVault,
    //     IPool _lendingPool,
    //     IERC20 _asset,
    //     uint256 _notionalQuantity
    // ) external nonReentrant onlyManagerAndValidSet(_jasperVault) {
    //     _updateUseReserveAsCollateral(_jasperVault, _asset, true);
    //     _jasperVault.invokeApprove(
    //         address(_asset),
    //         address(_lendingPool),
    //         _notionalQuantity
    //     );
    //     _jasperVault.invokeSupply(
    //         _lendingPool,
    //         address(_asset),
    //         _notionalQuantity
    //     );
    //     emit AssetSuppliedToSparkPool(_jasperVault, _asset, _notionalQuantity);
    // }

    // /**
    //  * @dev Invoke deposit from JasperVault on the sDAI token contract. Mints sDAI for JasperVault.
    //  */
    // function depositDAIForSDAI(
    //     IJasperVault _jasperVault,
    //     IERC20 _daiToken,
    //     uint256 _notionalQuantity
    // ) external nonReentrant onlyManagerAndValidSet(_jasperVault) {
    //     _updateUseReserveAsCollateral(_jasperVault, _daiToken, true);
    //     _jasperVault.invokeApprove(
    //         address(_daiToken),
    //         address(sDAIContract),
    //         _notionalQuantity
    //     );
    //     _jasperVault.invokeDeposit(sDAIContract, _notionalQuantity);
    //     emit DAIDepositedInSDAIContract(_jasperVault, _notionalQuantity);
    // }

    // /**
    //  * @dev Invoke withdraw from JasperVault using Spark library. Burns aTokens and returns underlying to JasperVault.
    //  */
    // function withdrawFromSpPool(
    //     IJasperVault _jasperVault,
    //     IPool _lendingPool,
    //     IERC20 _asset,
    //     uint256 _notionalQuantity
    // ) external nonReentrant onlyManagerAndValidSet(_jasperVault) {
    //     uint256 finalWithDrawn = _jasperVault.invokeWithdrawFromSpPool(
    //         _lendingPool,
    //         address(_asset),
    //         _notionalQuantity
    //     );
    //     require(finalWithDrawn == _notionalQuantity, "withdraw  fail");
    //     emit AssetWithdrawnFromSparkPool(
    //         _jasperVault,
    //         _asset,
    //         _notionalQuantity
    //     );
    // }

    // /**
    //  * @dev Invoke withdrawFromSDaiContract from JasperVault using Spark library.
    //  */
    // function withdrawDAIDeposit(
    //     IJasperVault _jasperVault,
    //     uint256 _notionalQuantity
    // ) external nonReentrant onlyManagerAndValidSet(_jasperVault) {
    //     uint256 finalWithDrawn = _jasperVault.invokeWithdrawFromSDaiContract(
    //         sDAIContract,
    //         _notionalQuantity
    //     );
    //     require(finalWithDrawn == _notionalQuantity, "withdraw  fail");
    //     emit DAIWithdrawnFromSDAIContract(_jasperVault, _notionalQuantity);
    // }

    // /**
    //  * @dev CALLABLE BY ANYBODY: Sync Set positions with ALL enabled Spark collateral and borrow positions.
    //  * For collateral assets, update aToken default position. For borrow assets, update external borrow position.
    //  * - Collateral assets may come out of sync when interest is accrued or a position is liquidated
    //  * - Borrow assets may come out of sync when interest is accrued or position is liquidated and borrow is repaid
    //  * Note: In Spark, both collateral and borrow interest is accrued in each block by increasing the balance of
    //  * aTokens and debtTokens for each user, and 1 aToken = 1 variableDebtToken = 1 underlying.
    //  * @param _jasperVault               Instance of the JasperVault
    //  */
    // function sync(
    //     IJasperVault _jasperVault
    // ) public nonReentrant onlyValidAndInitializedSet(_jasperVault) {
    //     uint256 setTotalSupply = _jasperVault.totalSupply();

    //     // Only sync positions when Set supply is not 0. Without this check, if sync is called by someone before the
    //     // first issuance, then editDefaultPosition would remove the default positions from the JasperVault
    //     if (setTotalSupply > 0) {
    //         address[] memory collateralAssets = enabledAssets[_jasperVault]
    //             .collateralAssets;
    //         for (uint256 i = 0; i < collateralAssets.length; i++) {
    //             ISpToken spToken = underlyingToReserveTokens[
    //                 IERC20(collateralAssets[i])
    //             ].spToken;

    //             uint256 previousPositionUnit = _jasperVault
    //                 .getDefaultPositionRealUnit(address(spToken))
    //                 .toUint256();
    //             uint256 newPositionUnit = _getCollateralPosition(
    //                 _jasperVault,
    //                 spToken,
    //                 setTotalSupply
    //             );

    //             // Note: Accounts for if position does not exist on JasperVault but is tracked in enabledAssets
    //             if (previousPositionUnit != newPositionUnit) {
    //                 _updateCollateralPosition(
    //                     _jasperVault,
    //                     spToken,
    //                     newPositionUnit
    //                 );
    //             }
    //         }

    //         address[] memory borrowAssets = enabledAssets[_jasperVault]
    //             .borrowAssets;
    //         for (uint256 i = 0; i < borrowAssets.length; i++) {
    //             IERC20 borrowAsset = IERC20(borrowAssets[i]);

    //             int256 previousPositionUnit = _jasperVault
    //                 .getExternalPositionRealUnit(
    //                     address(borrowAsset),
    //                     address(this)
    //                 );
    //             int256 newPositionUnit = _getBorrowPosition(
    //                 _jasperVault,
    //                 borrowAsset,
    //                 setTotalSupply
    //             );

    //             // Note: Accounts for if position does not exist on JasperVault but is tracked in enabledAssets
    //             if (newPositionUnit != previousPositionUnit) {
    //                 _updateBorrowPosition(
    //                     _jasperVault,
    //                     borrowAsset,
    //                     newPositionUnit
    //                 );
    //             }
    //         }
    //     }
    // }

    // /**
    //  * @dev MANAGER ONLY: Initializes this module to the JasperVault. Either the JasperVault needs to be on the allowed list
    //  * or anySetAllowed needs to be true. Only callable by the JasperVault's manager.
    //  * Note: Managers can enable collateral and borrow assets that don't exist as positions on the JasperVault
    //  * @param _jasperVault             Instance of the JasperVault to initialize
    //  */
    // function initialize(
    //     IJasperVault _jasperVault
    // )
    //     external
    //     onlySetManager(_jasperVault, msg.sender)
    //     onlyValidAndPendingSet(_jasperVault)
    // {
    //     // Initialize module before trying register
    //     _jasperVault.initializeModule();

    //     // Get debt issuance module registered to this module and require that it is initialized
    //     require(
    //         _jasperVault.isInitializedModule(
    //             getAndValidateAdapter(DEFAULT_ISSUANCE_MODULE_NAME)
    //         ),
    //         "Issuance not initialized"
    //     );

    //     // Try if register exists on any of the modules including the debt issuance module
    //     address[] memory modules = _jasperVault.getModules();
    //     for (uint256 i = 0; i < modules.length; i++) {
    //         try
    //             IDebtIssuanceModule(modules[i]).registerToIssuanceModule(
    //                 _jasperVault
    //             )
    //         {} catch {}
    //     }
    // }

    // /**
    //  * @dev MANAGER ONLY: Removes this module from the JasperVault, via call by the JasperVault. Any deposited collateral assets
    //  * are disabled to be used as collateral on Spark. Spark Settings and manager enabled assets state is deleted.
    //  * Note: Function will revert is there is any debt remaining on Spark
    //  */
    // function removeModule()
    //     external
    //     override
    //     onlyValidAndInitializedSet(IJasperVault(msg.sender))
    // {
    //     IJasperVault jasperVault = IJasperVault(msg.sender);

    //     // Sync Spark and JasperVault positions prior to any removal action
    //     sync(jasperVault);

    //     address[] memory borrowAssets = enabledAssets[jasperVault].borrowAssets;
    //     for (uint256 i = 0; i < borrowAssets.length; i++) {
    //         IERC20 borrowAsset = IERC20(borrowAssets[i]);
    //         require(
    //             underlyingToReserveTokens[borrowAsset]
    //                 .variableDebtToken
    //                 .balanceOf(address(jasperVault)) == 0,
    //             "Variable debt remaining"
    //         );
    //     }

    //     address[] memory collateralAssets = enabledAssets[jasperVault]
    //         .collateralAssets;
    //     for (uint256 i = 0; i < collateralAssets.length; i++) {
    //         IERC20 collateralAsset = IERC20(collateralAssets[i]);
    //         _updateUseReserveAsCollateral(jasperVault, collateralAsset, false);
    //     }

    //     delete enabledAssets[jasperVault];

    //     // Try if unregister exists on any of the modules
    //     address[] memory modules = jasperVault.getModules();
    //     for (uint256 i = 0; i < modules.length; i++) {
    //         try
    //             IDebtIssuanceModule(modules[i]).unregisterFromIssuanceModule(
    //                 jasperVault
    //             )
    //         {} catch {}
    //     }
    // }

    // /**
    //  * @dev MANAGER ONLY: Add registration of this module on the debt issuance module for the JasperVault.
    //  * Note: if the debt issuance module is not added to JasperVault before this module is initialized, then this function
    //  * needs to be called if the debt issuance module is later added and initialized to prevent state inconsistencies
    //  * @param _jasperVault             Instance of the JasperVault
    //  * @param _debtIssuanceModule   Debt issuance module address to register
    //  */
    // function registerToModule(
    //     IJasperVault _jasperVault,
    //     IDebtIssuanceModule _debtIssuanceModule
    // ) external onlyManagerAndValidSet(_jasperVault) {
    //     require(
    //         _jasperVault.isInitializedModule(address(_debtIssuanceModule)),
    //         "Issuance not initialized"
    //     );

    //     _debtIssuanceModule.registerToIssuanceModule(_jasperVault);
    // }

    // /**
    //  * @dev CALLABLE BY ANYBODY: Updates `underlyingToReserveTokens` mappings. Reverts if mapping already exists
    //  * or the passed _underlying asset does not have a valid reserve on Spark.
    //  * Note: Call this function when Spark adds a new reserve.
    //  * @param _underlying               Address of underlying asset
    //  */
    // function addUnderlyingToReserveTokensMapping(IERC20 _underlying) external {
    //     require(
    //         address(underlyingToReserveTokens[_underlying].spToken) ==
    //             address(0),
    //         "Mapping already exists"
    //     );

    //     // An active reserve is an alias for a valid reserve on Spark.
    //     (, , , , , , , , bool isActive, ) = protocolDataProvider
    //         .getReserveConfigurationData(address(_underlying));
    //     require(isActive, "Invalid Spark reserve");

    //     _addUnderlyingToReserveTokensMapping(_underlying);
    // }

    // /**
    //  * @dev MODULE ONLY: Hook called prior to issuance to sync positions on JasperVault. Only callable by valid module.
    //  * @param _jasperVault             Instance of the JasperVault
    //  */
    // function moduleIssueHook(
    //     IJasperVault _jasperVault,
    //     uint256 /* _setTokenQuantity */
    // ) external /* override */ onlyModule(_jasperVault) {
    //     sync(_jasperVault);
    // }

    // /**
    //  * @dev MODULE ONLY: Hook called prior to redemption to sync positions on JasperVault. For redemption, always use current borrowed
    //  * balance after interest accrual. Only callable by valid module.
    //  * @param _jasperVault             Instance of the JasperVault
    //  */
    // function moduleRedeemHook(
    //     IJasperVault _jasperVault,
    //     uint256 /* _setTokenQuantity */
    // ) external /* override */ onlyModule(_jasperVault) {
    //     sync(_jasperVault);
    // }

    // /* ============ External Getter Functions ============ */

    // /**
    //  * @dev Get enabled assets for JasperVault. Returns an array of collateral and borrow assets.
    //  * @return Underlying collateral assets that are enabled
    //  * @return Underlying borrowed assets that are enabled
    //  */
    // function getEnabledAssets(
    //     IJasperVault _jasperVault
    // ) external view returns (address[] memory, address[] memory) {
    //     return (
    //         enabledAssets[_jasperVault].collateralAssets,
    //         enabledAssets[_jasperVault].borrowAssets
    //     );
    // }

    // /* ============ Internal Functions ============ */
    // /**
    //  * @dev Updates default position unit for given spToken on JasperVault
    //  */
    // function _updateCollateralPosition(
    //     IJasperVault _jasperVault,
    //     ISpToken _spToken,
    //     uint256 _newPositionUnit
    // ) internal {
    //     _jasperVault.editCoinType(address(_spToken), 3); // 0 -> Regular Asset, 1 -> aToken, 2 cToken, 3 -> spToken
    //     _jasperVault.editDefaultPosition(address(_spToken), _newPositionUnit);
    // }

    // /**
    //  * @dev Updates external position unit for given borrow asset on JasperVault
    //  */
    // function _updateBorrowPosition(
    //     IJasperVault _jasperVault,
    //     IERC20 _underlyingAsset,
    //     int256 _newPositionUnit
    // ) internal {
    //     _jasperVault.editExternalCoinType(
    //         address(_underlyingAsset),
    //         address(this),
    //         3
    //     );
    //     _jasperVault.editExternalPosition(
    //         address(_underlyingAsset),
    //         address(this),
    //         _newPositionUnit,
    //         ""
    //     );
    // }

    // /**
    //  * @dev Updates `underlyingToReserveTokens` mappings for given `_underlying` asset. Emits ReserveTokensUpdated event.
    //  */
    // function _addUnderlyingToReserveTokensMapping(IERC20 _underlying) internal {
    //     (address spToken, , address variableDebtToken) = protocolDataProvider
    //         .getReserveTokensAddresses(address(_underlying));
    //     underlyingToReserveTokens[_underlying].spToken = ISpToken(spToken);
    //     underlyingToReserveTokens[_underlying]
    //         .variableDebtToken = IVariableDebtToken(variableDebtToken);

    //     emit ReserveTokensUpdated(
    //         _underlying,
    //         ISpToken(spToken),
    //         IVariableDebtToken(variableDebtToken)
    //     );
    // }

    // /**
    //  * @dev Updates JasperVault's ability to use an asset as collateral on Spark/Spark
    //  */
    // function _updateUseReserveAsCollateral(
    //     IJasperVault _jasperVault,
    //     IERC20 _asset,
    //     bool _useAsCollateral
    // ) internal {
    //     /*
    //     Note: Spark ENABLES an asset to be used as collateral by `to` address in an `aToken.transfer(to, amount)` call provided
    //         1. msg.sender (from address) isn't the same as `to` address
    //         2. `to` address had zero aToken balance before the transfer
    //         3. transfer `amount` is greater than 0

    //     Note: Spark DISABLES an asset to be used as collateral by `msg.sender`in an `aToken.transfer(to, amount)` call provided
    //         1. msg.sender (from address) isn't the same as `to` address
    //         2. msg.sender has zero balance after the transfer

    //     Different states of the JasperVault and what this function does in those states:

    //         Case 1: Manager adds collateral asset to JasperVault before first issuance
    //             - Since aToken.balanceOf(jasperVault) == 0, we do not call `jasperVault.invokeUserUseReserveAsCollateral` because Spark
    //             requires aToken balance to be greater than 0 before enabling/disabling the underlying asset to be used as collateral
    //             on Spark markets.

    //         Case 2: First issuance of the JasperVault
    //             - JasperVault was initialized with aToken as default position
    //             - DebtIssuanceModule reads the default position and transfers corresponding aToken from the issuer to the JasperVault
    //             - Spark enables aToken to be used as collateral by the JasperVault
    //             - Manager calls lever() and the aToken is used as collateral to borrow other assets

    //         Case 3: Manager removes collateral asset from the JasperVault
    //             - Disable asset to be used as collateral on JasperVault by calling `jasperVault.invokeSetUserUseReserveAsCollateral` with
    //             useAsCollateral equals false
    //             - Note: If health factor goes below 1 by removing the collateral asset, then Spark reverts on the above call, thus whole
    //             transaction reverts, and manager can't remove corresponding collateral asset

    //         Case 4: Manager adds collateral asset after removing it
    //             - If aToken.balanceOf(jasperVault) > 0, we call `jasperVault.invokeUserUseReserveAsCollateral` and the corresponding aToken
    //             is re-enabled as collateral on Spark

    //         Case 5: On redemption/delever/liquidated and aToken balance becomes zero
    //             - Spark disables aToken to be used as collateral by JasperVault

    //     Values of variables in below if condition and corresponding action taken:

    //     ---------------------------------------------------------------------------------------------------------------------
    //     | usageAsCollateralEnabled |  _useAsCollateral |   aToken.balanceOf()  |     Action                                 |
    //     |--------------------------|-------------------|-----------------------|--------------------------------------------|
    //     |   true                   |   true            |      X                |   Skip invoke. Save gas.                   |
    //     |--------------------------|-------------------|-----------------------|--------------------------------------------|
    //     |   true                   |   false           |   greater than 0      |   Invoke and set to false.                 |
    //     |--------------------------|-------------------|-----------------------|--------------------------------------------|
    //     |   true                   |   false           |   = 0                 |   Impossible case. Spark disables usage as  |
    //     |                          |                   |                       |   collateral when aToken balance becomes 0 |
    //     |--------------------------|-------------------|-----------------------|--------------------------------------------|
    //     |   false                  |   false           |     X                 |   Skip invoke. Save gas.                   |
    //     |--------------------------|-------------------|-----------------------|--------------------------------------------|
    //     |   false                  |   true            |   greater than 0      |   Invoke and set to true.                  |
    //     |--------------------------|-------------------|-----------------------|--------------------------------------------|
    //     |   false                  |   true            |   = 0                 |   Don't invoke. Will revert.               |
    //     ---------------------------------------------------------------------------------------------------------------------
    //     */
    //     (, , , , , , , , bool usageAsCollateralEnabled) = protocolDataProvider
    //         .getUserReserveData(address(_asset), address(_jasperVault));

    //     if (
    //         usageAsCollateralEnabled != _useAsCollateral &&
    //         underlyingToReserveTokens[_asset].spToken.balanceOf(
    //             address(_jasperVault)
    //         ) >
    //         0
    //     ) {
    //         _jasperVault.invokeSetUserUseReserveAsCollateral(
    //             IPool(lendingPoolAddressesProvider.getPool()),
    //             address(_asset),
    //             _useAsCollateral
    //         );
    //     }
    // }

    // /**
    //  * @dev Reads spToken balance and calculates default position unit for given collateral spToken and JasperVault
    //  *
    //  * @return uint256       default collateral position unit
    //  */
    // function _getCollateralPosition(
    //     IJasperVault _jasperVault,
    //     ISpToken _spToken,
    //     uint256 _setTotalSupply
    // ) internal view returns (uint256) {
    //     uint256 collateralNotionalBalance = _spToken.balanceOf(
    //         address(_jasperVault)
    //     );
    //     return collateralNotionalBalance.preciseDiv(_setTotalSupply);
    // }

    // /**
    //  * @dev Reads variableDebtToken balance and calculates external position unit for given borrow asset and JasperVault
    //  *
    //  * @return int256       external borrow position unit
    //  */
    // function _getBorrowPosition(
    //     IJasperVault _jasperVault,
    //     IERC20 _borrowAsset,
    //     uint256 _setTotalSupply
    // ) internal view returns (int256) {
    //     uint256 borrowNotionalBalance = underlyingToReserveTokens[_borrowAsset]
    //         .variableDebtToken
    //         .balanceOf(address(_jasperVault));
    //     return
    //         borrowNotionalBalance
    //             .preciseDivCeil(_setTotalSupply)
    //             .toInt256()
    //             .mul(-1);
    // }
}
