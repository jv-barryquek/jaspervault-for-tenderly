// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";

import {IJasperVault} from "../../interfaces/IJasperVault.sol";
import {IWETH} from "@setprotocol/set-protocol-v2/contracts/interfaces/external/IWETH.sol";
import {ILeverageModuleV2} from "../../interfaces/ILeverageModuleV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseGlobalExtension} from "../lib/BaseGlobalExtension.sol";
import {IDelegatedManager} from "../interfaces/IDelegatedManager.sol";
import {IManagerCore} from "../interfaces/IManagerCore.sol";

import {ISignalSuscriptionModule} from "../../interfaces/ISignalSuscriptionModule.sol";

/**
 * @title LeverageExtensionV2
 * @author JasperVault
 *
 * @notice Extension for invoking repay, borrow, lever, and delever on AaveV3's Pool contract
 * @dev If you wish to invoke supply* or withdraw* related functions, use the WrapExtension with the AaveV3WrapV2Adapter
 * ! For discussion: we can streamline interacting with the spToken Pool and AaveV3's pool by adding a boolean flag / Enum parameter to the various functions (e.g. repay, borrow, lever, delever) indicating whether or not it's AaveV3's Pool or Spark's Pool we're targetting. See the `borrow` function below for an e.g.
 */
contract LeverageExtensionV2 is BaseGlobalExtension {
    /* ============ Enums ============ */
    enum LeverageProtocol {
        AaveV3,
        Spark
    }

    /* ============ Events ============ */

    event LeverageExtensionInitialized(
        address indexed _jasperVault,
        address indexed _delegatedManager
    );
    event InvokeFail(
        address indexed _manage,
        address _leverageModule,
        string _reason,
        bytes _callData
    );

    struct LeverInfo {
        IERC20 borrowAsset;
        IERC20 collateralAsset;
        uint256 borrowQuantityUnits;
        uint256 minReceiveQuantityUnits;
        string tradeAdapterName;
        bytes tradeData;
    }
    struct LeverWithPermitInfo {
        IERC20 borrowAsset;
        IERC20 collateralAsset;
        uint256 borrowQuantityUnits;
        uint256 minReceiveQuantityUnits;
        string tradeAdapterName;
        bytes tradeData;
        uint256 signatureExpiry;
        bytes permitSignature;
    }

    struct DeLeverInfo {
        IERC20 collateralAsset;
        IERC20 repayAsset;
        uint256 redeemQuantityUnits;
        uint256 minRepayQuantityUnits;
        string tradeAdapterName;
        bytes tradeData;
    }

    /* ============ State Variables ============ */

    // Instance of LeverageModule
    ILeverageModuleV2 public immutable leverageModule;
    ISignalSuscriptionModule public immutable signalSuscriptionModule;

    /* ============ Constructor ============ */

    /**
     * Instantiate with ManagerCore address and LeverageModule address.
     *
     * @param _managerCore              Address of ManagerCore contract
     * @param _leverageModule               Address of leverageModule contract
     */
    constructor(
        IManagerCore _managerCore,
        ILeverageModuleV2 _leverageModule,
        ISignalSuscriptionModule _signalSuscriptionModule
    ) public BaseGlobalExtension(_managerCore) {
        leverageModule = _leverageModule;
        signalSuscriptionModule = _signalSuscriptionModule;
    }

    /* ============ External Functions ============ */

    /**
     * ONLY OWNER: Initializes LeverageModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the LeverageModule for
     */
    function initializeModule(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        _initializeModule(_delegatedManager.jasperVault(), _delegatedManager);
    }

    /**
     * ONLY OWNER: Initializes WrapExtension to the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeExtension(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        emit LeverageExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    /**
     * ONLY OWNER: Initializes WrapExtension to the DelegatedManager and TradeModule to the JasperVault
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeModuleAndExtension(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);
        _initializeModule(jasperVault, _delegatedManager);

        emit LeverageExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    /**
     * ONLY MANAGER: Remove an existing JasperVault and DelegatedManager tracked by the WrapExtension
     */
    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();

        _removeExtension(jasperVault, delegatedManager);
    }

    function borrow(
        IJasperVault _jasperVault,
        IERC20 _borrowAsset,
        uint256 _borrowQuantityUnits,
        LeverageProtocol _aaveV3OrSpark // * enum value is checked in module to determine which Pool to interact with
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(_borrowAsset))
    {
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.borrow.selector,
            _jasperVault,
            _borrowAsset,
            _borrowQuantityUnits,
            _aaveV3OrSpark
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
    }

    function repay(
        IJasperVault _jasperVault,
        IERC20 _repayAsset,
        uint256 _redeemQuantityUnits,
        bool _isAllRepay
    )
        external
        // * could add a flag/Enum value here which indicates whether it's AaveV3's Pool contract or Spark's Pool contract we want to do this on
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(_repayAsset))
    {
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.repay.selector,
            _jasperVault,
            _repayAsset,
            _redeemQuantityUnits,
            _isAllRepay
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
    }

    function repayWithPermit(
        IJasperVault _jasperVault,
        IERC20 _repayAsset,
        uint256 _redeemQuantityUnits,
        bool _isAllRepay,
        bytes memory _permitDetails
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(_repayAsset))
    {
        (uint256 signatureExpiry, bytes memory permitSignature) = abi.decode(
            _permitDetails,
            (uint256, bytes)
        );
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.repayWithPermit.selector,
            _jasperVault,
            _repayAsset,
            _redeemQuantityUnits,
            _isAllRepay,
            signatureExpiry,
            permitSignature
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
    }

    function repayWithATokens(
        IJasperVault _jasperVault,
        IERC20 _repayAsset,
        uint256 _redeemQuantityUnits,
        bool _isAllRepay
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(_repayAsset))
    {
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.repayWithATokens.selector,
            _jasperVault,
            _repayAsset,
            _redeemQuantityUnits,
            _isAllRepay
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
    }

    function lever(
        IJasperVault _jasperVault,
        LeverInfo memory _leverInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(leverageModule),
            _leverInfo.tradeAdapterName
        )
    {
        ValidAssetsByModule(
            _jasperVault,
            address(_leverInfo.borrowAsset),
            address(_leverInfo.collateralAsset)
        );
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.lever.selector,
            _jasperVault,
            _leverInfo.borrowAsset,
            _leverInfo.collateralAsset,
            _leverInfo.borrowQuantityUnits,
            _leverInfo.minReceiveQuantityUnits,
            _leverInfo.tradeAdapterName,
            _leverInfo.tradeData
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
    }

    function leverWithPermit(
        IJasperVault _jasperVault,
        LeverWithPermitInfo memory _leverWithPermitInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(leverageModule),
            _leverWithPermitInfo.tradeAdapterName
        )
    {
        ValidAssetsByModule(
            _jasperVault,
            address(_leverWithPermitInfo.borrowAsset),
            address(_leverWithPermitInfo.collateralAsset)
        );
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.leverWithPermit.selector,
            _jasperVault,
            _leverWithPermitInfo.borrowAsset,
            _leverWithPermitInfo.collateralAsset,
            _leverWithPermitInfo.borrowQuantityUnits,
            _leverWithPermitInfo.minReceiveQuantityUnits,
            _leverWithPermitInfo.tradeAdapterName,
            _leverWithPermitInfo.tradeData,
            _leverWithPermitInfo.signatureExpiry,
            _leverWithPermitInfo.permitSignature
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
    }

    function delever(
        IJasperVault _jasperVault,
        DeLeverInfo memory _deLeverInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(leverageModule),
            _deLeverInfo.tradeAdapterName
        )
    {
        ValidAssetsByModule(
            _jasperVault,
            address(_deLeverInfo.collateralAsset),
            address(_deLeverInfo.repayAsset)
        );
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.delever.selector,
            _jasperVault,
            _deLeverInfo.collateralAsset,
            _deLeverInfo.repayAsset,
            _deLeverInfo.redeemQuantityUnits,
            _deLeverInfo.minRepayQuantityUnits,
            _deLeverInfo.tradeAdapterName,
            _deLeverInfo.tradeData
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
    }

    function deleverToZeroBorrowBalance(
        IJasperVault _jasperVault,
        DeLeverInfo memory _deLeverInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(leverageModule),
            _deLeverInfo.tradeAdapterName
        )
    {
        ValidAssetsByModule(
            _jasperVault,
            address(_deLeverInfo.collateralAsset),
            address(_deLeverInfo.repayAsset)
        );
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.deleverToZeroBorrowBalance.selector,
            _jasperVault,
            _deLeverInfo.collateralAsset,
            _deLeverInfo.repayAsset,
            _deLeverInfo.redeemQuantityUnits,
            _deLeverInfo.tradeAdapterName,
            _deLeverInfo.tradeData
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
    }

    function borrowFollowers(
        IJasperVault _jasperVault,
        IERC20 _borrowAsset,
        uint256 _borrowQuantityUnits
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(_borrowAsset))
    {
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.borrow.selector,
            _jasperVault,
            _borrowAsset,
            _borrowQuantityUnits
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            callData = abi.encodeWithSelector(
                ILeverageModuleV2.borrow.selector,
                IJasperVault(followers[i]),
                _borrowAsset,
                _borrowQuantityUnits
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(leverageModule),
                callData
            );
        }
        callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(
            _manager(_jasperVault),
            address(signalSuscriptionModule),
            callData
        );
    }

    // todo: consider whether or not to implement repayWithATokensFollowers
    function repayFollowers(
        IJasperVault _jasperVault,
        IERC20 _repayAsset,
        uint256 _redeemQuantityUnits,
        bool _isAllRepay
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(_repayAsset))
    {
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.repay.selector,
            _jasperVault,
            _repayAsset,
            _redeemQuantityUnits,
            _isAllRepay
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );

        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            callData = abi.encodeWithSelector(
                ILeverageModuleV2.repay.selector,
                IJasperVault(followers[i]),
                _repayAsset,
                _redeemQuantityUnits,
                _isAllRepay
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(leverageModule),
                callData
            );
        }
        callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(
            _manager(_jasperVault),
            address(signalSuscriptionModule),
            callData
        );
    }

    function leverFollowers(
        IJasperVault _jasperVault,
        LeverInfo memory _leverInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(leverageModule),
            _leverInfo.tradeAdapterName
        )
    {
        ValidAssetsByModule(
            _jasperVault,
            address(_leverInfo.borrowAsset),
            address(_leverInfo.collateralAsset)
        );
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.lever.selector,
            _jasperVault,
            _leverInfo.borrowAsset,
            _leverInfo.collateralAsset,
            _leverInfo.borrowQuantityUnits,
            _leverInfo.minReceiveQuantityUnits,
            _leverInfo.tradeAdapterName,
            _leverInfo.tradeData
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
        _executeFollower(
            ILeverageModuleV2.lever.selector,
            _jasperVault,
            _leverInfo.borrowAsset,
            _leverInfo.collateralAsset,
            _leverInfo.borrowQuantityUnits,
            _leverInfo.minReceiveQuantityUnits,
            _leverInfo.tradeAdapterName,
            _leverInfo.tradeData
        );

        callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(
            _manager(_jasperVault),
            address(signalSuscriptionModule),
            callData
        );
    }

    function deleverFollowers(
        IJasperVault _jasperVault,
        DeLeverInfo memory _deLeverInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(leverageModule),
            _deLeverInfo.tradeAdapterName
        )
    {
        ValidAssetsByModule(
            _jasperVault,
            address(_deLeverInfo.collateralAsset),
            address(_deLeverInfo.repayAsset)
        );
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.delever.selector,
            _jasperVault,
            _deLeverInfo.collateralAsset,
            _deLeverInfo.repayAsset,
            _deLeverInfo.redeemQuantityUnits,
            _deLeverInfo.minRepayQuantityUnits,
            _deLeverInfo.tradeAdapterName,
            _deLeverInfo.tradeData
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
        _executeFollower(
            ILeverageModuleV2.delever.selector,
            _jasperVault,
            _deLeverInfo.collateralAsset,
            _deLeverInfo.repayAsset,
            _deLeverInfo.redeemQuantityUnits,
            _deLeverInfo.minRepayQuantityUnits,
            _deLeverInfo.tradeAdapterName,
            _deLeverInfo.tradeData
        );
        callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(
            _manager(_jasperVault),
            address(signalSuscriptionModule),
            callData
        );
    }

    function _executeFollower(
        bytes4 selector,
        IJasperVault _jasperVault,
        IERC20 _assetsOne,
        IERC20 _assetsTwo,
        uint256 _quantityUnits,
        uint256 _minQuantityUnits,
        string memory _tradeAdapterName,
        bytes memory _tradeData
    ) internal {
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                selector,
                IJasperVault(followers[i]),
                _assetsOne,
                _assetsTwo,
                _quantityUnits,
                _minQuantityUnits,
                _tradeAdapterName,
                _tradeData
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(leverageModule),
                callData
            );
        }
    }

    function deleverToZeroBorrowBalanceFollowers(
        IJasperVault _jasperVault,
        DeLeverInfo memory _deLeverInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(
            _jasperVault,
            address(leverageModule),
            _deLeverInfo.tradeAdapterName
        )
    {
        ValidAssetsByModule(
            _jasperVault,
            address(_deLeverInfo.collateralAsset),
            address(_deLeverInfo.repayAsset)
        );
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.deleverToZeroBorrowBalance.selector,
            _jasperVault,
            _deLeverInfo.collateralAsset,
            _deLeverInfo.repayAsset,
            _deLeverInfo.redeemQuantityUnits,
            _deLeverInfo.tradeAdapterName,
            _deLeverInfo.tradeData
        );
        _invokeManager(
            _manager(_jasperVault),
            address(leverageModule),
            callData
        );
        _executeDeleverToZeroFollower(
            _jasperVault,
            _deLeverInfo.collateralAsset,
            _deLeverInfo.repayAsset,
            _deLeverInfo.redeemQuantityUnits,
            _deLeverInfo.tradeAdapterName,
            _deLeverInfo.tradeData
        );
        callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(
            _manager(_jasperVault),
            address(signalSuscriptionModule),
            callData
        );
    }

    function _executeDeleverToZeroFollower(
        IJasperVault _jasperVault,
        IERC20 _collateralAsset,
        IERC20 _repayAsset,
        uint256 _redeemQuantityUnits,
        string memory _tradeAdapterName,
        bytes memory _tradeData
    ) internal {
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                ILeverageModuleV2.deleverToZeroBorrowBalance.selector,
                IJasperVault(followers[i]),
                _collateralAsset,
                _repayAsset,
                _redeemQuantityUnits,
                _tradeAdapterName,
                _tradeData
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(leverageModule),
                callData
            );
        }
    }

    /* ============ Internal Functions ============ */
    function _execute(
        IDelegatedManager manager,
        address module,
        bytes memory callData
    ) internal {
        try manager.interactManager(module, callData) {} catch Error(
            string memory reason
        ) {
            emit InvokeFail(address(manager), module, reason, callData);
        }
    }

    /**
     * Internal function to initialize LeverageModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the LeverageModule for
     */
    function _initializeModule(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager
    ) internal {
        bytes memory callData = abi.encodeWithSelector(
            ILeverageModuleV2.initialize.selector,
            _jasperVault
        );
        _invokeManager(_delegatedManager, address(leverageModule), callData);
    }
}
