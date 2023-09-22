/*
    Copyright 2022 Set Labs Inc.

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
import { IERC777 } from "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IController } from "../../../interfaces/IController.sol";
import { IDebtIssuanceModule } from "../../../interfaces/IDebtIssuanceModule.sol";
import { IModuleIssuanceHook } from "../../../interfaces/IModuleIssuanceHook.sol";
import { IWrappedfCash, IWrappedfCashComplete } from "../../../interfaces/IWrappedFCash.sol";
import { IWrappedfCashFactory } from "../../../interfaces/IWrappedFCashFactory.sol";
import { IJasperVault } from "../../../interfaces/IJasperVault.sol";
import { ModuleBase } from "../../lib/ModuleBase.sol";



/**
 * @title NotionalTradeModule
 * @author Set Protocol
 * @notice Smart contract that enables trading in and out of Notional fCash positions and redeem matured positions.
 * @dev This module depends on the wrappedFCash erc20-token-wrapper. Meaning positions managed with this module have to be in the form of wrappedfCash NOT fCash directly.
 */
contract NotionalTradeModule is ModuleBase, ReentrancyGuard, Ownable, IModuleIssuanceHook {
    using Address for address;

    // This value has to be the same as the one used in wrapped-fcash Constants
    address internal constant ETH_ADDRESS = address(0);

    /* ============ Events ============ */

    /**
     * @dev Emitted on updateAnySetAllowed()
     * @param _anySetAllowed    true if any set is allowed to initialize this module, false otherwise
     */
    event AnySetAllowedUpdated(
        bool indexed _anySetAllowed
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
     * @dev Emitted when minting new FCash
     * @param _jasperVault         JasperVault on whose behalf fcash was minted
     * @param _fCashPosition    Address of wrappedFCash token
     * @param _sendToken        Address of send token used to pay for minting
     * @param _fCashAmount      Amount of fCash minted
     * @param _sentAmount       Amount of sendToken spent
     */
    event FCashMinted(
        IJasperVault indexed _jasperVault,
        IWrappedfCashComplete indexed _fCashPosition,
        IERC20 indexed _sendToken,
        uint256 _fCashAmount,
        uint256 _sentAmount
    );

    /**
     * @dev Emitted when redeeming new FCash
     * @param _jasperVault         JasperVault on whose behalf fcash was redeemed
     * @param _fCashPosition    Address of wrappedFCash token
     * @param _receiveToken     Address of receive token used to pay for redeeming
     * @param _fCashAmount      Amount of fCash redeemed / burned
     * @param _receivedAmount   Amount of receiveToken received
     */
    event FCashRedeemed(
        IJasperVault indexed _jasperVault,
        IWrappedfCashComplete indexed _fCashPosition,
        IERC20 indexed _receiveToken,
        uint256 _fCashAmount,
        uint256 _receivedAmount
    );


    /* ============ Constants ============ */

    // String identifying the DebtIssuanceModule in the IntegrationRegistry. Note: Governance must add DefaultIssuanceModule as
    // the string as the integration name
    string constant internal DEFAULT_ISSUANCE_MODULE_NAME = "DefaultIssuanceModule";

    /* ============ State Variables ============ */

    // Mapping for a set token, wether or not to redeem to underlying upon reaching maturity
    mapping(IJasperVault => bool) public redeemToUnderlying;

    // Mapping of JasperVault to boolean indicating if JasperVault is on allow list. Updateable by governance
    mapping(IJasperVault => bool) public allowedSetTokens;

    // Boolean that returns if any JasperVault can initialize this module. If false, then subject to allow list. Updateable by governance.
    bool public anySetAllowed;

    // Factory that is used to deploy and check fCash wrapper contracts
    IWrappedfCashFactory public immutable wrappedfCashFactory;
    IERC20 public immutable weth;

    /* ============ Constructor ============ */

    /**
     * @dev Instantiate addresses
     * @param _controller                       Address of controller contract
     * @param _wrappedfCashFactory              Address of fCash wrapper factory used to check and deploy wrappers
     */
    constructor(
        IController _controller,
        IWrappedfCashFactory _wrappedfCashFactory,
        IERC20 _weth

    )
        public
        ModuleBase(_controller)
    {
        wrappedfCashFactory = _wrappedfCashFactory;
        weth = _weth;
    }

    /* ============ External Functions ============ */


    /**
     * @dev MANAGER ONLY: Trades into a new fCash position.
     * @param _jasperVault                   Instance of the JasperVault
     * @param _currencyId                 CurrencyId of the fCash token as defined by the notional protocol.
     * @param _maturity                   Maturity of the fCash token as defined by the notional protocol.
     * @param _mintAmount                 Amount of fCash token to mint
     * @param _sendToken                  Token to mint from, must be either the underlying or the asset token.
     * @param _maxSendAmount              Maximum amount to spend
     */
    function mintFCashPosition(
        IJasperVault _jasperVault,
        uint16 _currencyId,
        uint40 _maturity,
        uint256 _mintAmount,
        address _sendToken,
        uint256 _maxSendAmount
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
        returns(uint256)
    {
        require(_jasperVault.isComponent(address(_sendToken)), "Send token must be an index component");

        IWrappedfCashComplete wrappedfCash = _deployWrappedfCash(_currencyId, _maturity);
        return _mintFCashPosition(_jasperVault, wrappedfCash, IERC20(_sendToken), _mintAmount, _maxSendAmount);
    }

    /**
     * @dev MANAGER ONLY: Trades out of an existing fCash position.
     * Will revert if no wrapper for the selected fCash token was deployed
     * @param _jasperVault                   Instance of the JasperVault
     * @param _currencyId                 CurrencyId of the fCash token as defined by the notional protocol.
     * @param _maturity                   Maturity of the fCash token as defined by the notional protocol.
     * @param _redeemAmount               Amount of fCash token to redeem
     * @param _receiveToken               Token to redeem into, must be either asset or underlying token of the fCash token
     * @param _minReceiveAmount           Minimum amount of receive token to receive
     */
    function redeemFCashPosition(
        IJasperVault _jasperVault,
        uint16 _currencyId,
        uint40 _maturity,
        uint256 _redeemAmount,
        address _receiveToken,
        uint256 _minReceiveAmount
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
        returns(uint256)
    {
        IWrappedfCashComplete wrappedfCash = _getWrappedfCash(_currencyId, _maturity);
        require(_jasperVault.isComponent(address(wrappedfCash)), "FCash to redeem must be an index component");

        return _redeemFCashPosition(_jasperVault, wrappedfCash, IERC20(_receiveToken), _redeemAmount, _minReceiveAmount);
    }

    /**
     * @dev CALLABLE BY ANYBODY: Redeem all matured fCash positions of given jasperVault
     * Redeem all fCash positions that have reached maturity for their asset token (cToken)
     * This will update the set tokens components and positions (removes matured fCash positions and creates / increases positions of the asset token).
     * @param _jasperVault                     Instance of the JasperVault
     */
    function redeemMaturedPositions(IJasperVault _jasperVault) public nonReentrant onlyValidAndInitializedSet(_jasperVault) {
        _redeemMaturedPositions(_jasperVault);
    }

    /**
     * @dev MANGER ONLY: Initialize given JasperVault with initial list of registered fCash positions
     * Redeem all fCash positions that have reached maturity for their asset token (cToken)
     * @param _jasperVault                     Instance of the JasperVault
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
        require(_jasperVault.isInitializedModule(getAndValidateAdapter(DEFAULT_ISSUANCE_MODULE_NAME)), "Issuance not initialized");

        // Try if register exists on any of the modules including the debt issuance module
        address[] memory modules = _jasperVault.getModules();
        for(uint256 i = 0; i < modules.length; i++) {
            try IDebtIssuanceModule(modules[i]).registerToIssuanceModule(_jasperVault) {} catch {}
        }
    }

    /**
     * @dev MANAGER ONLY: Removes this module from the JasperVault, via call by the JasperVault. Redeems any matured positions
     */
    function removeModule() external override onlyValidAndInitializedSet(IJasperVault(msg.sender)) {
        IJasperVault jasperVault = IJasperVault(msg.sender);

        // Redeem matured positions prior to any removal action
        _redeemMaturedPositions(jasperVault);

        // Try if unregister exists on any of the modules
        address[] memory modules = jasperVault.getModules();
        for(uint256 i = 0; i < modules.length; i++) {
            if(modules[i].isContract()){
                try IDebtIssuanceModule(modules[i]).unregisterFromIssuanceModule(jasperVault) {} catch {}
            }
        }
    }

    /**
     * @dev MANAGER ONLY: Add registration of this module on the debt issuance module for the JasperVault.
     * Note: if the debt issuance module is not added to JasperVault before this module is initialized, then this function
     * needs to be called if the debt issuance module is later added and initialized to prevent state inconsistencies
     * @param _jasperVault             Instance of the JasperVault
     * @param _debtIssuanceModule   Debt issuance module address to register
     */
    function registerToModule(IJasperVault _jasperVault, IDebtIssuanceModule _debtIssuanceModule) external onlyManagerAndValidSet(_jasperVault) {
        require(_jasperVault.isInitializedModule(address(_debtIssuanceModule)), "Issuance not initialized");

        _debtIssuanceModule.registerToIssuanceModule(_jasperVault);
    }

    /**
     * @dev GOVERNANCE ONLY: Enable/disable ability of a JasperVault to initialize this module. Only callable by governance.
     * @param _jasperVault             Instance of the JasperVault
     * @param _status               Bool indicating if _jasperVault is allowed to initialize this module
     */
    function updateAllowedSetToken(IJasperVault _jasperVault, bool _status) external onlyOwner {
        require(controller.isSet(address(_jasperVault)) || allowedSetTokens[_jasperVault], "Invalid JasperVault");
        allowedSetTokens[_jasperVault] = _status;
        emit SetTokenStatusUpdated(_jasperVault, _status);
    }

    /**
     * @dev GOVERNANCE ONLY: Toggle whether ANY JasperVault is allowed to initialize this module. Only callable by governance.
     * @param _anySetAllowed             Bool indicating if ANY JasperVault is allowed to initialize this module
     */
    function updateAnySetAllowed(bool _anySetAllowed) external onlyOwner {
        anySetAllowed = _anySetAllowed;
        emit AnySetAllowedUpdated(_anySetAllowed);
    }

    function setRedeemToUnderlying(
        IJasperVault _jasperVault,
        bool _toUnderlying
    )
    external
    onlyManagerAndValidSet(_jasperVault)
    {
        redeemToUnderlying[_jasperVault] = _toUnderlying;
    }


    /**
     * @dev Hook called once before jasperVault issuance
     * @dev Ensures that no matured fCash positions are in the set when it is issued
     */
    function moduleIssueHook(IJasperVault _jasperVault, uint256 /* _setTokenAmount */) external override onlyModule(_jasperVault) {
        _redeemMaturedPositions(_jasperVault);
    }

    /**
     * @dev Hook called once before jasperVault redemption
     * @dev Ensures that no matured fCash positions are in the set when it is redeemed
     */
    function moduleRedeemHook(IJasperVault _jasperVault, uint256 /* _setTokenAmount */) external override onlyModule(_jasperVault) {
        _redeemMaturedPositions(_jasperVault);
    }


    /**
     * @dev Hook called once for each component upon jasperVault issuance
     * @dev Empty method added to satisfy IModuleIssuanceHook interface
     */
    function componentIssueHook(
        IJasperVault _jasperVault,
        uint256 _setTokenAmount,
        IERC20 _component,
        bool _isEquity
    ) external override onlyModule(_jasperVault) {
    }

    /**
     * @dev Hook called once for each component upon jasperVault redemption
     * @dev Empty method added to satisfy IModuleIssuanceHook interface
     */
    function componentRedeemHook(
        IJasperVault _jasperVault,
        uint256 _setTokenAmount,
        IERC20 _component,
        bool _isEquity
    ) external override onlyModule(_jasperVault) {
    }




    /* ============ External Getter Functions ============ */

    /**
     * @dev Get array of registered fCash positions
     * @param _jasperVault             Instance of the JasperVault
     */
    function getFCashPositions(IJasperVault _jasperVault)
    external
    view
    returns(address[] memory positions)
    {
        return _getFCashPositions(_jasperVault);
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev Deploy wrapper if it does not exist yet and return address
     */
    function _deployWrappedfCash(uint16 _currencyId, uint40 _maturity) internal returns(IWrappedfCashComplete) {
        address wrappedfCashAddress = wrappedfCashFactory.deployWrapper(_currencyId, _maturity);
        return IWrappedfCashComplete(wrappedfCashAddress);
    }

    /**
     * @dev Return wrapper address and revert if it isn't deployed
     */
    function _getWrappedfCash(uint16 _currencyId, uint40 _maturity) internal view returns(IWrappedfCashComplete) {
        address wrappedfCashAddress = wrappedfCashFactory.computeAddress(_currencyId, _maturity);
        require(wrappedfCashAddress.isContract(), "WrappedfCash not deployed for given parameters");
        return IWrappedfCashComplete(wrappedfCashAddress);
    }

    /**
     * @dev Redeem all matured fCash positions for the given JasperVault
     */
    function _redeemMaturedPositions(IJasperVault _jasperVault)
    internal
    {
        IJasperVault.Position[] memory positions = _jasperVault.getPositions();
        uint positionsLength = positions.length;

        bool toUnderlying = redeemToUnderlying[_jasperVault];

        for(uint256 i = 0; i < positionsLength; i++) {
            // Check that the given position is an equity position
            if(positions[i].unit > 0) {
                address component = positions[i].component;
                if(_isWrappedFCash(component)) {
                    IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(component);
                    if(fCashPosition.hasMatured()) {
                        (IERC20 receiveToken,) = fCashPosition.getToken(toUnderlying);
                        if(address(receiveToken) == ETH_ADDRESS) {
                            receiveToken = weth;
                        }
                        uint256 fCashBalance = fCashPosition.balanceOf(address(_jasperVault));
                        _redeemFCashPosition(_jasperVault, fCashPosition, receiveToken, fCashBalance, 0);
                    }
                }
            }
        }
    }



    /**
     * @dev Redeem a given fCash position from the specified send token (either underlying or asset token)
     * @dev Alo adjust the components / position of the set token accordingly
     */
    function _mintFCashPosition(
        IJasperVault _jasperVault,
        IWrappedfCashComplete _fCashPosition,
        IERC20 _sendToken,
        uint256 _fCashAmount,
        uint256 _maxSendAmount
    )
    internal
    returns(uint256 sentAmount)
    {
        if(_fCashAmount == 0) return 0;

        bool fromUnderlying = _isUnderlying(_fCashPosition, _sendToken);


        _approve(_jasperVault, _fCashPosition, _sendToken, _maxSendAmount);

        uint256 preTradeSendTokenBalance = _sendToken.balanceOf(address(_jasperVault));
        uint256 preTradeReceiveTokenBalance = _fCashPosition.balanceOf(address(_jasperVault));

        _mint(_jasperVault, _fCashPosition, _maxSendAmount, _fCashAmount, fromUnderlying);


        (sentAmount,) = _updateSetTokenPositions(
            _jasperVault,
            address(_sendToken),
            preTradeSendTokenBalance,
            address(_fCashPosition),
            preTradeReceiveTokenBalance
        );

        require(sentAmount <= _maxSendAmount, "Overspent");
        emit FCashMinted(_jasperVault, _fCashPosition, _sendToken, _fCashAmount, sentAmount);
    }

    /**
     * @dev Redeem a given fCash position for the specified receive token (either underlying or asset token)
     * @dev Alo adjust the components / position of the set token accordingly
     */
    function _redeemFCashPosition(
        IJasperVault _jasperVault,
        IWrappedfCashComplete _fCashPosition,
        IERC20 _receiveToken,
        uint256 _fCashAmount,
        uint256 _minReceiveAmount
    )
    internal
    returns(uint256 receivedAmount)
    {
        if(_fCashAmount == 0) return 0;

        bool toUnderlying = _isUnderlying(_fCashPosition, _receiveToken);
        uint256 preTradeReceiveTokenBalance = _receiveToken.balanceOf(address(_jasperVault));
        uint256 preTradeSendTokenBalance = _fCashPosition.balanceOf(address(_jasperVault));

        _redeem(_jasperVault, _fCashPosition, _fCashAmount, toUnderlying);


        (, receivedAmount) = _updateSetTokenPositions(
            _jasperVault,
            address(_fCashPosition),
            preTradeSendTokenBalance,
            address(_receiveToken),
            preTradeReceiveTokenBalance
        );


        require(receivedAmount >= _minReceiveAmount, "Not enough received amount");
        emit FCashRedeemed(_jasperVault, _fCashPosition, _receiveToken, _fCashAmount, receivedAmount);

    }

    /**
     * @dev Approve the given wrappedFCash instance to spend the jasperVault's sendToken
     */
    function _approve(
        IJasperVault _jasperVault,
        IWrappedfCashComplete _fCashPosition,
        IERC20 _sendToken,
        uint256 _maxAssetAmount
    )
    internal
    {
        if(IERC20(_sendToken).allowance(address(_jasperVault), address(_fCashPosition)) < _maxAssetAmount) {
            bytes memory approveCallData = abi.encodeWithSelector(_sendToken.approve.selector, address(_fCashPosition), _maxAssetAmount);
            _jasperVault.invoke(address(_sendToken), 0, approveCallData);
        }
    }

    /**
     * @dev Invokes the wrappedFCash token's mint function from the jasperVault
     */
    function _mint(
        IJasperVault _jasperVault,
        IWrappedfCashComplete _fCashPosition,
        uint256 _maxAssetAmount,
        uint256 _fCashAmount,
        bool _fromUnderlying
    )
    internal
    {
        uint32 minImpliedRate = 0;

        bytes4 functionSelector =
            _fromUnderlying ? _fCashPosition.mintViaUnderlying.selector : _fCashPosition.mintViaAsset.selector;
        bytes memory mintCallData = abi.encodeWithSelector(
            functionSelector,
            _maxAssetAmount,
            uint88(_fCashAmount),
            address(_jasperVault),
            minImpliedRate,
            _fromUnderlying
        );
        _jasperVault.invoke(address(_fCashPosition), 0, mintCallData);
    }

    /**
     * @dev Redeems the given amount of fCash token on behalf of the jasperVault
     */
    function _redeem(
        IJasperVault _jasperVault,
        IWrappedfCashComplete _fCashPosition,
        uint256 _fCashAmount,
        bool _toUnderlying
    )
    internal
    {
        uint32 maxImpliedRate = type(uint32).max;

        bytes4 functionSelector =
            _toUnderlying ? _fCashPosition.redeemToUnderlying.selector : _fCashPosition.redeemToAsset.selector;
        bytes memory redeemCallData = abi.encodeWithSelector(
            functionSelector,
            _fCashAmount,
            address(_jasperVault),
            maxImpliedRate
        );
        _jasperVault.invoke(address(_fCashPosition), 0, redeemCallData);
    }

    /**
     * @dev Returns boolean indicating if given paymentToken is the underlying of the given fCashPosition
     * @dev Reverts if given token is neither underlying nor asset token of the fCashPosition
     */
    function _isUnderlying(
        IWrappedfCashComplete _fCashPosition,
        IERC20 _paymentToken
    )
    internal
    view
    returns(bool isUnderlying)
    {
        (IERC20 underlyingToken, IERC20 assetToken) = _getUnderlyingAndAssetTokens(_fCashPosition);
        isUnderlying = _paymentToken == underlyingToken;
        if(!isUnderlying) {
            require(_paymentToken == assetToken, "Token is neither asset nor underlying token");
        }
    }


    /**
     * @dev Returns both underlying and asset token address for given fCash position
     */
    function _getUnderlyingAndAssetTokens(IWrappedfCashComplete _fCashPosition)
    internal
    view
    returns(IERC20 underlyingToken, IERC20 assetToken)
    {
        (underlyingToken,) = _fCashPosition.getUnderlyingToken();
        if(address(underlyingToken) == ETH_ADDRESS) {
            underlyingToken = weth;
        }
        (assetToken,,) = _fCashPosition.getAssetToken();
    }

    /**
     * @dev Returns an array with fcash position addresses for given set token
     */
    function _getFCashPositions(IJasperVault _jasperVault)
    internal
    view
    returns(address[] memory fCashPositions)
    {
        IJasperVault.Position[] memory positions = _jasperVault.getPositions();
        uint positionsLength = positions.length;
        uint numFCashPositions;

        for(uint256 i = 0; i < positionsLength; i++) {
            // Check that the given position is an equity position
            if(positions[i].unit > 0) {
                address component = positions[i].component;
                if(_isWrappedFCash(component)) {
                    numFCashPositions++;
                }
            }
        }

        fCashPositions = new address[](numFCashPositions);

        uint j;
        for(uint256 i = 0; i < positionsLength; i++) {
            if(positions[i].unit > 0) {
                address component = positions[i].component;
                if(_isWrappedFCash(component)) {
                    fCashPositions[j] = component;
                    j++;
                }
            }
        }
    }



    /**
     * @dev Checks if a given address is an fCash position that was deployed from the factory
     */
    function _isWrappedFCash(address _fCashPosition) internal view returns(bool){
        if(!_fCashPosition.isContract()) {
            return false;
        }

        try IWrappedfCash(_fCashPosition).getDecodedID() returns(uint16 _currencyId, uint40 _maturity){
            try wrappedfCashFactory.computeAddress(_currencyId, _maturity) returns(address _computedAddress){
                return _fCashPosition == _computedAddress;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    /**
     * @dev Update set token positions after mint or redeem
     * @dev WARNING: This function is largely copied from the trade module
     */
    function _updateSetTokenPositions(
        IJasperVault jasperVault,
        address sendToken,
        uint256 preTradeSendTokenBalance,
        address receiveToken,
        uint256 preTradeReceiveTokenBalance
    ) internal returns (uint256, uint256) {

        uint256 setTotalSupply = jasperVault.totalSupply();

        (uint256 currentSendTokenBalance,,) = jasperVault.calculateAndEditDefaultPosition(
            sendToken,
            setTotalSupply,
            preTradeSendTokenBalance
        );

        (uint256 currentReceiveTokenBalance,,) = jasperVault.calculateAndEditDefaultPosition(
            receiveToken,
            setTotalSupply,
            preTradeReceiveTokenBalance
        );

        return (
            preTradeSendTokenBalance.sub(currentSendTokenBalance),
            currentReceiveTokenBalance.sub(preTradeReceiveTokenBalance)
        );
    }
}
