/*
    Copyright 2021 Set Labs Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {AaveV2} from "../../integration/lib/AaveV2.sol";
import {IAToken} from "../../../interfaces/external/aave-v2/IAToken.sol";
import {IController} from "../../../interfaces/IController.sol";
import {IDebtIssuanceModule} from "../../../interfaces/IDebtIssuanceModule.sol";
import {IExchangeAdapter} from "../../../interfaces/IExchangeAdapter.sol";
import {ILendingPool} from "../../../interfaces/external/aave-v2/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "../../../interfaces/external/aave-v2/ILendingPoolAddressesProvider.sol";
import {IModuleIssuanceHook} from "../../../interfaces/IModuleIssuanceHook.sol";
import {IProtocolDataProvider} from "../../../interfaces/external/aave-v2/IProtocolDataProvider.sol";
import {IJasperVault} from "../../../interfaces/IJasperVault.sol";
import {IVariableDebtToken} from "../../../interfaces/external/aave-v2/IVariableDebtToken.sol";
import {ModuleBase} from "../../lib/ModuleBase.sol";

/**
 * @title AaveLeverageModule
 * @author Set Protocol
 * @notice Smart contract that enables leverage trading using Aave as the lending protocol.
 * @dev Do not use this module in conjunction with other debt modules that allow Aave debt positions as it could lead to double counting of
 * debt when borrowed assets are the same.
 */
