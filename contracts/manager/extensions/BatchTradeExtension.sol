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
import { StringArrayUtils } from "@setprotocol/set-protocol-v2/contracts/lib/StringArrayUtils.sol";

import { BaseGlobalExtension } from "../lib/BaseGlobalExtension.sol";
import { IDelegatedManager } from "../interfaces/IDelegatedManager.sol";
import { IManagerCore } from "../interfaces/IManagerCore.sol";
/**
 * @title BatchTradeExtension
 * @author Set Protocol
 *
 * Smart contract global extension which provides DelegatedManager operator(s) the ability to execute a batch of trades
 * on a DEX and the owner the ability to restrict operator(s) permissions with an asset whitelist.
 */
contract BatchTradeExtension is BaseGlobalExtension {
    using StringArrayUtils for string[];

    /* ============ Structs ============ */

    struct TradeInfo {
        string exchangeName;             // Human readable name of the exchange in the integrations registry
        address sendToken;               // Address of the token to be sent to the exchange
        int256 sendQuantity;            // Max units of `sendToken` sent to the exchange
        address receiveToken;            // Address of the token that will be received from the exchange
        uint256 receiveQuantity;         // Min units of `receiveToken` to be received from the exchange
        bytes data;                      // Arbitrary bytes to be used to construct trade call data
    }

    /* ============ Events ============ */

    event IntegrationAdded(
        string _integrationName          // String name of TradeModule exchange integration to allow
    );

    event IntegrationRemoved(
        string _integrationName          // String name of TradeModule exchange integration to disallow
    );

    event BatchTradeExtensionInitialized(
        address indexed _jasperVault,                 // Address of the JasperVault which had BatchTradeExtension initialized on their manager
        address indexed _delegatedManager          // Address of the DelegatedManager which initialized the BatchTradeExtension
    );

    event StringTradeFailed(
        address indexed _jasperVault,       // Address of the JasperVault which the failed trade targeted
        uint256 indexed _index,          // Index of trade that failed in _trades parameter of batchTrade call
        string _reason,                  // String reason for the trade failure
        TradeInfo _tradeInfo             // Input TradeInfo of the failed trade
    );

    event BytesTradeFailed(
        address indexed _jasperVault,       // Address of the JasperVault which the failed trade targeted
        uint256 indexed _index,          // Index of trade that failed in _trades parameter of batchTrade call
        bytes _lowLevelData,             // Bytes low level data reason for the trade failure
        TradeInfo _tradeInfo             // Input TradeInfo of the failed trade
    );

    /* ============ State Variables ============ */

    // Instance of TradeModule
    ITradeModule public immutable tradeModule;

    // List of allowed TradeModule exchange integrations
    string[] public integrations;

    // Mapping to check whether string is allowed TradeModule exchange integration
    mapping(string => bool) public isIntegration;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the ManagerCore contract owner
     */
    modifier onlyManagerCoreOwner() {
        require(msg.sender == managerCore.owner(), "Caller must be ManagerCore owner");
        _;
    }

    /* ============ Constructor ============ */

    /**
     * Instantiate with ManagerCore address, TradeModule address, and allowed TradeModule integration strings.
     *
     * @param _managerCore              Address of ManagerCore contract
     * @param _tradeModule              Address of TradeModule contract
     * @param _integrations             List of TradeModule exchange integrations to allow
     */
    constructor(
        IManagerCore _managerCore,
        ITradeModule _tradeModule,
        string[] memory _integrations
    )
        public
        BaseGlobalExtension(_managerCore)
    {
        tradeModule = _tradeModule;

        integrations = _integrations;
        uint256 integrationsLength = _integrations.length;
        for (uint256 i = 0; i < integrationsLength; i++) {
            _addIntegration(_integrations[i]);
        }
    }

    /* ============ External Functions ============ */

    /**
     * MANAGER OWNER ONLY. Allows manager owner to add allowed TradeModule exchange integrations
     *
     * @param _integrations     List of TradeModule exchange integrations to allow
     */
    function addIntegrations(string[] memory _integrations) external onlyManagerCoreOwner {
        uint256 integrationsLength = _integrations.length;
        for (uint256 i = 0; i < integrationsLength; i++) {
            require(!isIntegration[_integrations[i]], "Integration already exists");

            integrations.push(_integrations[i]);

            _addIntegration(_integrations[i]);
        }
    }

    /**
     * MANAGER OWNER ONLY. Allows manager owner to remove allowed TradeModule exchange integrations
     *
     * @param _integrations     List of TradeModule exchange integrations to disallow
     */
    function removeIntegrations(string[] memory _integrations) external onlyManagerCoreOwner {
        uint256 integrationsLength = _integrations.length;
        for (uint256 i = 0; i < integrationsLength; i++) {
            require(isIntegration[_integrations[i]], "Integration does not exist");

            integrations.removeStorage(_integrations[i]);

            isIntegration[_integrations[i]] = false;

            IntegrationRemoved(_integrations[i]);
        }
    }

    /**
     * ONLY OWNER: Initializes TradeModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the TradeModule for
     */
    function initializeModule(IDelegatedManager _delegatedManager) external onlyOwnerAndValidManager(_delegatedManager) {
        _initializeModule(_delegatedManager.jasperVault(), _delegatedManager);
    }

    /**
     * ONLY OWNER: Initializes BatchTradeExtension to the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeExtension(IDelegatedManager _delegatedManager) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        emit BatchTradeExtensionInitialized(address(jasperVault), address(_delegatedManager));
    }

    /**
     * ONLY OWNER: Initializes BatchTradeExtension to the DelegatedManager and TradeModule to the JasperVault
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeModuleAndExtension(IDelegatedManager _delegatedManager) external onlyOwnerAndValidManager(_delegatedManager){
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);
        _initializeModule(jasperVault, _delegatedManager);

        emit BatchTradeExtensionInitialized(address(jasperVault), address(_delegatedManager));
    }

    /**
     * ONLY MANAGER: Remove an existing JasperVault and DelegatedManager tracked by the BatchTradeExtension
     */
    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();

        _removeExtension(jasperVault, delegatedManager);
    }

    /**
     * ONLY OPERATOR: Executes a batch of trades on a supported DEX. If any individual trades fail, events are emitted.
     * @dev Although the JasperVault units are passed in for the send and receive quantities, the total quantity
     * sent and received is the quantity of component units multiplied by the JasperVault totalSupply.
     *
     * @param _jasperVault             Instance of the JasperVault to trade
     * @param _trades               Array of TradeInfo structs containing information about trades
     */
    function batchTrade(
        IJasperVault _jasperVault,
        TradeInfo[] memory _trades
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
    {
        uint256 tradesLength = _trades.length;
        IDelegatedManager manager = _manager(_jasperVault);
        for(uint256 i = 0; i < tradesLength; i++) {

            require(isIntegration[_trades[i].exchangeName], "Must be allowed integration");
            if(_isPrimeMember(_jasperVault)){
              require(manager.isAllowedAsset(_trades[i].receiveToken), "Must be allowed asset");  
            }        
            bytes memory callData = abi.encodeWithSelector(
                ITradeModule.trade.selector,
                _jasperVault,
                _trades[i].exchangeName,
                _trades[i].sendToken,
                _trades[i].sendQuantity,
                _trades[i].receiveToken,
                _trades[i].receiveQuantity,
                _trades[i].data
            );

            // ZeroEx (for example) throws custom errors which slip through OpenZeppelin's
            // functionCallWithValue error management and surface here as `bytes`. These should be
            // decode-able off-chain given enough context about protocol targeted by the adapter.
           if(!ValidAdapterByModule(_jasperVault,address(tradeModule),_trades[i].exchangeName)){
               continue;
           }
            try 
             manager.interactManager(address(tradeModule), callData)
            {}
            catch Error(string memory reason) {
                emit StringTradeFailed(
                    address(_jasperVault),
                    i,
                    reason,
                    _trades[i]
                );
            } catch (bytes memory lowLevelData) {
                emit BytesTradeFailed(
                    address(_jasperVault),
                    i,
                    lowLevelData,
                    _trades[i]
                );
            }
        }
    }
    /* ============ External Getter Functions ============ */

    function getIntegrations() external view returns (string[] memory) {
        return integrations;
    }

    /* ============ Internal Functions ============ */

    /**
     * Add an allowed TradeModule exchange integration to the BatchTradeExtension
     *
     * @param _integrationName               Name of TradeModule exchange integration to allow
     */
    function _addIntegration(string memory _integrationName) internal {
        isIntegration[_integrationName] = true;

        emit IntegrationAdded(_integrationName);
    }

    /**
     * Internal function to initialize TradeModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the TradeModule for
     */
    function _initializeModule(IJasperVault _jasperVault, IDelegatedManager _delegatedManager) internal {
        bytes memory callData = abi.encodeWithSelector(ITradeModule.initialize.selector, _jasperVault);
        _invokeManager(_delegatedManager, address(tradeModule), callData);
    }
}
