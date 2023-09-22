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

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { AddressArrayUtils } from "../../../lib/AddressArrayUtils.sol";
import { IController } from "../../../interfaces/IController.sol";
import { IJasperVault } from "../../../interfaces/IJasperVault.sol";
import { Invoke } from "../../lib/Invoke.sol";
import { ModuleBase } from "../../lib/ModuleBase.sol";
import { Position } from "../../lib/Position.sol";
import { PreciseUnitMath } from "../../../lib/PreciseUnitMath.sol";


/**
 * @title AirdropModule
 * @author Set Protocol
 *
 * Module that enables managers to absorb tokens sent to the JasperVault into the token's positions. With each JasperVault,
 * managers are able to specify 1) the airdrops they want to include, 2) an airdrop fee recipient, 3) airdrop fee,
 * and 4) whether all users are allowed to trigger an airdrop.
 */
contract AirdropModule is ModuleBase, ReentrancyGuard {
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using Position for uint256;
    using SafeCast for int256;
    using AddressArrayUtils for address[];
    using Invoke for IJasperVault;
    using Position for IJasperVault;

    /* ============ Structs ============ */

    struct AirdropSettings {
        address[] airdrops;                     // Array of tokens manager is allowing to be absorbed
        address feeRecipient;                   // Address airdrop fees are sent to
        uint256 airdropFee;                     // Percentage in preciseUnits of airdrop sent to feeRecipient (1e16 = 1%)
        bool anyoneAbsorb;                      // Boolean indicating if any address can call absorb or just the manager
    }

    /* ============ Events ============ */

    event ComponentAbsorbed(
        IJasperVault indexed _jasperVault,
        IERC20 indexed _absorbedToken,
        uint256 _absorbedQuantity,
        uint256 _managerFee,
        uint256 _protocolFee
    );

    event AirdropComponentAdded(IJasperVault indexed _jasperVault, IERC20 indexed _component);
    event AirdropComponentRemoved(IJasperVault indexed _jasperVault, IERC20 indexed _component);
    event AnyoneAbsorbUpdated(IJasperVault indexed _jasperVault, bool _anyoneAbsorb);
    event AirdropFeeUpdated(IJasperVault indexed _jasperVault, uint256 _newFee);
    event FeeRecipientUpdated(IJasperVault indexed _jasperVault, address _newFeeRecipient);

    /* ============ Modifiers ============ */

    /**
     * Throws if claim is confined to the manager and caller is not the manager
     */
    modifier onlyValidCaller(IJasperVault _jasperVault) {
        require(_isValidCaller(_jasperVault), "Must be valid caller");
        _;
    }

    /* ============ Constants ============ */

    uint256 public constant AIRDROP_MODULE_PROTOCOL_FEE_INDEX = 0;

    /* ============ State Variables ============ */

    mapping(IJasperVault => AirdropSettings) public airdropSettings;
    // Mapping indicating if token is an allowed airdrop
    mapping(IJasperVault => mapping(IERC20 => bool)) public isAirdrop;

    /* ============ Constructor ============ */

    constructor(IController _controller) public ModuleBase(_controller) {}

    /* ============ External Functions ============ */

    /**
     * Absorb passed tokens into respective positions. If airdropFee defined, send portion to feeRecipient and portion to
     * protocol feeRecipient address. Callable only by manager unless manager has set anyoneAbsorb to true.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _tokens                   Array of tokens to absorb
     */
    function batchAbsorb(IJasperVault _jasperVault, address[] memory _tokens)
        external
        nonReentrant
        onlyValidCaller(_jasperVault)
        onlyValidAndInitializedSet(_jasperVault)
    {
        _batchAbsorb(_jasperVault, _tokens);
    }

    /**
     * Absorb specified token into position. If airdropFee defined, send portion to feeRecipient and portion to
     * protocol feeRecipient address. Callable only by manager unless manager has set anyoneAbsorb to true.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _token                    Address of token to absorb
     */
    function absorb(IJasperVault _jasperVault, IERC20 _token)
        external
        nonReentrant
        onlyValidCaller(_jasperVault)
        onlyValidAndInitializedSet(_jasperVault)
    {
        _absorb(_jasperVault, _token);
    }

    /**
     * SET MANAGER ONLY. Adds new tokens to be added to positions when absorb is called.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _airdrop                  Component to add to airdrop list
     */
    function addAirdrop(IJasperVault _jasperVault, IERC20 _airdrop) external onlyManagerAndValidSet(_jasperVault) {
        require(!isAirdropToken(_jasperVault, _airdrop), "Token already added.");
        airdropSettings[_jasperVault].airdrops.push(address(_airdrop));
        isAirdrop[_jasperVault][_airdrop] = true;
        emit AirdropComponentAdded(_jasperVault, _airdrop);
    }

    /**
     * SET MANAGER ONLY. Removes tokens from list to be absorbed.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _airdrop                  Component to remove from airdrop list
     */
    function removeAirdrop(IJasperVault _jasperVault, IERC20 _airdrop) external onlyManagerAndValidSet(_jasperVault) {
        require(isAirdropToken(_jasperVault, _airdrop), "Token not added.");
        airdropSettings[_jasperVault].airdrops.removeStorage(address(_airdrop));
        isAirdrop[_jasperVault][_airdrop] = false;
        emit AirdropComponentRemoved(_jasperVault, _airdrop);
    }

    /**
     * SET MANAGER ONLY. Update whether manager allows other addresses to call absorb.
     *
     * @param _jasperVault                 Address of JasperVault
     */
    function updateAnyoneAbsorb(IJasperVault _jasperVault, bool _anyoneAbsorb) external onlyManagerAndValidSet(_jasperVault) {
        airdropSettings[_jasperVault].anyoneAbsorb = _anyoneAbsorb;
        emit AnyoneAbsorbUpdated(_jasperVault, _anyoneAbsorb);
    }

    /**
     * SET MANAGER ONLY. Update address manager fees are sent to.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _newFeeRecipient      Address of new fee recipient
     */
    function updateFeeRecipient(
        IJasperVault _jasperVault,
        address _newFeeRecipient
    )
        external
        onlyManagerAndValidSet(_jasperVault)
    {
        require(_newFeeRecipient != address(0), "Passed address must be non-zero");
        airdropSettings[_jasperVault].feeRecipient = _newFeeRecipient;
        emit FeeRecipientUpdated(_jasperVault, _newFeeRecipient);
    }

    /**
     * SET MANAGER ONLY. Update airdrop fee percentage.
     *
     * @param _jasperVault         Address of JasperVault
     * @param _newFee           Percentage, in preciseUnits, of new airdrop fee (1e16 = 1%)
     */
    function updateAirdropFee(
        IJasperVault _jasperVault,
        uint256 _newFee
    )
        external
        onlySetManager(_jasperVault, msg.sender)
        onlyValidAndInitializedSet(_jasperVault)
    {
        require(_newFee <=  PreciseUnitMath.preciseUnit(), "Airdrop fee can't exceed 100%");

        // Absorb all outstanding tokens before fee is updated
        _batchAbsorb(_jasperVault, airdropSettings[_jasperVault].airdrops);

        airdropSettings[_jasperVault].airdropFee = _newFee;
        emit AirdropFeeUpdated(_jasperVault, _newFee);
    }

    /**
     * SET MANAGER ONLY. Initialize module with JasperVault and set initial airdrop tokens as well as specify
     * whether anyone can call absorb.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _airdropSettings          Struct of airdrop setting for Set including accepted airdrops, feeRecipient,
     *                                  airdropFee, and indicating if anyone can call an absorb
     */
    function initialize(
        IJasperVault _jasperVault,
        AirdropSettings memory _airdropSettings
    )
        external
        onlySetManager(_jasperVault, msg.sender)
        onlyValidAndPendingSet(_jasperVault)
    {
        require(_airdropSettings.airdropFee <= PreciseUnitMath.preciseUnit(), "Fee must be <= 100%.");
        require(_airdropSettings.feeRecipient != address(0), "Zero fee address passed");
        if (_airdropSettings.airdrops.length > 0) {
            require(!_airdropSettings.airdrops.hasDuplicate(), "Duplicate airdrop token passed");
        }

        airdropSettings[_jasperVault] = _airdropSettings;

        for (uint256 i = 0; i < _airdropSettings.airdrops.length; i++) {
            isAirdrop[_jasperVault][IERC20(_airdropSettings.airdrops[i])] = true;
        }

        _jasperVault.initializeModule();
    }

    /**
     * Removes this module from the JasperVault, via call by the JasperVault. Token's airdrop settings are deleted.
     * Airdrops are not absorbed.
     */
    function removeModule() external override {
        address[] memory airdrops = airdropSettings[IJasperVault(msg.sender)].airdrops;

        for (uint256 i =0; i < airdrops.length; i++) {
            isAirdrop[IJasperVault(msg.sender)][IERC20(airdrops[i])] = false;
        }

        delete airdropSettings[IJasperVault(msg.sender)];
    }

    /**
     * Get list of tokens approved to collect airdrops for the JasperVault.
     *
     * @param _jasperVault             Address of JasperVault
     * @return                      Array of tokens approved for airdrops
     */
    function getAirdrops(IJasperVault _jasperVault) external view returns (address[] memory) {
        return airdropSettings[_jasperVault].airdrops;
    }

    /**
     * Get boolean indicating if token is approved for airdrops.
     *
     * @param _jasperVault             Address of JasperVault
     * @return                      Boolean indicating approval for airdrops
     */
    function isAirdropToken(IJasperVault _jasperVault, IERC20 _token) public view returns (bool) {
        return isAirdrop[_jasperVault][_token];
    }

    /* ============ Internal Functions ============ */

    /**
     * Check token approved for airdrops then handle airdropped position.
     */
    function _absorb(IJasperVault _jasperVault, IERC20 _token) internal {
        require(isAirdropToken(_jasperVault, _token), "Must be approved token.");

        _handleAirdropPosition(_jasperVault, _token);
    }

    /**
     * Loop through array of tokens and handle airdropped positions.
     */
    function _batchAbsorb(IJasperVault _jasperVault, address[] memory _tokens) internal {
        for (uint256 i = 0; i < _tokens.length; i++) {
            _absorb(_jasperVault, IERC20(_tokens[i]));
        }
    }

    /**
     * Calculate amount of tokens airdropped since last absorption, then distribute fees and update position.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _token                    Address of airdropped token
     */
    function _handleAirdropPosition(IJasperVault _jasperVault, IERC20 _token) internal {
        uint256 preFeeTokenBalance = _token.balanceOf(address(_jasperVault));
        uint256 amountAirdropped = preFeeTokenBalance.sub(_jasperVault.getDefaultTrackedBalance(address(_token)));

        if (amountAirdropped > 0) {
            (uint256 managerTake, uint256 protocolTake, uint256 totalFees) = _handleFees(_jasperVault, _token, amountAirdropped);

            uint256 newUnit = _getPostAirdropUnit(_jasperVault, preFeeTokenBalance, totalFees);

            _jasperVault.editDefaultPosition(address(_token), newUnit);

            emit ComponentAbsorbed(_jasperVault, _token, amountAirdropped, managerTake, protocolTake);
        }
    }

    /**
     * Calculate fee total and distribute between feeRecipient defined on module and the protocol feeRecipient.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _component                Address of airdropped component
     * @param _amountAirdropped         Amount of tokens airdropped to the JasperVault
     * @return netManagerTake           Amount of airdropped tokens set aside for manager fees net of protocol fees
     * @return protocolTake             Amount of airdropped tokens set aside for protocol fees (taken from manager fees)
     * @return totalFees                Total fees paid
     */
    function _handleFees(
        IJasperVault _jasperVault,
        IERC20 _component,
        uint256 _amountAirdropped
    )
        internal
        returns (uint256 netManagerTake, uint256 protocolTake, uint256 totalFees)
    {
        uint256 airdropFee = airdropSettings[_jasperVault].airdropFee;

        if (airdropFee > 0) {
            totalFees = _amountAirdropped.preciseMul(airdropFee);

            protocolTake = getModuleFee(AIRDROP_MODULE_PROTOCOL_FEE_INDEX, totalFees);
            netManagerTake = totalFees.sub(protocolTake);

            _jasperVault.strictInvokeTransfer(address(_component), airdropSettings[_jasperVault].feeRecipient, netManagerTake);

            payProtocolFeeFromSetToken(_jasperVault, address(_component), protocolTake);

            return (netManagerTake, protocolTake, totalFees);
        } else {
            return (0, 0, 0);
        }
    }

    /**
     * Retrieve new unit, which is the current balance less fees paid divided by total supply
     */
    function _getPostAirdropUnit(
        IJasperVault _jasperVault,
        uint256 _totalComponentBalance,
        uint256 _totalFeesPaid
    )
        internal
        view
        returns(uint256)
    {
        uint256 totalSupply = _jasperVault.totalSupply();
        return totalSupply.getDefaultPositionUnit(_totalComponentBalance.sub(_totalFeesPaid));
    }

    /**
     * If absorption is confined to the manager, manager must be caller
     */
    function _isValidCaller(IJasperVault _jasperVault) internal view returns(bool) {
        return airdropSettings[_jasperVault].anyoneAbsorb || isSetManager(_jasperVault, msg.sender);
    }
}