contract AaveLeverageModule is
    ModuleBase,
    ReentrancyGuard,
    Ownable,
    IModuleIssuanceHook
{
    using AaveV2 for IJasperVault;

    /* ============ Structs ============ */

    struct EnabledAssets {
        address[] collateralAssets; // Array of enabled underlying collateral assets for a JasperVault
        address[] borrowAssets; // Array of enabled underlying borrow assets for a JasperVault
    }

    struct ActionInfo {
        IJasperVault jasperVault; // JasperVault instance
        ILendingPool lendingPool; // Lending pool instance, we grab this everytime since it's best practice not to store
        IExchangeAdapter exchangeAdapter; // Exchange adapter instance
        uint256 setTotalSupply; // Total supply of JasperVault
        uint256 notionalSendQuantity; // Total notional quantity sent to exchange
        uint256 minNotionalReceiveQuantity; // Min total notional received from exchange
        IERC20 collateralAsset; // Address of collateral asset
        IERC20 borrowAsset; // Address of borrow asset
        uint256 preTradeReceiveTokenBalance; // Balance of pre-trade receive token balance
    }

    struct ReserveTokens {
        IAToken aToken; // Reserve's aToken instance
        IVariableDebtToken variableDebtToken; // Reserve's variable debt token instance
    }

    /* ============ Events ============ */

    /**
     * @dev Emitted on lever()
     * @param _jasperVault             Instance of the JasperVault being levered
     * @param _borrowAsset          Asset being borrowed for leverage
     * @param _collateralAsset      Collateral asset being levered
     * @param _exchangeAdapter      Exchange adapter used for trading
     * @param _totalBorrowAmount    Total amount of `_borrowAsset` borrowed
     * @param _totalReceiveAmount   Total amount of `_collateralAsset` received by selling `_borrowAsset`
     * @param _protocolFee          Protocol fee charged
     */
    event LeverageIncreased(
        IJasperVault indexed _jasperVault,
        IERC20 indexed _borrowAsset,
        IERC20 indexed _collateralAsset,
        IExchangeAdapter _exchangeAdapter,
        uint256 _totalBorrowAmount,
        uint256 _totalReceiveAmount,
        uint256 _protocolFee
    );

    /**
     * @dev Emitted on delever() and deleverToZeroBorrowBalance()
     * @param _jasperVault             Instance of the JasperVault being delevered
     * @param _collateralAsset      Asset sold to decrease leverage
     * @param _repayAsset           Asset being bought to repay to Aave
     * @param _exchangeAdapter      Exchange adapter used for trading
     * @param _totalRedeemAmount    Total amount of `_collateralAsset` being sold
     * @param _totalRepayAmount     Total amount of `_repayAsset` being repaid
     * @param _protocolFee          Protocol fee charged
     */
    event LeverageDecreased(
        IJasperVault indexed _jasperVault,
        IERC20 indexed _collateralAsset,
        IERC20 indexed _repayAsset,
        IExchangeAdapter _exchangeAdapter,
        uint256 _totalRedeemAmount,
        uint256 _totalRepayAmount,
        uint256 _protocolFee
    );

    /**
     * @dev Emitted on addCollateralAssets() and removeCollateralAssets()
     * @param _jasperVault Instance of JasperVault whose collateral assets is updated
     * @param _added    true if assets are added false if removed
     * @param _assets   Array of collateral assets being added/removed
     */
    event CollateralAssetsUpdated(
        IJasperVault indexed _jasperVault,
        bool indexed _added,
        IERC20[] _assets
    );

    /**
     * @dev Emitted on addBorrowAssets() and removeBorrowAssets()
     * @param _jasperVault Instance of JasperVault whose borrow assets is updated
     * @param _added    true if assets are added false if removed
     * @param _assets   Array of borrow assets being added/removed
     */
    event BorrowAssetsUpdated(
        IJasperVault indexed _jasperVault,
        bool indexed _added,
        IERC20[] _assets
    );

    /**
     * @dev Emitted when `underlyingToReserveTokensMappings` is updated
     * @param _underlying           Address of the underlying asset
     * @param _aToken               Updated aave reserve aToken
     * @param _variableDebtToken    Updated aave reserve variable debt token
     */
    event ReserveTokensUpdated(
        IERC20 indexed _underlying,
        IAToken indexed _aToken,
        IVariableDebtToken indexed _variableDebtToken
    );

    /**
     * @dev Emitted on updateAllowedSetToken()
     * @param _jasperVault JasperVault being whose allowance to initialize this module is being updated
     * @param _added    true if added false if removed
     */
    event SetTokenStatusUpdated(
        IJasperVault indexed _jasperVault,
        bool indexed _added
    );

    /**
     * @dev Emitted on updateAnySetAllowed()
     * @param _anySetAllowed    true if any set is allowed to initialize this module, false otherwise
     */
    event AnySetAllowedUpdated(bool indexed _anySetAllowed);

    /* ============ Constants ============ */

    // This module only supports borrowing in variable rate mode from Aave which is represented by 2
    uint256 internal constant BORROW_RATE_MODE = 2;

    // String identifying the DebtIssuanceModule in the IntegrationRegistry. Note: Governance must add DefaultIssuanceModule as
    // the string as the integration name
    string internal constant DEFAULT_ISSUANCE_MODULE_NAME =
        "DefaultIssuanceModule";

    // 0 index stores protocol fee % on the controller, charged in the _executeTrade function
    uint256 internal constant PROTOCOL_TRADE_FEE_INDEX = 0;

    /* ============ State Variables ============ */

    // Mapping to efficiently fetch reserve token addresses. Tracking Aave reserve token addresses and updating them
    // upon requirement is more efficient than fetching them each time from Aave.
    // Note: For an underlying asset to be enabled as collateral/borrow asset on JasperVault, it must be added to this mapping first.
    mapping(IERC20 => ReserveTokens) public underlyingToReserveTokens;

    // Used to fetch reserves and user data from AaveV2
    IProtocolDataProvider public immutable protocolDataProvider;

    // Used to fetch lendingPool address. This contract is immutable and its address will never change.
    ILendingPoolAddressesProvider public immutable lendingPoolAddressesProvider;


    // Internal mapping of enabled collateral and borrow tokens for syncing positions
    mapping(IJasperVault => EnabledAssets) internal enabledAssets;

    // Mapping of JasperVault to boolean indicating if JasperVault is on allow list. Updateable by governance
    mapping(IJasperVault => bool) public allowedSetTokens;

    // Boolean that returns if any JasperVault can initialize this module. If false, then subject to allow list. Updateable by governance.
    bool public anySetAllowed;

    /* ============ Constructor ============ */

    /**
     * @dev Instantiate addresses. Underlying to reserve tokens mapping is created.
     * @param _controller                       Address of controller contract
     * @param _lendingPoolAddressesProvider     Address of Aave LendingPoolAddressProvider
     */
    constructor(
        IController _controller,
        ILendingPoolAddressesProvider _lendingPoolAddressesProvider
    ) public ModuleBase(_controller) {
        lendingPoolAddressesProvider = _lendingPoolAddressesProvider;
        IProtocolDataProvider _protocolDataProvider = IProtocolDataProvider(
            // Use the raw input vs bytes32() conversion. This is to ensure the input is an uint and not a string.
            _lendingPoolAddressesProvider.getAddress(
                0x0100000000000000000000000000000000000000000000000000000000000000
            )
        );
        protocolDataProvider = _protocolDataProvider;

        IProtocolDataProvider.TokenData[]
            memory reserveTokens = _protocolDataProvider.getAllReservesTokens();
        for (uint256 i = 0; i < reserveTokens.length; i++) {
            (
                address aToken,
                ,
                address variableDebtToken
            ) = _protocolDataProvider.getReserveTokensAddresses(
                    reserveTokens[i].tokenAddress
                );
            underlyingToReserveTokens[
                IERC20(reserveTokens[i].tokenAddress)
            ] = ReserveTokens(
                IAToken(aToken),
                IVariableDebtToken(variableDebtToken)
            );
        }
    }

    /* ============ External Functions ============ */
    function borrow(  
           IJasperVault _jasperVault,
           IERC20 _borrowAsset,
           uint256 _borrowQuantityUnits
         ) external nonReentrant onlyManagerAndValidSet(_jasperVault){
        ILendingPool   lendingPool=ILendingPool(
                lendingPoolAddressesProvider.getLendingPool()
            );
        uint256 setTotalSupply = _jasperVault.totalSupply();    
        uint256 quantity= _borrowQuantityUnits.preciseMul(setTotalSupply);
        require(quantity> 0, "Quantity is 0");
        _borrow(
            _jasperVault,
            lendingPool,
            _borrowAsset ,
            quantity
        );  
        uint256 newBorrowAsset=_borrowAsset.balanceOf(address(_jasperVault));
        _updatePosition(_jasperVault,_borrowAsset,newBorrowAsset.preciseDiv(setTotalSupply)); 
        _updateBorrowPosition(
            _jasperVault,
            _borrowAsset,
            _getBorrowPosition(
                _jasperVault,
                _borrowAsset,
                setTotalSupply
            )
        );
    }


    function repay(
        IJasperVault _jasperVault,
        IERC20 _repayAsset,
        uint256 _redeemQuantityUnits,
        bool  _isAllRepay
    ) external nonReentrant onlyManagerAndValidSet(_jasperVault){
        ILendingPool   lendingPool=ILendingPool(
                lendingPoolAddressesProvider.getLendingPool()
            );
        uint256 setTotalSupply = _jasperVault.totalSupply();    
        uint256 repayUnit;
        if(_isAllRepay){
            repayUnit= underlyingToReserveTokens[_repayAsset].variableDebtToken.balanceOf(address(_jasperVault));        
        }else{
            repayUnit=_redeemQuantityUnits.preciseMul(setTotalSupply);
        }
        uint256  preRepayAsset=_repayAsset.balanceOf(address(_jasperVault));
        require(repayUnit> 0, "repayUnit is 0");
        require(preRepayAsset>= repayUnit,"repayUnit exceeds balance");
        _repayBorrow(
            _jasperVault,
            lendingPool,
            _repayAsset,
            repayUnit
        );    
         uint256 nextRepayAsset=_repayAsset.balanceOf(address(_jasperVault));
         _updatePosition(_jasperVault,_repayAsset,nextRepayAsset.preciseDiv(setTotalSupply)); 
         if(_isAllRepay){
            _updateBorrowPosition(
                _jasperVault,
                _repayAsset,
                0 
            );
         }else{
            _updateBorrowPosition(
                _jasperVault,
                _repayAsset,
                _getBorrowPosition(
                    _jasperVault,
                    _repayAsset,
                    setTotalSupply
                )
            );
         }

    }



    /**
     * @dev MANAGER ONLY: Increases leverage for a given collateral position using an enabled borrow asset.
     * Borrows _borrowAsset from Aave. Performs a DEX trade, exchanging the _borrowAsset for _collateralAsset.
     * Deposits _collateralAsset to Aave and mints corresponding aToken.
     * Note: Both collateral and borrow assets need to be enabled, and they must not be the same asset.
     * @param _jasperVault                     Instance of the JasperVault
     * @param _borrowAsset                  Address of underlying asset being borrowed for leverage
     * @param _collateralAsset              Address of underlying collateral asset
     * @param _borrowQuantityUnits          Borrow quantity of asset in position units
     * @param _minReceiveQuantityUnits      Min receive quantity of collateral asset to receive post-trade in position units
     * @param _tradeAdapterName             Name of trade adapter
     * @param _tradeData                    Arbitrary data for trade
     */
    function lever(
        IJasperVault _jasperVault,
        IERC20 _borrowAsset,
        IERC20 _collateralAsset,
        uint256 _borrowQuantityUnits,
        uint256 _minReceiveQuantityUnits,
        string memory _tradeAdapterName,
        bytes memory _tradeData
    ) external nonReentrant onlyManagerAndValidSet(_jasperVault) {
        // For levering up, send quantity is derived from borrow asset and receive quantity is derived from
        // collateral asset
        ActionInfo memory leverInfo = _createAndValidateActionInfo(
            _jasperVault,
            _borrowAsset,
            _collateralAsset,
            _borrowQuantityUnits,
            _minReceiveQuantityUnits,
            _tradeAdapterName,
            true
        );

        _borrow(
            leverInfo.jasperVault,
            leverInfo.lendingPool,
            leverInfo.borrowAsset,
            leverInfo.notionalSendQuantity
        );

        uint256 postTradeReceiveQuantity = _executeTrade(
            leverInfo,
            _borrowAsset,
            _collateralAsset,
            _tradeData
        );

        uint256 protocolFee = _accrueProtocolFee(
            _jasperVault,
            _collateralAsset,
            postTradeReceiveQuantity
        );

        uint256 postTradeCollateralQuantity = postTradeReceiveQuantity.sub(
            protocolFee
        );

        _deposit(
            leverInfo.jasperVault,
            leverInfo.lendingPool,
            _collateralAsset,
            postTradeCollateralQuantity
        );

        _updateLeverPositions(leverInfo, _borrowAsset);

        emit LeverageIncreased(
            _jasperVault,
            _borrowAsset,
            _collateralAsset,
            leverInfo.exchangeAdapter,
            leverInfo.notionalSendQuantity,
            postTradeCollateralQuantity,
            protocolFee
        );
    }

    /**
     * @dev MANAGER ONLY: Decrease leverage for a given collateral position using an enabled borrow asset.
     * Withdraws _collateralAsset from Aave. Performs a DEX trade, exchanging the _collateralAsset for _repayAsset.
     * Repays _repayAsset to Aave and burns corresponding debt tokens.
     * Note: Both collateral and borrow assets need to be enabled, and they must not be the same asset.
     * @param _jasperVault                 Instance of the JasperVault
     * @param _collateralAsset          Address of underlying collateral asset being withdrawn
     * @param _repayAsset               Address of underlying borrowed asset being repaid
     * @param _redeemQuantityUnits      Quantity of collateral asset to delever in position units
     * @param _minRepayQuantityUnits    Minimum amount of repay asset to receive post trade in position units
     * @param _tradeAdapterName         Name of trade adapter
     * @param _tradeData                Arbitrary data for trade
     */
    function delever(
        IJasperVault _jasperVault,
        IERC20 _collateralAsset,
        IERC20 _repayAsset,
        uint256 _redeemQuantityUnits,
        uint256 _minRepayQuantityUnits,
        string memory _tradeAdapterName,
        bytes memory _tradeData
    ) external nonReentrant onlyManagerAndValidSet(_jasperVault) {
        // Note: for delevering, send quantity is derived from collateral asset and receive quantity is derived from
        // repay asset
        ActionInfo memory deleverInfo = _createAndValidateActionInfo(
            _jasperVault,
            _collateralAsset,
            _repayAsset,
            _redeemQuantityUnits,
            _minRepayQuantityUnits,
            _tradeAdapterName,
            false
        );

        _withdraw(
            deleverInfo.jasperVault,
            deleverInfo.lendingPool,
            _collateralAsset,
            deleverInfo.notionalSendQuantity
        );

        uint256 postTradeReceiveQuantity = _executeTrade(
            deleverInfo,
            _collateralAsset,
            _repayAsset,
            _tradeData
        );

        uint256 protocolFee = _accrueProtocolFee(
            _jasperVault,
            _repayAsset,
            postTradeReceiveQuantity
        );

        uint256 repayQuantity = postTradeReceiveQuantity.sub(protocolFee);

        _repayBorrow(
            deleverInfo.jasperVault,
            deleverInfo.lendingPool,
            _repayAsset,
            repayQuantity
        );

        _updateDeleverPositions(deleverInfo, _repayAsset);

        emit LeverageDecreased(
            _jasperVault,
            _collateralAsset,
            _repayAsset,
            deleverInfo.exchangeAdapter,
            deleverInfo.notionalSendQuantity,
            repayQuantity,
            protocolFee
        );
    }

    /** @dev MANAGER ONLY: Pays down the borrow asset to 0 selling off a given amount of collateral asset.
     * Withdraws _collateralAsset from Aave. Performs a DEX trade, exchanging the _collateralAsset for _repayAsset.
     * Minimum receive amount for the DEX trade is set to the current variable debt balance of the borrow asset.
     * Repays received _repayAsset to Aave which burns corresponding debt tokens. Any extra received borrow asset is .
     * updated as equity. No protocol fee is charged.
     * Note: Both collateral and borrow assets need to be enabled, and they must not be the same asset.
     * The function reverts if not enough collateral asset is redeemed to buy the required minimum amount of _repayAsset.
     * @param _jasperVault             Instance of the JasperVault
     * @param _collateralAsset      Address of underlying collateral asset being redeemed
     * @param _repayAsset           Address of underlying asset being repaid
     * @param _redeemQuantityUnits  Quantity of collateral asset to delever in position units
     * @param _tradeAdapterName     Name of trade adapter
     * @param _tradeData            Arbitrary data for trade
     * @return uint256              Notional repay quantity
     */
    function deleverToZeroBorrowBalance(
        IJasperVault _jasperVault,
        IERC20 _collateralAsset,
        IERC20 _repayAsset,
        uint256 _redeemQuantityUnits,
        string memory _tradeAdapterName,
        bytes memory _tradeData
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
        returns (uint256)
    {
        uint256 setTotalSupply = _jasperVault.totalSupply();
        uint256 notionalRedeemQuantity =_redeemQuantityUnits.preciseMul(
            setTotalSupply
        );
        uint256 notionalRepayQuantity = underlyingToReserveTokens[_repayAsset]
            .variableDebtToken
            .balanceOf(address(_jasperVault));
        require(notionalRepayQuantity > 0, "Borrow balance is zero");

        ActionInfo memory deleverInfo = _createAndValidateActionInfoNotional(
            _jasperVault,
            _collateralAsset,
            _repayAsset,
            notionalRedeemQuantity,
            notionalRepayQuantity,
            _tradeAdapterName,
            false,
            setTotalSupply
        );

        _withdraw(
            deleverInfo.jasperVault,
            deleverInfo.lendingPool,
            _collateralAsset,
            deleverInfo.notionalSendQuantity
        );

        _executeTrade(deleverInfo, _collateralAsset, _repayAsset, _tradeData);

        _repayBorrow(
            deleverInfo.jasperVault,
            deleverInfo.lendingPool,
            _repayAsset,
            notionalRepayQuantity
        );

        _updateDeleverPositions(deleverInfo, _repayAsset);

        emit LeverageDecreased(
            _jasperVault,
            _collateralAsset,
            _repayAsset,
            deleverInfo.exchangeAdapter,
            deleverInfo.notionalSendQuantity,
            notionalRepayQuantity,
            0 // No protocol fee
        );

        return notionalRepayQuantity;
    }

    /**
     * @dev CALLABLE BY ANYBODY: Sync Set positions with ALL enabled Aave collateral and borrow positions.
     * For collateral assets, update aToken default position. For borrow assets, update external borrow position.
     * - Collateral assets may come out of sync when interest is accrued or a position is liquidated
     * - Borrow assets may come out of sync when interest is accrued or position is liquidated and borrow is repaid
     * Note: In Aave, both collateral and borrow interest is accrued in each block by increasing the balance of
     * aTokens and debtTokens for each user, and 1 aToken = 1 variableDebtToken = 1 underlying.
     * @param _jasperVault               Instance of the JasperVault
     */
    function sync(IJasperVault _jasperVault)
        public
        nonReentrant
        onlyValidAndInitializedSet(_jasperVault)
    {
        uint256 setTotalSupply = _jasperVault.totalSupply();

        // Only sync positions when Set supply is not 0. Without this check, if sync is called by someone before the
        // first issuance, then editDefaultPosition would remove the default positions from the JasperVault
        if (setTotalSupply > 0) {
            address[] memory collateralAssets = enabledAssets[_jasperVault]
                .collateralAssets;
            for (uint256 i = 0; i < collateralAssets.length; i++) {
                IAToken aToken = underlyingToReserveTokens[
                    IERC20(collateralAssets[i])
                ].aToken;

                uint256 previousPositionUnit = _jasperVault
                    .getDefaultPositionRealUnit(address(aToken))
                    .toUint256();
                uint256 newPositionUnit = _getCollateralPosition(
                    _jasperVault,
                    aToken,
                    setTotalSupply
                );

                // Note: Accounts for if position does not exist on JasperVault but is tracked in enabledAssets
                if (previousPositionUnit != newPositionUnit) {
                    _updateCollateralPosition(
                        _jasperVault,
                        aToken,
                        newPositionUnit
                    );
                }
            }

            address[] memory borrowAssets = enabledAssets[_jasperVault]
                .borrowAssets;
            for (uint256 i = 0; i < borrowAssets.length; i++) {
                IERC20 borrowAsset = IERC20(borrowAssets[i]);

                int256 previousPositionUnit = _jasperVault
                    .getExternalPositionRealUnit(
                        address(borrowAsset),
                        address(this)
                    );
                int256 newPositionUnit = _getBorrowPosition(
                    _jasperVault,
                    borrowAsset,
                    setTotalSupply
                );

                // Note: Accounts for if position does not exist on JasperVault but is tracked in enabledAssets
                if (newPositionUnit != previousPositionUnit) {
                    _updateBorrowPosition(
                        _jasperVault,
                        borrowAsset,
                        newPositionUnit
                    );
                }
            }
        }
    }

    /**
     * @dev MANAGER ONLY: Initializes this module to the JasperVault. Either the JasperVault needs to be on the allowed list
     * or anySetAllowed needs to be true. Only callable by the JasperVault's manager.
     * Note: Managers can enable collateral and borrow assets that don't exist as positions on the JasperVault
     * @param _jasperVault             Instance of the JasperVault to initialize
     */
    function initialize(
        IJasperVault _jasperVault
    )
        external
        onlySetManager(_jasperVault, msg.sender)
        onlyValidAndPendingSet(_jasperVault)
    {
        if (!anySetAllowed) {
            require(allowedSetTokens[_jasperVault], "Not allowed JasperVault");
        }

        // Initialize module before trying register
        _jasperVault.initializeModule();

        // Get debt issuance module registered to this module and require that it is initialized
        require(
            _jasperVault.isInitializedModule(
                getAndValidateAdapter(DEFAULT_ISSUANCE_MODULE_NAME)
            ),
            "Issuance not initialized"
        );

        // Try if register exists on any of the modules including the debt issuance module
        address[] memory modules = _jasperVault.getModules();
        for (uint256 i = 0; i < modules.length; i++) {
            try
                IDebtIssuanceModule(modules[i]).registerToIssuanceModule(
                    _jasperVault
                )
            {} catch {}
        }
    }

    /**
     * @dev MANAGER ONLY: Removes this module from the JasperVault, via call by the JasperVault. Any deposited collateral assets
     * are disabled to be used as collateral on Aave. Aave Settings and manager enabled assets state is deleted.
     * Note: Function will revert is there is any debt remaining on Aave
     */
    function removeModule()
        external
        override
        onlyValidAndInitializedSet(IJasperVault(msg.sender))
    {
        IJasperVault jasperVault = IJasperVault(msg.sender);

        // Sync Aave and JasperVault positions prior to any removal action
        sync(jasperVault);

        address[] memory borrowAssets = enabledAssets[jasperVault].borrowAssets;
        for (uint256 i = 0; i < borrowAssets.length; i++) {
            IERC20 borrowAsset = IERC20(borrowAssets[i]);
            require(
                underlyingToReserveTokens[borrowAsset]
                    .variableDebtToken
                    .balanceOf(address(jasperVault)) == 0,
                "Variable debt remaining"
            );
        }

        address[] memory collateralAssets = enabledAssets[jasperVault]
            .collateralAssets;
        for (uint256 i = 0; i < collateralAssets.length; i++) {
            IERC20 collateralAsset = IERC20(collateralAssets[i]);
            _updateUseReserveAsCollateral(jasperVault, collateralAsset, false);

        }

        delete enabledAssets[jasperVault];

        // Try if unregister exists on any of the modules
        address[] memory modules = jasperVault.getModules();
        for (uint256 i = 0; i < modules.length; i++) {
            try
                IDebtIssuanceModule(modules[i]).unregisterFromIssuanceModule(
                    jasperVault
                )
            {} catch {}
        }
    }

    /**
     * @dev MANAGER ONLY: Add registration of this module on the debt issuance module for the SetToken.
     * Note: if the debt issuance module is not added to SetToken before this module is initialized, then this function
     * needs to be called if the debt issuance module is later added and initialized to prevent state inconsistencies
     * @param _jasperVault             Instance of the SetToken
     * @param _debtIssuanceModule   Debt issuance module address to register
     */
    function registerToModule(
        IJasperVault _jasperVault,
        IDebtIssuanceModule _debtIssuanceModule
    ) external onlyManagerAndValidSet(_jasperVault) {
        require(
            _jasperVault.isInitializedModule(address(_debtIssuanceModule)),
            "Issuance not initialized"
        );

        _debtIssuanceModule.registerToIssuanceModule(_jasperVault);
    }

    /**
     * @dev CALLABLE BY ANYBODY: Updates `underlyingToReserveTokens` mappings. Reverts if mapping already exists
     * or the passed _underlying asset does not have a valid reserve on Aave.
     * Note: Call this function when Aave adds a new reserve.
     * @param _underlying               Address of underlying asset
     */
    function addUnderlyingToReserveTokensMapping(IERC20 _underlying) external {
        require(
            address(underlyingToReserveTokens[_underlying].aToken) ==
                address(0),
            "Mapping already exists"
        );

        // An active reserve is an alias for a valid reserve on Aave.
        (, , , , , , , , bool isActive, ) = protocolDataProvider
            .getReserveConfigurationData(address(_underlying));
        require(isActive, "Invalid aave reserve");

        _addUnderlyingToReserveTokensMapping(_underlying);
    }

    /**
     * @dev GOVERNANCE ONLY: Enable/disable ability of a SetToken to initialize this module. Only callable by governance.
     * @param _jasperVault             Instance of the SetToken
     * @param _status               Bool indicating if _jasperVault is allowed to initialize this module
     */
    function updateAllowedSetToken(IJasperVault _jasperVault, bool _status)
        external
        onlyOwner
    {
        require(
            controller.isSet(address(_jasperVault)) || allowedSetTokens[_jasperVault],
            "Invalid SetToken"
        );
        allowedSetTokens[_jasperVault] = _status;
        emit SetTokenStatusUpdated(_jasperVault, _status);
    }

    /**
     * @dev GOVERNANCE ONLY: Toggle whether ANY SetToken is allowed to initialize this module. Only callable by governance.
     * @param _anySetAllowed             Bool indicating if ANY SetToken is allowed to initialize this module
     */
    function updateAnySetAllowed(bool _anySetAllowed) external onlyOwner {
        anySetAllowed = _anySetAllowed;
        emit AnySetAllowedUpdated(_anySetAllowed);
    }

    /**
     * @dev MODULE ONLY: Hook called prior to issuance to sync positions on SetToken. Only callable by valid module.
     * @param _jasperVault             Instance of the SetToken
     */
    function moduleIssueHook(
        IJasperVault _jasperVault,
        uint256 /* _setTokenQuantity */
    ) external override onlyModule(_jasperVault) {
        sync(_jasperVault);
    }

    /**
     * @dev MODULE ONLY: Hook called prior to redemption to sync positions on SetToken. For redemption, always use current borrowed
     * balance after interest accrual. Only callable by valid module.
     * @param _jasperVault             Instance of the SetToken
     */
    function moduleRedeemHook(
        IJasperVault _jasperVault,
        uint256 /* _setTokenQuantity */
    ) external override onlyModule(_jasperVault) {
        sync(_jasperVault);
    }

    /**
     * @dev MODULE ONLY: Hook called prior to looping through each component on issuance. Invokes borrow in order for
     * module to return debt to issuer. Only callable by valid module.
     * @param _jasperVault             Instance of the SetToken
     * @param _setTokenQuantity     Quantity of SetToken
     * @param _component            Address of component
     */
    function componentIssueHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity,
        IERC20 _component,
        bool _isEquity
    ) external override onlyModule(_jasperVault) {
        // Check hook not being called for an equity position. If hook is called with equity position and outstanding borrow position
        // exists the loan would be taken out twice potentially leading to liquidation
        if (!_isEquity) {
            int256 componentDebt = _jasperVault.getExternalPositionRealUnit(
                address(_component),
                address(this)
            );

            require(componentDebt < 0, "Component must be negative");

            uint256 notionalDebt = componentDebt.mul(-1).toUint256().preciseMul(
                _setTokenQuantity
            );
            _borrowForHook(_jasperVault, _component, notionalDebt);
        }
    }

    /**
     * @dev MODULE ONLY: Hook called prior to looping through each component on redemption. Invokes repay after
     * the issuance module transfers debt from the issuer. Only callable by valid module.
     * @param _jasperVault             Instance of the SetToken
     * @param _setTokenQuantity     Quantity of SetToken
     * @param _component            Address of component
     */
    function componentRedeemHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity,
        IERC20 _component,
        bool _isEquity
    ) external override onlyModule(_jasperVault) {
        // Check hook not being called for an equity position. If hook is called with equity position and outstanding borrow position
        // exists the loan would be paid down twice, decollateralizing the Set
        if (!_isEquity) {
            int256 componentDebt = _jasperVault.getExternalPositionRealUnit(
                address(_component),
                address(this)
            );

            require(componentDebt < 0, "Component must be negative");

            uint256 notionalDebt = componentDebt
                .mul(-1)
                .toUint256()
                .preciseMulCeil(_setTokenQuantity);
            _repayBorrowForHook(_jasperVault, _component, notionalDebt);
        }
    }

    /* ============ External Getter Functions ============ */

    /**
     * @dev Get enabled assets for SetToken. Returns an array of collateral and borrow assets.
     * @return Underlying collateral assets that are enabled
     * @return Underlying borrowed assets that are enabled
     */
    function getEnabledAssets(IJasperVault _jasperVault)
        external
        view
        returns (address[] memory, address[] memory)
    {
        return (
            enabledAssets[_jasperVault].collateralAssets,
            enabledAssets[_jasperVault].borrowAssets
        );
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev Invoke deposit from SetToken using AaveV2 library. Mints aTokens for SetToken.
     */
    function _deposit(
        IJasperVault _jasperVault,
        ILendingPool _lendingPool,
        IERC20 _asset,
        uint256 _notionalQuantity
    ) internal {
        _updateUseReserveAsCollateral(_jasperVault,_asset,true);
        _jasperVault.invokeApprove(
            address(_asset),
            address(_lendingPool),
            _notionalQuantity
        );
        _jasperVault.invokeDeposit(
            _lendingPool,
            address(_asset),
            _notionalQuantity
        );
        
    }

    /**
     * @dev Invoke withdraw from SetToken using AaveV2 library. Burns aTokens and returns underlying to SetToken.
     */
    function _withdraw(
        IJasperVault _jasperVault,
        ILendingPool _lendingPool,
        IERC20 _asset,
        uint256 _notionalQuantity
    ) internal {
        uint256 finalWithDrawn= _jasperVault.invokeWithdraw(
            _lendingPool,
            address(_asset),
            _notionalQuantity
        );
        require(finalWithDrawn==_notionalQuantity,"withdraw  fail");
    }

    /**
     * @dev Invoke repay from SetToken using AaveV2 library. Burns DebtTokens for SetToken.
     */
    function _repayBorrow(
        IJasperVault _jasperVault,
        ILendingPool _lendingPool,
        IERC20 _asset,
        uint256 _notionalQuantity
    ) internal {
        _jasperVault.invokeApprove(
            address(_asset),
            address(_lendingPool),
            _notionalQuantity
        );
        uint256 finalRepaid=_jasperVault.invokeRepay(
            _lendingPool,
            address(_asset),
            _notionalQuantity,
            BORROW_RATE_MODE
        );
        require(finalRepaid==_notionalQuantity,"repay fail");
    }

    /**
     * @dev Invoke borrow from the SetToken during issuance hook. Since we only need to interact with AAVE once we fetch the
     * lending pool in this function to optimize vs forcing a fetch twice during lever/delever.
     */
    function _repayBorrowForHook(
        IJasperVault _jasperVault,
        IERC20 _asset,
        uint256 _notionalQuantity
    ) internal {
       
        _repayBorrow(
            _jasperVault,
            ILendingPool(lendingPoolAddressesProvider.getLendingPool()),
            _asset,
            _notionalQuantity
        );
    }

    /**
     * @dev Invoke borrow from the SetToken using AaveV2 library. Mints DebtTokens for SetToken.
     */
    function _borrow(
        IJasperVault _jasperVault,
        ILendingPool _lendingPool,
        IERC20 _asset,
        uint256 _notionalQuantity
    ) internal {
        _jasperVault.invokeBorrow(
            _lendingPool,
            address(_asset),
            _notionalQuantity,
            BORROW_RATE_MODE
        );
    }
    /**
     * @dev Invoke borrow from the SetToken during issuance hook. Since we only need to interact with AAVE once we fetch the
     * lending pool in this function to optimize vs forcing a fetch twice during lever/delever.
     */
    function _borrowForHook(
        IJasperVault _jasperVault,
        IERC20 _asset,
        uint256 _notionalQuantity
    ) internal {
        _borrow(
            _jasperVault,
            ILendingPool(lendingPoolAddressesProvider.getLendingPool()),
            _asset,
            _notionalQuantity
        );
    }

    /**
     * @dev Invokes approvals, gets trade call data from exchange adapter and invokes trade from SetToken
     * @return uint256     The quantity of tokens received post-trade
     */
    function _executeTrade(
        ActionInfo memory _actionInfo,
        IERC20 _sendToken,
        IERC20 _receiveToken,
        bytes memory _data
    ) internal returns (uint256) {
        IJasperVault jasperVault = _actionInfo.jasperVault;
        uint256 notionalSendQuantity = _actionInfo.notionalSendQuantity;

        jasperVault.invokeApprove(
            address(_sendToken),
            _actionInfo.exchangeAdapter.getSpender(),
            notionalSendQuantity
        );

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = _actionInfo.exchangeAdapter.getTradeCalldata(
                address(_sendToken),
                address(_receiveToken),
                address(jasperVault),
                notionalSendQuantity,
                _actionInfo.minNotionalReceiveQuantity,
                _data
            );

        jasperVault.invoke(targetExchange, callValue, methodData);

        uint256 receiveTokenQuantity = _receiveToken
            .balanceOf(address(jasperVault))
            .sub(_actionInfo.preTradeReceiveTokenBalance);
        require(
            receiveTokenQuantity >= _actionInfo.minNotionalReceiveQuantity,
            "Slippage too high"
        );

        return receiveTokenQuantity;
    }

    /**
     * @dev Calculates protocol fee on module and pays protocol fee from SetToken
     * @return uint256          Total protocol fee paid
     */
    function _accrueProtocolFee(
        IJasperVault _jasperVault,
        IERC20 _receiveToken,
        uint256 _exchangedQuantity
    ) internal returns (uint256) {
        uint256 protocolFeeTotal = getModuleFee(
            PROTOCOL_TRADE_FEE_INDEX,
            _exchangedQuantity
        );

        payProtocolFeeFromSetToken(
            _jasperVault,
            address(_receiveToken),
            protocolFeeTotal
        );

        return protocolFeeTotal;
    }

    /**
     * @dev Updates the collateral (aToken held) and borrow position (variableDebtToken held) of the SetToken
     */
    function _updateLeverPositions(
        ActionInfo memory _actionInfo,
        IERC20 _borrowAsset
    ) internal {
        IAToken aToken = underlyingToReserveTokens[_actionInfo.collateralAsset]
            .aToken;
        _updateCollateralPosition(
            _actionInfo.jasperVault,
            aToken,
            _getCollateralPosition(
                _actionInfo.jasperVault,
                aToken,
                _actionInfo.setTotalSupply
            )
        );

        _updateBorrowPosition(
            _actionInfo.jasperVault,
            _borrowAsset,
            _getBorrowPosition(
                _actionInfo.jasperVault,
                _borrowAsset,
                _actionInfo.setTotalSupply
            )
        );
    }

    /**
     * @dev Updates positions as per _updateLeverPositions and updates Default position for borrow asset in case Set is
     * delevered all the way to zero any remaining borrow asset after the debt is paid can be added as a position.
     */
    function _updateDeleverPositions(
        ActionInfo memory _actionInfo,
        IERC20 _repayAsset
    ) internal {
        // if amount of tokens traded for exceeds debt, update default position first to save gas on editing borrow position
        uint256 repayAssetBalance = _repayAsset.balanceOf(
            address(_actionInfo.jasperVault)
        );
        if (repayAssetBalance != _actionInfo.preTradeReceiveTokenBalance) {
            _actionInfo.jasperVault.calculateAndEditDefaultPosition(
                address(_repayAsset),
                _actionInfo.setTotalSupply,
                _actionInfo.preTradeReceiveTokenBalance
            );
        }

        _updateLeverPositions(_actionInfo, _repayAsset);
    }

    /**
     * @dev Updates default position unit for given aToken on SetToken
     */
    function _updateCollateralPosition(
        IJasperVault _jasperVault,
        IAToken _aToken,
        uint256 _newPositionUnit
    ) internal {
        _jasperVault.editCoinType(address(_aToken),1);
        _jasperVault.editDefaultPosition(address(_aToken), _newPositionUnit);
    
    }

    function _updatePosition( 
        IJasperVault _jasperVault,
        IERC20 _token,
        uint256 _newPositionUnit
    ) internal {
        _jasperVault.editCoinType(address(_token),0);
        _jasperVault.editDefaultPosition(address(_token), _newPositionUnit);
    }

    /**
     * @dev Updates external position unit for given borrow asset on SetToken
     */
    function _updateBorrowPosition(
        IJasperVault _jasperVault,
        IERC20 _underlyingAsset,
        int256 _newPositionUnit
    ) internal {
        _jasperVault.editExternalCoinType(
            address(_underlyingAsset),
            address(this),
            1
        );
        _jasperVault.editExternalPosition(
            address(_underlyingAsset),
            address(this),
            _newPositionUnit,
            ""
        );

    }

    /**
     * @dev Construct the ActionInfo struct for lever and delever
     * @return ActionInfo       Instance of constructed ActionInfo struct
     */
    function _createAndValidateActionInfo(
        IJasperVault _jasperVault,
        IERC20 _sendToken,
        IERC20 _receiveToken,
        uint256 _sendQuantityUnits,
        uint256 _minReceiveQuantityUnits,
        string memory _tradeAdapterName,
        bool _isLever
    ) internal view returns (ActionInfo memory) {
        uint256 totalSupply = _jasperVault.totalSupply();

        return
            _createAndValidateActionInfoNotional(
                _jasperVault,
                _sendToken,
                _receiveToken,
                _sendQuantityUnits.preciseMul(totalSupply),
                _minReceiveQuantityUnits.preciseMul(totalSupply),
                _tradeAdapterName,
                _isLever,
                totalSupply
            );
    }

    /**
     * @dev Construct the ActionInfo struct for lever and delever accepting notional units
     * @return ActionInfo       Instance of constructed ActionInfo struct
     */
    function _createAndValidateActionInfoNotional(
        IJasperVault _jasperVault,
        IERC20 _sendToken,
        IERC20 _receiveToken,
        uint256 _notionalSendQuantity,
        uint256 _minNotionalReceiveQuantity,
        string memory _tradeAdapterName,
        bool _isLever,
        uint256 _setTotalSupply
    ) internal view returns (ActionInfo memory) {
        ActionInfo memory actionInfo = ActionInfo({
            exchangeAdapter: IExchangeAdapter(
                getAndValidateAdapter(_tradeAdapterName)
            ),
            lendingPool: ILendingPool(
                lendingPoolAddressesProvider.getLendingPool()
            ),
            jasperVault: _jasperVault,
            collateralAsset: _isLever ? _receiveToken : _sendToken,
            borrowAsset: _isLever ? _sendToken : _receiveToken,
            setTotalSupply: _setTotalSupply,
            notionalSendQuantity: _notionalSendQuantity,
            minNotionalReceiveQuantity: _minNotionalReceiveQuantity,
            preTradeReceiveTokenBalance: IERC20(_receiveToken).balanceOf(
                address(_jasperVault)
            )
        });

        _validateCommon(actionInfo);

        return actionInfo;
    }

    /**
     * @dev Updates `underlyingToReserveTokens` mappings for given `_underlying` asset. Emits ReserveTokensUpdated event.
     */
    function _addUnderlyingToReserveTokensMapping(IERC20 _underlying) internal {
        (address aToken, , address variableDebtToken) = protocolDataProvider
            .getReserveTokensAddresses(address(_underlying));
        underlyingToReserveTokens[_underlying].aToken = IAToken(aToken);
        underlyingToReserveTokens[_underlying]
            .variableDebtToken = IVariableDebtToken(variableDebtToken);

        emit ReserveTokensUpdated(
            _underlying,
            IAToken(aToken),
            IVariableDebtToken(variableDebtToken)
        );
    }

    /**
     * @dev Updates SetToken's ability to use an asset as collateral on Aave
     */
    function _updateUseReserveAsCollateral(
        IJasperVault _jasperVault,
        IERC20 _asset,
        bool _useAsCollateral
    ) internal {
        /*
        Note: Aave ENABLES an asset to be used as collateral by `to` address in an `aToken.transfer(to, amount)` call provided
            1. msg.sender (from address) isn't the same as `to` address
            2. `to` address had zero aToken balance before the transfer
            3. transfer `amount` is greater than 0

        Note: Aave DISABLES an asset to be used as collateral by `msg.sender`in an `aToken.transfer(to, amount)` call provided
            1. msg.sender (from address) isn't the same as `to` address
            2. msg.sender has zero balance after the transfer

        Different states of the SetToken and what this function does in those states:

            Case 1: Manager adds collateral asset to SetToken before first issuance
                - Since aToken.balanceOf(jasperVault) == 0, we do not call `jasperVault.invokeUserUseReserveAsCollateral` because Aave
                requires aToken balance to be greater than 0 before enabling/disabling the underlying asset to be used as collateral
                on Aave markets.

            Case 2: First issuance of the SetToken
                - SetToken was initialized with aToken as default position
                - DebtIssuanceModule reads the default position and transfers corresponding aToken from the issuer to the SetToken
                - Aave enables aToken to be used as collateral by the SetToken
                - Manager calls lever() and the aToken is used as collateral to borrow other assets

            Case 3: Manager removes collateral asset from the SetToken
                - Disable asset to be used as collateral on SetToken by calling `jasperVault.invokeSetUserUseReserveAsCollateral` with
                useAsCollateral equals false
                - Note: If health factor goes below 1 by removing the collateral asset, then Aave reverts on the above call, thus whole
                transaction reverts, and manager can't remove corresponding collateral asset

            Case 4: Manager adds collateral asset after removing it
                - If aToken.balanceOf(jasperVault) > 0, we call `jasperVault.invokeUserUseReserveAsCollateral` and the corresponding aToken
                is re-enabled as collateral on Aave

            Case 5: On redemption/delever/liquidated and aToken balance becomes zero
                - Aave disables aToken to be used as collateral by SetToken

        Values of variables in below if condition and corresponding action taken:

        ---------------------------------------------------------------------------------------------------------------------
        | usageAsCollateralEnabled |  _useAsCollateral |   aToken.balanceOf()  |     Action                                 |
        |--------------------------|-------------------|-----------------------|--------------------------------------------|
        |   true                   |   true            |      X                |   Skip invoke. Save gas.                   |
        |--------------------------|-------------------|-----------------------|--------------------------------------------|
        |   true                   |   false           |   greater than 0      |   Invoke and set to false.                 |
        |--------------------------|-------------------|-----------------------|--------------------------------------------|
        |   true                   |   false           |   = 0                 |   Impossible case. Aave disables usage as  |
        |                          |                   |                       |   collateral when aToken balance becomes 0 |
        |--------------------------|-------------------|-----------------------|--------------------------------------------|
        |   false                  |   false           |     X                 |   Skip invoke. Save gas.                   |
        |--------------------------|-------------------|-----------------------|--------------------------------------------|
        |   false                  |   true            |   greater than 0      |   Invoke and set to true.                  |
        |--------------------------|-------------------|-----------------------|--------------------------------------------|
        |   false                  |   true            |   = 0                 |   Don't invoke. Will revert.               |
        ---------------------------------------------------------------------------------------------------------------------
        */
        (, , , , , , , , bool usageAsCollateralEnabled) = protocolDataProvider .getUserReserveData(address(_asset), address(_jasperVault));
           
        if (
            usageAsCollateralEnabled != _useAsCollateral &&
            underlyingToReserveTokens[_asset].aToken.balanceOf(
                address(_jasperVault)
            ) >
            0
        ) {
            _jasperVault.invokeSetUserUseReserveAsCollateral(
                ILendingPool(lendingPoolAddressesProvider.getLendingPool()),
                address(_asset),
                _useAsCollateral
            );
        }
    }

    /**
     * @dev Validate common requirements for lever and delever
     */
    function _validateCommon(ActionInfo memory _actionInfo) internal pure {
        require(
            _actionInfo.collateralAsset != _actionInfo.borrowAsset,
            "Collateral and borrow asset must be different"
        );
        require(_actionInfo.notionalSendQuantity > 0, "Quantity is 0");
    }

  
    /**
     * @dev Reads aToken balance and calculates default position unit for given collateral aToken and SetToken
     *
     * @return uint256       default collateral position unit
     */
    function _getCollateralPosition(
        IJasperVault _jasperVault,
        IAToken _aToken,
        uint256 _setTotalSupply
    ) internal view returns (uint256) {
        uint256 collateralNotionalBalance = _aToken.balanceOf(
            address(_jasperVault)
        );
        return collateralNotionalBalance.preciseDiv(_setTotalSupply);
    }

    /**
     * @dev Reads variableDebtToken balance and calculates external position unit for given borrow asset and SetToken
     *
     * @return int256       external borrow position unit
     */
    function _getBorrowPosition(
        IJasperVault _jasperVault,
        IERC20 _borrowAsset,
        uint256 _setTotalSupply
    ) internal view returns (int256) {
        uint256 borrowNotionalBalance = underlyingToReserveTokens[_borrowAsset]
            .variableDebtToken
            .balanceOf(address(_jasperVault));
        return
            borrowNotionalBalance
                .preciseDivCeil(_setTotalSupply)
                .toInt256()
                .mul(-1);
    }
}
 