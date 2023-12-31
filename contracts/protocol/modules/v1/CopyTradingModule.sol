/*
    Copyright 2020 Set Labs Inc.

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

pragma solidity ^0.6.10;
pragma experimental "ABIEncoderV2";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

import {IController} from "../../../interfaces/IController.sol";
import {ISignalSuscriptionModule} from "../../../interfaces/ISignalSuscriptionModule.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExchangeAdapter} from "../../../interfaces/IExchangeAdapter.sol";
import {IIntegrationRegistry} from "../../../interfaces/IIntegrationRegistry.sol";
import {Invoke} from "../../lib/Invoke.sol";
import {IJasperVault} from "../../../interfaces/IJasperVault.sol";
import {ModuleBase} from "../../lib/ModuleBase.sol";
import {Position} from "../../lib/Position.sol";
import {PreciseUnitMath} from "../../../lib/PreciseUnitMath.sol";

/**
 * @title TradeModule
 * @author Set Protocol
 *
 * Module that enables SetTokens to perform atomic trades using Decentralized Exchanges
 * such as 1inch or Kyber. Integrations mappings are stored on the IntegrationRegistry contract.
 */
contract CopyTradingModule is ModuleBase, ReentrancyGuard {
    using SafeCast for int256;
    using SafeMath for uint256;

    using Invoke for IJasperVault;
    using Position for IJasperVault;
    using PreciseUnitMath for uint256;

    /* ============ Struct ============ */

    struct TradeInfo {
        IJasperVault jasperVault; // Instance of JasperVault
        IExchangeAdapter exchangeAdapter; // Instance of exchange adapter contract
        address sendToken; // Address of token being sold
        address receiveToken; // Address of token being bought
        uint256 setTotalSupply; // Total supply of JasperVault in Precise Units (10^18)
        uint256 totalSendQuantity; // Total quantity of sold token (position unit x total supply)
        uint256 totalMinReceiveQuantity; // Total minimum quantity of token to receive back
        uint256 preTradeSendTokenBalance; // Total initial balance of token being sold
        uint256 preTradeReceiveTokenBalance; // Total initial balance of token being bought
    }

    /* ============ Events ============ */

    event ComponentExchanged(
        IJasperVault indexed _jasperVault,
        address indexed _sendToken,
        address indexed _receiveToken,
        IExchangeAdapter _exchangeAdapter,
        uint256 _totalSendAmount,
        uint256 _totalReceiveAmount,
        uint256 _protocolFee
    );

    event CopyTrading_ComponentExchanged(
        IJasperVault _source_setToken,
        IJasperVault indexed _jasperVault,
        address indexed _sendToken,
        address indexed _receiveToken,
        IExchangeAdapter _exchangeAdapter,
        uint256 _totalSendAmount,
        uint256 _totalReceiveAmount,
        uint256 _protocolFee
    );

    ISignalSuscriptionModule public signalSuscriptionModule;

    /* ============ Constants ============ */

    // 0 index stores the fee % charged in the trade function
    uint256 internal constant TRADE_MODULE_PROTOCOL_FEE_INDEX = 0;

    /* ============ Constructor ============ */

    constructor(
        IController _controller,
        ISignalSuscriptionModule _signalSuscriptionModule
    ) public ModuleBase(_controller) {
        signalSuscriptionModule = _signalSuscriptionModule;
    }

    /* ============ External Functions ============ */

    /**
     * Initializes this module to the JasperVault. Only callable by the JasperVault's manager.
     *
     * @param _jasperVault                 Instance of the JasperVault to initialize
     */
    function initialize(IJasperVault _jasperVault)
        external
        onlyValidAndPendingSet(_jasperVault)
        onlySetManager(_jasperVault, msg.sender)
    {
        _jasperVault.initializeModule();
    }

    /**
     * Executes a trade on a supported DEX. Only callable by the JasperVault's manager.
     * @dev Although the JasperVault units are passed in for the send and receive quantities, the total quantity
     * sent and received is the quantity of JasperVault units multiplied by the JasperVault totalSupply.
     *
     * @param _jasperVault             Instance of the JasperVault to trade
     * @param _exchangeName         Human readable name of the exchange in the integrations registry
     * @param _sendToken             of the token to be sent to the exchange
     * @param _sendQuantity         Units of token in JasperVault sent to the exchange
     * @param _receiveToken         AddressAddress of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of token in JasperVault to be received from the exchange
     * @param _data                 Arbitrary bytes to be used to construct trade call data
     */
    function trade(
        IJasperVault _jasperVault,
        string memory _exchangeName,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        bytes memory _data
    ) external nonReentrant onlyManagerAndValidSet(_jasperVault) {
        _trade(
            _jasperVault,
            _exchangeName,
            _sendToken,
            _sendQuantity,
            true,
            _receiveToken,
            _minReceiveQuantity,
            _data
        );
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            _trade(
                IJasperVault(followers[i]),
                _exchangeName,
                _sendToken,
                _sendQuantity,
                false,
                _receiveToken,
                _minReceiveQuantity,
                _data
            );
        }
    }

    function _trade(
        IJasperVault _jasperVault,
        string memory _exchangeName,
        address _sendToken,
        uint256 _sendQuantity,
        bool exit_onerror,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        bytes memory _data
    ) internal {
        TradeInfo memory tradeInfo = _createTradeInfo(
            _jasperVault,
            _exchangeName,
            _sendToken,
            _receiveToken,
            _sendQuantity,
            _minReceiveQuantity
        );
        if (exit_onerror) {
            _validatePreTradeData(tradeInfo, _sendQuantity);
        } else {
            if (
                _validatePreTradeData_noerror(tradeInfo, _sendQuantity) == false
            ) {
                return;
            }
        }
        _executeTrade(tradeInfo, _data);

        uint256 exchangedQuantity = _validatePostTrade(tradeInfo);

        uint256 protocolFee = _accrueProtocolFee(tradeInfo, exchangedQuantity);

        (
            uint256 netSendAmount,
            uint256 netReceiveAmount
        ) = _updateSetTokenPositions(tradeInfo);

        emit ComponentExchanged(
            _jasperVault,
            _sendToken,
            _receiveToken,
            tradeInfo.exchangeAdapter,
            netSendAmount,
            netReceiveAmount,
            protocolFee
        );
    }

    /**
     * Removes this module from the JasperVault, via call by the JasperVault. Left with empty logic
     * here because there are no check needed to verify removal.
     */
    function removeModule() external override {}

    /* ============ Internal Functions ============ */

    /**
     * Create and return TradeInfo struct
     *
     * @param _jasperVault             Instance of the JasperVault to trade
     * @param _exchangeName         Human readable name of the exchange in the integrations registry
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _sendQuantity         Units of token in JasperVault sent to the exchange
     * @param _minReceiveQuantity   Min units of token in JasperVault to be received from the exchange
     *
     * return TradeInfo             Struct containing data for trade
     */
    function _createTradeInfo(
        IJasperVault _jasperVault,
        string memory _exchangeName,
        address _sendToken,
        address _receiveToken,
        uint256 _sendQuantity,
        uint256 _minReceiveQuantity
    ) internal view returns (TradeInfo memory) {
        TradeInfo memory tradeInfo;

        tradeInfo.jasperVault = _jasperVault;

        tradeInfo.exchangeAdapter = IExchangeAdapter(
            getAndValidateAdapter(_exchangeName)
        );

        tradeInfo.sendToken = _sendToken;
        tradeInfo.receiveToken = _receiveToken;

        tradeInfo.setTotalSupply = _jasperVault.totalSupply();

        tradeInfo.totalSendQuantity = Position.getDefaultTotalNotional(
            tradeInfo.setTotalSupply,
            _sendQuantity
        );

        tradeInfo.totalMinReceiveQuantity = Position.getDefaultTotalNotional(
            tradeInfo.setTotalSupply,
            _minReceiveQuantity
        );

        tradeInfo.preTradeSendTokenBalance = IERC20(_sendToken).balanceOf(
            address(_jasperVault)
        );
        tradeInfo.preTradeReceiveTokenBalance = IERC20(_receiveToken).balanceOf(
            address(_jasperVault)
        );

        return tradeInfo;
    }

    /**
     * Validate pre trade data. Check exchange is valid, token quantity is valid.
     *
     * @param _tradeInfo            Struct containing trade information used in internal functions
     * @param _sendQuantity         Units of token in JasperVault sent to the exchange
     */
    function _validatePreTradeData(
        TradeInfo memory _tradeInfo,
        uint256 _sendQuantity
    ) internal view {
        require(
            _tradeInfo.totalSendQuantity > 0,
            "Token to sell must be nonzero"
        );

        require(
            _tradeInfo.jasperVault.hasSufficientDefaultUnits(
                _tradeInfo.sendToken,
                _sendQuantity
            ),
            "Unit cant be greater than existing"
        );
    }

    function _validatePreTradeData_noerror(
        TradeInfo memory _tradeInfo,
        uint256 _sendQuantity
    ) internal view returns (bool) {
        require(
            _tradeInfo.totalSendQuantity > 0,
            "Token to sell must be nonzero"
        );
        if (
            _tradeInfo.jasperVault.hasSufficientDefaultUnits(
                _tradeInfo.sendToken,
                _sendQuantity
            ) == false
        ) {
            return false;
        }
        return true;
    }

    /**
     * Invoke approve for send token, get method data and invoke trade in the context of the JasperVault.
     *
     * @param _tradeInfo            Struct containing trade information used in internal functions
     * @param _data                 Arbitrary bytes to be used to construct trade call data
     */
    function _executeTrade(TradeInfo memory _tradeInfo, bytes memory _data)
        internal
    {
        // Get spender address from exchange adapter and invoke approve for exact amount on JasperVault
        _tradeInfo.jasperVault.invokeApprove(
            _tradeInfo.sendToken,
            _tradeInfo.exchangeAdapter.getSpender(),
            _tradeInfo.totalSendQuantity
        );

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = _tradeInfo.exchangeAdapter.getTradeCalldata(
                _tradeInfo.sendToken,
                _tradeInfo.receiveToken,
                address(_tradeInfo.jasperVault),
                _tradeInfo.totalSendQuantity,
                _tradeInfo.totalMinReceiveQuantity,
                _data
            );

        _tradeInfo.jasperVault.invoke(targetExchange, callValue, methodData);
    }

    /**
     * Validate post trade data.
     *
     * @param _tradeInfo                Struct containing trade information used in internal functions
     * @return uint256                  Total quantity of receive token that was exchanged
     */
    function _validatePostTrade(TradeInfo memory _tradeInfo)
        internal
        view
        returns (uint256)
    {
        uint256 exchangedQuantity = IERC20(_tradeInfo.receiveToken)
            .balanceOf(address(_tradeInfo.jasperVault))
            .sub(_tradeInfo.preTradeReceiveTokenBalance);

        require(
            exchangedQuantity >= _tradeInfo.totalMinReceiveQuantity,
            "Slippage greater than allowed"
        );

        return exchangedQuantity;
    }

    /**
     * Retrieve fee from controller and calculate total protocol fee and send from JasperVault to protocol recipient
     *
     * @param _tradeInfo                Struct containing trade information used in internal functions
     * @return uint256                  Amount of receive token taken as protocol fee
     */
    function _accrueProtocolFee(
        TradeInfo memory _tradeInfo,
        uint256 _exchangedQuantity
    ) internal returns (uint256) {
        uint256 protocolFeeTotal = getModuleFee(
            TRADE_MODULE_PROTOCOL_FEE_INDEX,
            _exchangedQuantity
        );

        payProtocolFeeFromSetToken(
            _tradeInfo.jasperVault,
            _tradeInfo.receiveToken,
            protocolFeeTotal
        );

        return protocolFeeTotal;
    }

    /**
     * Update JasperVault positions
     *
     * @param _tradeInfo                Struct containing trade information used in internal functions
     * @return uint256                  Amount of sendTokens used in the trade
     * @return uint256                  Amount of receiveTokens received in the trade (net of fees)
     */
    function _updateSetTokenPositions(TradeInfo memory _tradeInfo)
        internal
        returns (uint256, uint256)
    {
        (uint256 currentSendTokenBalance, , ) = _tradeInfo
            .jasperVault
            .calculateAndEditDefaultPosition(
                _tradeInfo.sendToken,
                _tradeInfo.setTotalSupply,
                _tradeInfo.preTradeSendTokenBalance
            );

        (uint256 currentReceiveTokenBalance, , ) = _tradeInfo
            .jasperVault
            .calculateAndEditDefaultPosition(
                _tradeInfo.receiveToken,
                _tradeInfo.setTotalSupply,
                _tradeInfo.preTradeReceiveTokenBalance
            );

        return (
            _tradeInfo.preTradeSendTokenBalance.sub(currentSendTokenBalance),
            currentReceiveTokenBalance.sub(
                _tradeInfo.preTradeReceiveTokenBalance
            )
        );
    }
}
