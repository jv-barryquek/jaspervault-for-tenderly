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
import { IJasperVault } from "../../interfaces/IJasperVault.sol";
import { ITradeModule } from "../../interfaces/ITradeModule.sol";

import { BaseGlobalExtension } from "../lib/BaseGlobalExtension.sol";
import { IDelegatedManager } from "../interfaces/IDelegatedManager.sol";
import { IManagerCore } from "../interfaces/IManagerCore.sol";
/**
 * @title TradeExtension
 * @author Set Protocol
 *
 * Smart contract global extension which provides DelegatedManager privileged operator(s) the ability to trade on a DEX
 * and the owner the ability to restrict operator(s) permissions with an asset whitelist.
 */
contract TradeExtension is BaseGlobalExtension {
    struct TradeInfo {
        string exchangeName;             // Human readable name of the exchange in the integrations registry
        address sendToken;               // Address of the token to be sent to the exchange
        int256 sendQuantity;            // Max units of `sendToken` sent to the exchange
        address receiveToken;            // Address of the token that will be received from the exchange
        uint256 minReceiveQuantity;         // Min units of `receiveToken` to be received from the exchange
        bytes data;                      // Arbitrary bytes to be used to construct trade call data
    }
    /* ============ Events ============ */
    event TradeExtensionInitialized(
        address indexed _jasperVault,
        address indexed _delegatedManager
    );

    /* ============ State Variables ============ */

    // Instance of TradeModule
    ITradeModule public immutable tradeModule;

    /* ============ Constructor ============ */

    constructor(
        IManagerCore _managerCore,
        ITradeModule _tradeModule
    )
        public
        BaseGlobalExtension(_managerCore)
    {
        tradeModule = _tradeModule;
    }

    /* ============ External Functions ============ */

    /**
     * ONLY OWNER: Initializes TradeModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the TradeModule for
     */
    function initializeModule(IDelegatedManager _delegatedManager) external onlyOwnerAndValidManager(_delegatedManager) {
        require(_delegatedManager.isInitializedExtension(address(this)), "Extension must be initialized");

        _initializeModule(_delegatedManager.jasperVault(), _delegatedManager);
    }

    /**
     * ONLY OWNER: Initializes TradeExtension to the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeExtension(IDelegatedManager _delegatedManager) external onlyOwnerAndValidManager(_delegatedManager) {
        require(_delegatedManager.isPendingExtension(address(this)), "Extension must be pending");

        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        emit TradeExtensionInitialized(address(jasperVault), address(_delegatedManager));
    }

    /**
     * ONLY OWNER: Initializes TradeExtension to the DelegatedManager and TradeModule to the JasperVault
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeModuleAndExtension(IDelegatedManager _delegatedManager) external onlyOwnerAndValidManager(_delegatedManager){
        require(_delegatedManager.isPendingExtension(address(this)), "Extension must be pending");

        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);
        _initializeModule(jasperVault, _delegatedManager);

        emit TradeExtensionInitialized(address(jasperVault), address(_delegatedManager));
    }

    /**
     * ONLY MANAGER: Remove an existing JasperVault and DelegatedManager tracked by the TradeExtension
     */
    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();

        _removeExtension(jasperVault, delegatedManager);
    }


    function trade(
        IJasperVault _jasperVault,
        TradeInfo memory _tradeInfo
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        onlyAllowedAsset(_jasperVault, _tradeInfo.receiveToken)
        ValidAdapter(_jasperVault,address(tradeModule),_tradeInfo.exchangeName)
    {
        bytes memory callData = abi.encodeWithSignature(
            "trade(address,string,address,int256,address,uint256,bytes)",
            _jasperVault,
            _tradeInfo.exchangeName,
            _tradeInfo.sendToken,
            _tradeInfo.sendQuantity,
            _tradeInfo.receiveToken,
            _tradeInfo.minReceiveQuantity,
            _tradeInfo.data
        );
        _invokeManager(_manager(_jasperVault), address(tradeModule), callData);
    }
    /* ============ Internal Functions ============ */

    /**
     * Internal function to initialize TradeModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the TradeModule for
     */
    function _initializeModule(IJasperVault _jasperVault, IDelegatedManager _delegatedManager) internal {
        bytes memory callData = abi.encodeWithSignature("initialize(address)", _jasperVault);
        _invokeManager(_delegatedManager, address(tradeModule), callData);
    }
}
