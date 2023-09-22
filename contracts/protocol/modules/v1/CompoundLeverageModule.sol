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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Compound } from "../../integration/lib/Compound.sol";
import { ICErc20 } from "../../../interfaces/external/ICErc20.sol";
import { IComptroller } from "../../../interfaces/external/IComptroller.sol";
import { IController } from "../../../interfaces/IController.sol";
import { IDebtIssuanceModule } from "../../../interfaces/IDebtIssuanceModule.sol";
import { IExchangeAdapter } from "../../../interfaces/IExchangeAdapter.sol";
import { IJasperVault } from "../../../interfaces/IJasperVault.sol";
import { ModuleBase } from "../../lib/ModuleBase.sol";

/**
 * @title CompoundLeverageModule
 * @author Set Protocol
 *
 * Smart contract that enables leverage trading using Compound as the lending protocol. This module is paired with a debt issuance module that will call
 * functions on this module to keep interest accrual and liquidation state updated. This does not allow borrowing of assets from Compound alone. Each
 * asset is leveraged when using this module.
 *
 * Note: Do not use this module in conjunction with other debt modules that allow Compound debt positions as it could lead to double counting of
 * debt when borrowed assets are the same.
 *
 */
contract CompoundLeverageModule is ModuleBase, ReentrancyGuard, Ownable {
    using Compound for IJasperVault;

    /* ============ Structs ============ */

    struct EnabledAssets {
        address[] collateralCTokens;             // Array of enabled cToken collateral assets for a JasperVault
        address[] borrowCTokens;                 // Array of enabled cToken borrow assets for a JasperVault
        address[] borrowAssets;                  // Array of underlying borrow assets that map to the array of enabled cToken borrow assets
    }

    struct ActionInfo {
        IJasperVault jasperVault;                      // JasperVault instance
        IExchangeAdapter exchangeAdapter;        // Exchange adapter instance
        uint256 setTotalSupply;                  // Total supply of JasperVault
        uint256 notionalSendQuantity;            // Total notional quantity sent to exchange
        uint256 minNotionalReceiveQuantity;      // Min total notional received from exchange
        ICErc20 collateralCTokenAsset;           // Address of cToken collateral asset
        ICErc20 borrowCTokenAsset;               // Address of cToken borrow asset
        uint256 preTradeReceiveTokenBalance;     // Balance of pre-trade receive token balance
    }

    /* ============ Events ============ */

    event LeverageIncreased(
        IJasperVault indexed _jasperVault,
        IERC20 indexed _borrowAsset,
        IERC20 indexed _collateralAsset,
        IExchangeAdapter _exchangeAdapter,
        uint256 _totalBorrowAmount,
        uint256 _totalReceiveAmount,
        uint256 _protocolFee
    );

    event LeverageDecreased(
        IJasperVault indexed _jasperVault,
        IERC20 indexed _collateralAsset,
        IERC20 indexed _repayAsset,
        IExchangeAdapter _exchangeAdapter,
        uint256 _totalRedeemAmount,
        uint256 _totalRepayAmount,
        uint256 _protocolFee
    );

    event CollateralAssetsUpdated(
        IJasperVault indexed _jasperVault,
        bool indexed _added,
        IERC20[] _assets
    );

    event BorrowAssetsUpdated(
        IJasperVault indexed _jasperVault,
        bool indexed _added,
        IERC20[] _assets
    );

    event SetTokenStatusUpdated(
        IJasperVault indexed _jasperVault,
        bool indexed _added
    );

    event AnySetAllowedUpdated(
        bool indexed _anySetAllowed
    );

    /* ============ Constants ============ */

    // String identifying the DebtIssuanceModule in the IntegrationRegistry. Note: Governance must add DefaultIssuanceModule as
    // the string as the integration name
    string constant internal DEFAULT_ISSUANCE_MODULE_NAME = "DefaultIssuanceModule";

    // 0 index stores protocol fee % on the controller, charged in the trade function
    uint256 constant internal PROTOCOL_TRADE_FEE_INDEX = 0;

    /* ============ State Variables ============ */

    // Mapping of underlying to CToken. If ETH, then map WETH to cETH
    mapping(IERC20 => ICErc20) public underlyingToCToken;

    // Wrapped Ether address
    IERC20 internal weth;

    // Compound cEther address
    ICErc20 internal cEther;

    // Compound Comptroller contract
    IComptroller internal comptroller;

    // COMP token address
    IERC20 internal compToken;

    // Mapping to efficiently check if cToken market for collateral asset is valid in JasperVault
    mapping(IJasperVault => mapping(ICErc20 => bool)) public collateralCTokenEnabled;

    // Mapping to efficiently check if cToken market for borrow asset is valid in JasperVault
    mapping(IJasperVault => mapping(ICErc20 => bool)) public borrowCTokenEnabled;

    // Mapping of enabled collateral and borrow cTokens for syncing positions
    mapping(IJasperVault => EnabledAssets) internal enabledAssets;

    // Mapping of JasperVault to boolean indicating if JasperVault is on allow list. Updateable by governance
    mapping(IJasperVault => bool) public allowedSetTokens;

    // Boolean that returns if any JasperVault can initialize this module. If false, then subject to allow list
    bool public anySetAllowed;


    /* ============ Constructor ============ */

    /**
     * Instantiate addresses. Underlying to cToken mapping is created.
     *
     * @param _controller               Address of controller contract
     * @param _compToken                Address of COMP token
     * @param _comptroller              Address of Compound Comptroller
     * @param _cEther                   Address of cEther contract
     * @param _weth                     Address of WETH contract
     */
    constructor(
        IController _controller,
        IERC20 _compToken,
        IComptroller _comptroller,
        ICErc20 _cEther,
        IERC20 _weth
    )
        public
        ModuleBase(_controller)
    {
        compToken = _compToken;
        comptroller = _comptroller;
        cEther = _cEther;
        weth = _weth;

        ICErc20[] memory cTokens = comptroller.getAllMarkets();

        for(uint256 i = 0; i < cTokens.length; i++) {
            ICErc20 cToken = cTokens[i];
            underlyingToCToken[
                cToken == _cEther ? _weth : IERC20(cTokens[i].underlying())
            ] = cToken;
        }
    }

    /* ============ External Functions ============ */

    /**
     * MANAGER ONLY: Increases leverage for a given collateral position using an enabled borrow asset that is enabled.
     * Performs a DEX trade, exchanging the borrow asset for collateral asset.
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _borrowAsset          Address of asset being borrowed for leverage
     * @param _collateralAsset      Address of collateral asset (underlying of cToken)
     * @param _borrowQuantity       Borrow quantity of asset in position units
     * @param _minReceiveQuantity   Min receive quantity of collateral asset to receive post-trade in position units
     * @param _tradeAdapterName     Name of trade adapter
     * @param _tradeData            Arbitrary data for trade
     */
    function lever(
        IJasperVault _jasperVault,
        IERC20 _borrowAsset,
        IERC20 _collateralAsset,
        uint256 _borrowQuantity,
        uint256 _minReceiveQuantity,
        string memory _tradeAdapterName,
        bytes memory _tradeData
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        // For levering up, send quantity is derived from borrow asset and receive quantity is derived from
        // collateral asset
        ActionInfo memory leverInfo = _createAndValidateActionInfo(
            _jasperVault,
            _borrowAsset,
            _collateralAsset,
            _borrowQuantity,
            _minReceiveQuantity,
            _tradeAdapterName,
            true
        );

        _borrow(leverInfo.jasperVault, leverInfo.borrowCTokenAsset, leverInfo.notionalSendQuantity);

        uint256 postTradeReceiveQuantity = _executeTrade(leverInfo, _borrowAsset, _collateralAsset, _tradeData);

        uint256 protocolFee = _accrueProtocolFee(_jasperVault, _collateralAsset, postTradeReceiveQuantity);

        uint256 postTradeCollateralQuantity = postTradeReceiveQuantity.sub(protocolFee);

        _mintCToken(leverInfo.jasperVault, leverInfo.collateralCTokenAsset, _collateralAsset, postTradeCollateralQuantity);

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
     * MANAGER ONLY: Decrease leverage for a given collateral position using an enabled borrow asset that is enabled
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _collateralAsset      Address of collateral asset (underlying of cToken)
     * @param _repayAsset           Address of asset being repaid
     * @param _redeemQuantity       Quantity of collateral asset to delever
     * @param _minRepayQuantity     Minimum amount of repay asset to receive post trade
     * @param _tradeAdapterName     Name of trade adapter
     * @param _tradeData            Arbitrary data for trade
     */
    function delever(
        IJasperVault _jasperVault,
        IERC20 _collateralAsset,
        IERC20 _repayAsset,
        uint256 _redeemQuantity,
        uint256 _minRepayQuantity,
        string memory _tradeAdapterName,
        bytes memory _tradeData
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        // Note: for delevering, send quantity is derived from collateral asset and receive quantity is derived from
        // repay asset
        ActionInfo memory deleverInfo = _createAndValidateActionInfo(
            _jasperVault,
            _collateralAsset,
            _repayAsset,
            _redeemQuantity,
            _minRepayQuantity,
            _tradeAdapterName,
            false
        );

        _redeemUnderlying(deleverInfo.jasperVault, deleverInfo.collateralCTokenAsset, deleverInfo.notionalSendQuantity);

        uint256 postTradeReceiveQuantity = _executeTrade(deleverInfo, _collateralAsset, _repayAsset, _tradeData);

        uint256 protocolFee = _accrueProtocolFee(_jasperVault, _repayAsset, postTradeReceiveQuantity);

        uint256 repayQuantity = postTradeReceiveQuantity.sub(protocolFee);

        _repayBorrow(deleverInfo.jasperVault, deleverInfo.borrowCTokenAsset, _repayAsset, repayQuantity);

        _updateLeverPositions(deleverInfo, _repayAsset);

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

    /**
     * MANAGER ONLY: Pays down the borrow asset to 0 selling off a given collateral asset. Any extra received
     * borrow asset is updated as equity. No protocol fee is charged.
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _collateralAsset      Address of collateral asset (underlying of cToken)
     * @param _repayAsset           Address of asset being repaid (underlying asset e.g. DAI)
     * @param _redeemQuantity       Quantity of collateral asset to delever
     * @param _tradeAdapterName     Name of trade adapter
     * @param _tradeData            Arbitrary data for trade
     */
    function deleverToZeroBorrowBalance(
        IJasperVault _jasperVault,
        IERC20 _collateralAsset,
        IERC20 _repayAsset,
        uint256 _redeemQuantity,
        string memory _tradeAdapterName,
        bytes memory _tradeData
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        uint256 notionalRedeemQuantity = _redeemQuantity.preciseMul(_jasperVault.totalSupply());

        require(borrowCTokenEnabled[_jasperVault][underlyingToCToken[_repayAsset]], "Borrow not enabled");
        uint256 notionalRepayQuantity = underlyingToCToken[_repayAsset].borrowBalanceCurrent(address(_jasperVault));

        ActionInfo memory deleverInfo = _createAndValidateActionInfoNotional(
            _jasperVault,
            _collateralAsset,
            _repayAsset,
            notionalRedeemQuantity,
            notionalRepayQuantity,
            _tradeAdapterName,
            false
        );

        _redeemUnderlying(deleverInfo.jasperVault, deleverInfo.collateralCTokenAsset, deleverInfo.notionalSendQuantity);

        _executeTrade(deleverInfo, _collateralAsset, _repayAsset, _tradeData);

        // We use notionalRepayQuantity vs. Compound's max value uint256(-1) to handle WETH properly
        _repayBorrow(deleverInfo.jasperVault, deleverInfo.borrowCTokenAsset, _repayAsset, notionalRepayQuantity);

        // Update default position first to save gas on editing borrow position
        _jasperVault.calculateAndEditDefaultPosition(
            address(_repayAsset),
            deleverInfo.setTotalSupply,
            deleverInfo.preTradeReceiveTokenBalance
        );

        _updateLeverPositions(deleverInfo, _repayAsset);

        emit LeverageDecreased(
            _jasperVault,
            _collateralAsset,
            _repayAsset,
            deleverInfo.exchangeAdapter,
            deleverInfo.notionalSendQuantity,
            notionalRepayQuantity,
            0 // No protocol fee
        );
    }

    /**
     * CALLABLE BY ANYBODY: Sync Set positions with enabled Compound collateral and borrow positions. For collateral
     * assets, update cToken default position. For borrow assets, update external borrow position.
     * - Collateral assets may come out of sync when a position is liquidated
     * - Borrow assets may come out of sync when interest is accrued or position is liquidated and borrow is repaid
     *
     * @param _jasperVault               Instance of the JasperVault
     * @param _shouldAccrueInterest   Boolean indicating whether use current block interest rate value or stored value
     */
    function sync(IJasperVault _jasperVault, bool _shouldAccrueInterest) public nonReentrant onlyValidAndInitializedSet(_jasperVault) {
        uint256 setTotalSupply = _jasperVault.totalSupply();

        // Only sync positions when Set supply is not 0. This preserves debt and collateral positions on issuance / redemption
        if (setTotalSupply > 0) {
            // Loop through collateral assets
            address[] memory collateralCTokens = enabledAssets[_jasperVault].collateralCTokens;
            for(uint256 i = 0; i < collateralCTokens.length; i++) {
                ICErc20 collateralCToken = ICErc20(collateralCTokens[i]);
                uint256 previousPositionUnit = _jasperVault.getDefaultPositionRealUnit(address(collateralCToken)).toUint256();
                uint256 newPositionUnit = _getCollateralPosition(_jasperVault, collateralCToken, setTotalSupply);

                // Note: Accounts for if position does not exist on JasperVault but is tracked in enabledAssets
                if (previousPositionUnit != newPositionUnit) {
                  _updateCollateralPosition(_jasperVault, collateralCToken, newPositionUnit);
                }
            }

            // Loop through borrow assets
            address[] memory borrowCTokens = enabledAssets[_jasperVault].borrowCTokens;
            address[] memory borrowAssets = enabledAssets[_jasperVault].borrowAssets;
            for(uint256 i = 0; i < borrowCTokens.length; i++) {
                ICErc20 borrowCToken = ICErc20(borrowCTokens[i]);
                IERC20 borrowAsset = IERC20(borrowAssets[i]);

                int256 previousPositionUnit = _jasperVault.getExternalPositionRealUnit(address(borrowAsset), address(this));

                int256 newPositionUnit = _getBorrowPosition(
                    _jasperVault,
                    borrowCToken,
                    setTotalSupply,
                    _shouldAccrueInterest
                );

                // Note: Accounts for if position does not exist on JasperVault but is tracked in enabledAssets
                if (newPositionUnit != previousPositionUnit) {
                    _updateBorrowPosition(_jasperVault, borrowAsset, newPositionUnit);
                }
            }
        }
    }


    /**
     * MANAGER ONLY: Initializes this module to the JasperVault. Only callable by the JasperVault's manager. Note: managers can enable
     * collateral and borrow assets that don't exist as positions on the JasperVault
     *
     * @param _jasperVault             Instance of the JasperVault to initialize
     * @param _collateralAssets     Underlying tokens to be enabled as collateral in the JasperVault
     * @param _borrowAssets         Underlying tokens to be enabled as borrow in the JasperVault
     */
    function initialize(
        IJasperVault _jasperVault,
        IERC20[] memory _collateralAssets,
        IERC20[] memory _borrowAssets
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
        require(_jasperVault.isInitializedModule(getAndValidateAdapter(DEFAULT_ISSUANCE_MODULE_NAME)), "Issuance not initialized");

        // Try if register exists on any of the modules including the debt issuance module
        address[] memory modules = _jasperVault.getModules();
        for(uint256 i = 0; i < modules.length; i++) {
            try IDebtIssuanceModule(modules[i]).registerToIssuanceModule(_jasperVault) {} catch {}
        }

        // Enable collateral and borrow assets on Compound
        addCollateralAssets(_jasperVault, _collateralAssets);

        addBorrowAssets(_jasperVault, _borrowAssets);
    }

    /**
     * MANAGER ONLY: Removes this module from the JasperVault, via call by the JasperVault. Compound Settings and manager enabled
     * cTokens are deleted. Markets are exited on Comptroller (only valid if borrow balances are zero)
     */
    function removeModule() external override onlyValidAndInitializedSet(IJasperVault(msg.sender)) {
        IJasperVault jasperVault = IJasperVault(msg.sender);

        // Sync Compound and JasperVault positions prior to any removal action
        sync(jasperVault, true);

        address[] memory borrowCTokens = enabledAssets[jasperVault].borrowCTokens;
        for (uint256 i = 0; i < borrowCTokens.length; i++) {
            ICErc20 cToken = ICErc20(borrowCTokens[i]);

            // Will exit only if token isn't also being used as collateral
            if(!collateralCTokenEnabled[jasperVault][cToken]) {
                // Note: if there is an existing borrow balance, will revert and market cannot be exited on Compound
                jasperVault.invokeExitMarket(cToken, comptroller);
            }

            delete borrowCTokenEnabled[jasperVault][cToken];
        }

        address[] memory collateralCTokens = enabledAssets[jasperVault].collateralCTokens;
        for (uint256 i = 0; i < collateralCTokens.length; i++) {
            ICErc20 cToken = ICErc20(collateralCTokens[i]);

            jasperVault.invokeExitMarket(cToken, comptroller);

            delete collateralCTokenEnabled[jasperVault][cToken];
        }

        delete enabledAssets[jasperVault];

        // Try if unregister exists on any of the modules
        address[] memory modules = jasperVault.getModules();
        for(uint256 i = 0; i < modules.length; i++) {
            try IDebtIssuanceModule(modules[i]).unregisterFromIssuanceModule(jasperVault) {} catch {}
        }
    }

    /**
     * MANAGER ONLY: Add registration of this module on debt issuance module for the JasperVault. Note: if the debt issuance module is not added to JasperVault
     * before this module is initialized, then this function needs to be called if the debt issuance module is later added and initialized to prevent state
     * inconsistencies
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _debtIssuanceModule   Debt issuance module address to register
     */
    function registerToModule(IJasperVault _jasperVault, IDebtIssuanceModule _debtIssuanceModule) external onlyManagerAndValidSet(_jasperVault) {
        require(_jasperVault.isInitializedModule(address(_debtIssuanceModule)), "Issuance not initialized");

        _debtIssuanceModule.registerToIssuanceModule(_jasperVault);
    }

    /**
     * MANAGER ONLY: Add enabled collateral assets. Collateral assets are tracked for syncing positions and entered in Compound markets
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _newCollateralAssets  Addresses of new collateral underlying assets
     */
    function addCollateralAssets(IJasperVault _jasperVault, IERC20[] memory _newCollateralAssets) public onlyManagerAndValidSet(_jasperVault) {
        for(uint256 i = 0; i < _newCollateralAssets.length; i++) {
            ICErc20 cToken = underlyingToCToken[_newCollateralAssets[i]];
            require(address(cToken) != address(0), "cToken must exist");
            require(!collateralCTokenEnabled[_jasperVault][cToken], "Collateral enabled");

            // Note: Will only enter market if cToken is not enabled as a borrow asset as well
            if (!borrowCTokenEnabled[_jasperVault][cToken]) {
                _jasperVault.invokeEnterMarkets(cToken, comptroller);
            }

            collateralCTokenEnabled[_jasperVault][cToken] = true;
            enabledAssets[_jasperVault].collateralCTokens.push(address(cToken));
        }

        emit CollateralAssetsUpdated(_jasperVault, true, _newCollateralAssets);
    }

    /**
     * MANAGER ONLY: Remove collateral asset. Collateral asset exited in Compound markets
     * If there is a borrow balance, collateral asset cannot be removed
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _collateralAssets     Addresses of collateral underlying assets to remove
     */
    function removeCollateralAssets(IJasperVault _jasperVault, IERC20[] memory _collateralAssets) external onlyManagerAndValidSet(_jasperVault) {
        // Sync Compound and JasperVault positions prior to any removal action
        sync(_jasperVault, true);

        for(uint256 i = 0; i < _collateralAssets.length; i++) {
            ICErc20 cToken = underlyingToCToken[_collateralAssets[i]];
            require(collateralCTokenEnabled[_jasperVault][cToken], "Collateral not enabled");

            // Note: Will only exit market if cToken is not enabled as a borrow asset as well
            // If there is an existing borrow balance, will revert and market cannot be exited on Compound
            if (!borrowCTokenEnabled[_jasperVault][cToken]) {
                _jasperVault.invokeExitMarket(cToken, comptroller);
            }

            delete collateralCTokenEnabled[_jasperVault][cToken];
            enabledAssets[_jasperVault].collateralCTokens.removeStorage(address(cToken));
        }

        emit CollateralAssetsUpdated(_jasperVault, false, _collateralAssets);
    }

    /**
     * MANAGER ONLY: Add borrow asset. Borrow asset is tracked for syncing positions and entered in Compound markets
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _newBorrowAssets      Addresses of borrow underlying assets to add
     */
    function addBorrowAssets(IJasperVault _jasperVault, IERC20[] memory _newBorrowAssets) public onlyManagerAndValidSet(_jasperVault) {
        for(uint256 i = 0; i < _newBorrowAssets.length; i++) {
            IERC20 newBorrowAsset = _newBorrowAssets[i];
            ICErc20 cToken = underlyingToCToken[newBorrowAsset];
            require(address(cToken) != address(0), "cToken must exist");
            require(!borrowCTokenEnabled[_jasperVault][cToken], "Borrow enabled");

            // Note: Will only enter market if cToken is not enabled as a borrow asset as well
            if (!collateralCTokenEnabled[_jasperVault][cToken]) {
                _jasperVault.invokeEnterMarkets(cToken, comptroller);
            }

            borrowCTokenEnabled[_jasperVault][cToken] = true;
            enabledAssets[_jasperVault].borrowCTokens.push(address(cToken));
            enabledAssets[_jasperVault].borrowAssets.push(address(newBorrowAsset));
        }

        emit BorrowAssetsUpdated(_jasperVault, true, _newBorrowAssets);
    }

    /**
     * MANAGER ONLY: Remove borrow asset. Borrow asset is exited in Compound markets
     * If there is a borrow balance, borrow asset cannot be removed
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _borrowAssets         Addresses of borrow underlying assets to remove
     */
    function removeBorrowAssets(IJasperVault _jasperVault, IERC20[] memory _borrowAssets) external onlyManagerAndValidSet(_jasperVault) {
        // Sync Compound and JasperVault positions prior to any removal action
        sync(_jasperVault, true);

        for(uint256 i = 0; i < _borrowAssets.length; i++) {
            ICErc20 cToken = underlyingToCToken[_borrowAssets[i]];
            require(borrowCTokenEnabled[_jasperVault][cToken], "Borrow not enabled");

            // Note: Will only exit market if cToken is not enabled as a collateral asset as well
            // If there is an existing borrow balance, will revert and market cannot be exited on Compound
            if (!collateralCTokenEnabled[_jasperVault][cToken]) {
                _jasperVault.invokeExitMarket(cToken, comptroller);
            }

            delete borrowCTokenEnabled[_jasperVault][cToken];
            enabledAssets[_jasperVault].borrowCTokens.removeStorage(address(cToken));
            enabledAssets[_jasperVault].borrowAssets.removeStorage(address(_borrowAssets[i]));
        }

        emit BorrowAssetsUpdated(_jasperVault, false, _borrowAssets);
    }

    /**
     * GOVERNANCE ONLY: Add or remove allowed JasperVault to initialize this module. Only callable by governance.
     *
     * @param _jasperVault             Instance of the JasperVault
     */
    function updateAllowedSetToken(IJasperVault _jasperVault, bool _status) external onlyOwner {
        allowedSetTokens[_jasperVault] = _status;
        emit SetTokenStatusUpdated(_jasperVault, _status);
    }

    /**
     * GOVERNANCE ONLY: Toggle whether any JasperVault is allowed to initialize this module. Only callable by governance.
     *
     * @param _anySetAllowed             Bool indicating whether allowedSetTokens is enabled
     */
    function updateAnySetAllowed(bool _anySetAllowed) external onlyOwner {
        anySetAllowed = _anySetAllowed;
        emit AnySetAllowedUpdated(_anySetAllowed);
    }

    /**
     * GOVERNANCE ONLY: Add Compound market to module with stored underlying to cToken mapping in case of market additions to Compound.
     *
     * IMPORTANT: Validations are skipped in order to get contract under bytecode limit
     *
     * @param _cToken                   Address of cToken to add
     * @param _underlying               Address of underlying token that maps to cToken
     */
    function addCompoundMarket(ICErc20 _cToken, IERC20 _underlying) external onlyOwner {
        require(address(underlyingToCToken[_underlying]) == address(0), "Already added");
        underlyingToCToken[_underlying] = _cToken;
    }

    /**
     * GOVERNANCE ONLY: Remove Compound market on stored underlying to cToken mapping in case of market removals
     *
     * IMPORTANT: Validations are skipped in order to get contract under bytecode limit
     *
     * @param _underlying               Address of underlying token to remove
     */
    function removeCompoundMarket(IERC20 _underlying) external onlyOwner {
        require(address(underlyingToCToken[_underlying]) != address(0), "Not added");
        delete underlyingToCToken[_underlying];
    }

    /**
     * MODULE ONLY: Hook called prior to issuance to sync positions on JasperVault. Only callable by valid module.
     *
     * @param _jasperVault             Instance of the JasperVault
     */
    function moduleIssueHook(IJasperVault _jasperVault, uint256 /* _setTokenQuantity */) external onlyModule(_jasperVault) {
        sync(_jasperVault, false);
    }

    /**
     * MODULE ONLY: Hook called prior to redemption to sync positions on JasperVault. For redemption, always use current borrowed balance after interest accrual.
     * Only callable by valid module.
     *
     * @param _jasperVault             Instance of the JasperVault
     */
    function moduleRedeemHook(IJasperVault _jasperVault, uint256 /* _setTokenQuantity */) external onlyModule(_jasperVault) {
        sync(_jasperVault, true);
    }

    /**
     * MODULE ONLY: Hook called prior to looping through each component on issuance. Invokes borrow in order for module to return debt to issuer. Only callable by valid module.
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _setTokenQuantity     Quantity of JasperVault
     * @param _component            Address of component
     */
    function componentIssueHook(IJasperVault _jasperVault, uint256 _setTokenQuantity, IERC20 _component, bool /* _isEquity */) external onlyModule(_jasperVault) {
        int256 componentDebt = _jasperVault.getExternalPositionRealUnit(address(_component), address(this));

        require(componentDebt < 0, "Component must be negative");

        uint256 notionalDebt = componentDebt.mul(-1).toUint256().preciseMul(_setTokenQuantity);

        _borrow(_jasperVault, underlyingToCToken[_component], notionalDebt);
    }

    /**
     * MODULE ONLY: Hook called prior to looping through each component on redemption. Invokes repay after issuance module transfers debt from issuer. Only callable by valid module.
     *
     * @param _jasperVault             Instance of the JasperVault
     * @param _setTokenQuantity     Quantity of JasperVault
     * @param _component            Address of component
     */
    function componentRedeemHook(IJasperVault _jasperVault, uint256 _setTokenQuantity, IERC20 _component, bool /* _isEquity */) external onlyModule(_jasperVault) {
        int256 componentDebt = _jasperVault.getExternalPositionRealUnit(address(_component), address(this));

        require(componentDebt < 0, "Component must be negative");

        uint256 notionalDebt = componentDebt.mul(-1).toUint256().preciseMulCeil(_setTokenQuantity);

        _repayBorrow(_jasperVault, underlyingToCToken[_component], _component, notionalDebt);
    }


    /* ============ External Getter Functions ============ */

    /**
     * Get enabled assets for JasperVault. Returns an array of enabled cTokens that are collateral assets and an
     * array of underlying that are borrow assets.
     *
     * @return                    Collateral cToken assets that are enabled
     * @return                    Underlying borrowed assets that are enabled.
     */
    function getEnabledAssets(IJasperVault _jasperVault) external view returns(address[] memory, address[] memory) {
        return (
            enabledAssets[_jasperVault].collateralCTokens,
            enabledAssets[_jasperVault].borrowAssets
        );
    }

    /* ============ Internal Functions ============ */

    /**
     * Mints the specified cToken from the underlying of the specified notional quantity. If cEther, the WETH must be
     * unwrapped as it only accepts the underlying ETH.
     */
    function _mintCToken(IJasperVault _jasperVault, ICErc20 _cToken, IERC20 _underlyingToken, uint256 _mintNotional) internal {
        if (_cToken == cEther) {
            _jasperVault.invokeUnwrapWETH(address(weth), _mintNotional);

            _jasperVault.invokeMintCEther(_cToken, _mintNotional);
        } else {
            _jasperVault.invokeApprove(address(_underlyingToken), address(_cToken), _mintNotional);

            _jasperVault.invokeMintCToken(_cToken, _mintNotional);
        }
    }

    /**
     * Invoke redeem from JasperVault. If cEther, then also wrap ETH into WETH.
     */
    function _redeemUnderlying(IJasperVault _jasperVault, ICErc20 _cToken, uint256 _redeemNotional) internal {
        _jasperVault.invokeRedeemUnderlying(_cToken, _redeemNotional);

        if (_cToken == cEther) {
            _jasperVault.invokeWrapWETH(address(weth), _redeemNotional);
        }
    }

    /**
     * Invoke repay from JasperVault. If cEther then unwrap WETH into ETH.
     */
    function _repayBorrow(IJasperVault _jasperVault, ICErc20 _cToken, IERC20 _underlyingToken, uint256 _repayNotional) internal {
        if (_cToken == cEther) {
            _jasperVault.invokeUnwrapWETH(address(weth), _repayNotional);

            _jasperVault.invokeRepayBorrowCEther(_cToken, _repayNotional);
        } else {
            // Approve to cToken
            _jasperVault.invokeApprove(address(_underlyingToken), address(_cToken), _repayNotional);
            _jasperVault.invokeRepayBorrowCToken(_cToken, _repayNotional);
        }
    }

    /**
     * Invoke the JasperVault to interact with the specified cToken to borrow the cToken's underlying of the specified borrowQuantity.
     */
    function _borrow(IJasperVault _jasperVault, ICErc20 _cToken, uint256 _notionalBorrowQuantity) internal {
        _jasperVault.invokeBorrow(_cToken, _notionalBorrowQuantity);
        if (_cToken == cEther) {
            _jasperVault.invokeWrapWETH(address(weth), _notionalBorrowQuantity);
        }
    }

    /**
     * Invokes approvals, gets trade call data from exchange adapter and invokes trade from JasperVault
     *
     * @return receiveTokenQuantity The quantity of tokens received post-trade
     */
    function _executeTrade(
        ActionInfo memory _actionInfo,
        IERC20 _sendToken,
        IERC20 _receiveToken,
        bytes memory _data
    )
        internal
        returns (uint256)
    {
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

        uint256 receiveTokenQuantity = _receiveToken.balanceOf(address(jasperVault)).sub(_actionInfo.preTradeReceiveTokenBalance);
        require(
            receiveTokenQuantity >= _actionInfo.minNotionalReceiveQuantity,
            "Slippage too high"
        );

        return receiveTokenQuantity;
    }

    /**
     * Calculates protocol fee on module and pays protocol fee from JasperVault
     */
    function _accrueProtocolFee(IJasperVault _jasperVault, IERC20 _receiveToken, uint256 _exchangedQuantity) internal returns(uint256) {
        uint256 protocolFeeTotal = getModuleFee(PROTOCOL_TRADE_FEE_INDEX, _exchangedQuantity);

        payProtocolFeeFromSetToken(_jasperVault, address(_receiveToken), protocolFeeTotal);

        return protocolFeeTotal;
    }

    /**
     * Updates the collateral (cToken held) and borrow position (underlying owed on Compound)
     */
    function _updateLeverPositions(ActionInfo memory actionInfo, IERC20 _borrowAsset) internal {
        _updateCollateralPosition(
            actionInfo.jasperVault,
            actionInfo.collateralCTokenAsset,
            _getCollateralPosition(
                actionInfo.jasperVault,
                actionInfo.collateralCTokenAsset,
                actionInfo.setTotalSupply
            )
        );

        _updateBorrowPosition(
            actionInfo.jasperVault,
            _borrowAsset,
            _getBorrowPosition(
                actionInfo.jasperVault,
                actionInfo.borrowCTokenAsset,
                actionInfo.setTotalSupply,
                false // Do not accrue interest
            )
        );
    }

    function _updateCollateralPosition(IJasperVault _jasperVault, ICErc20 _cToken, uint256 _newPositionUnit) public {
        _jasperVault.editCoinType(address(_cToken),2);
        _jasperVault.editDefaultPosition(address(_cToken), _newPositionUnit);

    }

    function _updateBorrowPosition(IJasperVault _jasperVault, IERC20 _underlyingToken, int256 _newPositionUnit) internal {
        _jasperVault.editExternalCoinType(address(_underlyingToken),address(this),2);        
        _jasperVault.editExternalPosition(address(_underlyingToken), address(this), _newPositionUnit, "");
    }

    /**
     * Construct the ActionInfo struct for lever and delever
     */
    function _createAndValidateActionInfo(
        IJasperVault _jasperVault,
        IERC20 _sendToken,
        IERC20 _receiveToken,
        uint256 _sendQuantityUnits,
        uint256 _minReceiveQuantityUnits,
        string memory _tradeAdapterName,
        bool _isLever
    )
        internal
        view
        returns(ActionInfo memory)
    {
        uint256 totalSupply = _jasperVault.totalSupply();

        return _createAndValidateActionInfoNotional(
            _jasperVault,
            _sendToken,
            _receiveToken,
            _sendQuantityUnits.preciseMul(totalSupply),
            _minReceiveQuantityUnits.preciseMul(totalSupply),
            _tradeAdapterName,
            _isLever
        );
    }

    /**
     * Construct the ActionInfo struct for lever and delever accepting notional units
     */
    function _createAndValidateActionInfoNotional(
        IJasperVault _jasperVault,
        IERC20 _sendToken,
        IERC20 _receiveToken,
        uint256 _notionalSendQuantity,
        uint256 _minNotionalReceiveQuantity,
        string memory _tradeAdapterName,
        bool _isLever
    )
        internal
        view
        returns(ActionInfo memory)
    {
        uint256 totalSupply = _jasperVault.totalSupply();
        ActionInfo memory actionInfo = ActionInfo ({
            exchangeAdapter: IExchangeAdapter(getAndValidateAdapter(_tradeAdapterName)),
            jasperVault: _jasperVault,
            collateralCTokenAsset: _isLever ? underlyingToCToken[_receiveToken] : underlyingToCToken[_sendToken],
            borrowCTokenAsset: _isLever ? underlyingToCToken[_sendToken] : underlyingToCToken[_receiveToken],
            setTotalSupply: totalSupply,
            notionalSendQuantity: _notionalSendQuantity,
            minNotionalReceiveQuantity: _minNotionalReceiveQuantity,
            preTradeReceiveTokenBalance: IERC20(_receiveToken).balanceOf(address(_jasperVault))
        });

        _validateCommon(actionInfo);

        return actionInfo;
    }



    function _validateCommon(ActionInfo memory _actionInfo) internal view {
        require(collateralCTokenEnabled[_actionInfo.jasperVault][_actionInfo.collateralCTokenAsset], "Collateral not enabled");
        require(borrowCTokenEnabled[_actionInfo.jasperVault][_actionInfo.borrowCTokenAsset], "Borrow not enabled");
        require(_actionInfo.collateralCTokenAsset != _actionInfo.borrowCTokenAsset, "Must be different");
        require(_actionInfo.notionalSendQuantity > 0, "Quantity is 0");
    }

    function _getCollateralPosition(IJasperVault _jasperVault, ICErc20 _cToken, uint256 _setTotalSupply) internal view returns (uint256) {
        uint256 collateralNotionalBalance = _cToken.balanceOf(address(_jasperVault));
        return collateralNotionalBalance.preciseDiv(_setTotalSupply);
    }

    /**
     * Get borrow position. If should accrue interest is true, then accrue interest on Compound and use current borrow balance, else use the stored value to save gas.
     * Use the current value for debt redemption, when we need to calculate the exact units of debt that needs to be repaid.
     */
    function _getBorrowPosition(IJasperVault _jasperVault, ICErc20 _cToken, uint256 _setTotalSupply, bool _shouldAccrueInterest) internal returns (int256) {
        uint256 borrowNotionalBalance = _shouldAccrueInterest ? _cToken.borrowBalanceCurrent(address(_jasperVault)) : _cToken.borrowBalanceStored(address(_jasperVault));
        // Round negative away from 0
        int256 borrowPositionUnit = borrowNotionalBalance.preciseDivCeil(_setTotalSupply).toInt256().mul(-1);

        return borrowPositionUnit;
    }
}
