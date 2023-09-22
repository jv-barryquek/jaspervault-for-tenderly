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

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";

import {IController} from "../../../interfaces/IController.sol";
import {IJasperVault} from "../../../interfaces/IJasperVault.sol";
import {ModuleBase} from "../../lib/ModuleBase.sol";
import {PreciseUnitMath} from "../../../lib/PreciseUnitMath.sol";

/**
 * @title StreamingFeeModule
 * @author Set Protocol
 *
 * Smart contract that accrues streaming fees for Set managers. Streaming fees are denominated as percent
 * per year and realized as Set inflation rewarded to the manager.
 */
contract StreamingFeeModule is ModuleBase, ReentrancyGuard {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeCast for uint256;

    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using SafeCast for int256;

    /* ============ Structs ============ */

    struct FeeState {
        address feeRecipient; // Address to accrue fees to
        uint256 maxStreamingFeePercentage; // Max streaming fee maanager commits to using (1% = 1e16, 100% = 1e18)
        uint256 streamingFeePercentage; // Percent of Set accruing to manager annually (1% = 1e16, 100% = 1e18)
        uint256 lastStreamingFeeTimestamp; // Timestamp last streaming fee was accrued
        uint256 profitSharingPercentage;
    }

    /* ============ Events ============ */

    event FeeActualized(
        address indexed _jasperVault,
        uint256 _managerFee,
        uint256 _protocolFee
    );
    event StreamingFeeUpdated(
        address indexed _jasperVault,
        uint256 _newStreamingFee
    );
    event FeeRecipientUpdated(
        address indexed _jasperVault,
        address _newFeeRecipient
    );

    /* ============ Constants ============ */

    uint256 private constant ONE_YEAR_IN_SECONDS = 365.25 days;
    uint256 private constant PROTOCOL_STREAMING_FEE_INDEX = 0;

    /* ============ State Variables ============ */

    mapping(IJasperVault => FeeState) public feeStates;

    /* ============ Constructor ============ */

    constructor(IController _controller) public ModuleBase(_controller) {}

    /* ============ External Functions ============ */

    /*
     * Calculates total inflation percentage then mints new Sets to the fee recipient. Position units are
     * then adjusted down (in magnitude) in order to ensure full collateralization. Callable by anyone.
     *
     * @param _jasperVault       Address of JasperVault
     */
    function accrueFee(
        IJasperVault _jasperVault
    ) public nonReentrant onlyValidAndInitializedSet(_jasperVault) {
        uint256 managerFee;
        uint256 protocolFee;

        if (_streamingFeePercentage(_jasperVault) > 0) {
            uint256 inflationFeePercentage = _calculateStreamingFee(_jasperVault);

            // Calculate incentiveFee inflation
            uint256 feeQuantity = _calculateStreamingFeeInflation(
                _jasperVault,
                inflationFeePercentage
            );

            // Mint new Sets to manager and protocol
            (managerFee, protocolFee) = _mintManagerAndProtocolFee(
                _jasperVault,
                feeQuantity
            );

            _editPositionMultiplier(_jasperVault, inflationFeePercentage);
        }

        feeStates[_jasperVault].lastStreamingFeeTimestamp = block.timestamp;

        emit FeeActualized(address(_jasperVault), managerFee, protocolFee);
    }

    /**
     * SET MANAGER ONLY. Initialize module with JasperVault and set the fee state for the JasperVault. Passed
     * _settings will have lastStreamingFeeTimestamp over-written.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _settings                 FeeState struct defining fee parameters
     */
    function initialize(
        IJasperVault _jasperVault,
        FeeState memory _settings
    )
        external
        onlySetManager(_jasperVault, msg.sender)
        onlyValidAndPendingSet(_jasperVault)
    {
        require(
            _settings.feeRecipient != address(0),
            "Fee Recipient must be non-zero address."
        );
        require(
            _settings.maxStreamingFeePercentage < PreciseUnitMath.preciseUnit(),
            "Max fee must be < 100%."
        );
        require(
            _settings.streamingFeePercentage <=
                _settings.maxStreamingFeePercentage,
            "Fee must be <= max."
        );

        _settings.lastStreamingFeeTimestamp = block.timestamp;

        feeStates[_jasperVault] = _settings;
        _jasperVault.initializeModule();
    }

    /**
     * Removes this module from the JasperVault, via call by the JasperVault. Manager's feeState is deleted. Fees
     * are not accrued in case reason for removing module is related to fee accrual.
     */
    function removeModule() external override {
        delete feeStates[IJasperVault(msg.sender)];
    }

    /*
     * Set new streaming fee. Fees accrue at current rate then new rate is set.
     * Fees are accrued to prevent the manager from unfairly accruing a larger percentage.
     *
     * @param _jasperVault       Address of JasperVault
     * @param _newFee         New streaming fee 18 decimal precision
     */
    function updateStreamingFee(
        IJasperVault _jasperVault,
        uint256 _newFee
    )
        external
        onlySetManager(_jasperVault, msg.sender)
        onlyValidAndInitializedSet(_jasperVault)
    {
        require(
            _newFee < _maxStreamingFeePercentage(_jasperVault),
            "Fee must be less than max"
        );
        accrueFee(_jasperVault);

        feeStates[_jasperVault].streamingFeePercentage = _newFee;

        emit StreamingFeeUpdated(address(_jasperVault), _newFee);
    }

    /*
     * Set new fee recipient.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _newFeeRecipient      New fee recipient
     */
    function updateFeeRecipient(
        IJasperVault _jasperVault,
        address _newFeeRecipient
    )
        external
        onlySetManager(_jasperVault, msg.sender)
        onlyValidAndInitializedSet(_jasperVault)
    {
        require(
            _newFeeRecipient != address(0),
            "Fee Recipient must be non-zero address."
        );

        feeStates[_jasperVault].feeRecipient = _newFeeRecipient;

        emit FeeRecipientUpdated(address(_jasperVault), _newFeeRecipient);
    }

    /*
     * Calculates total inflation percentage in order to accrue fees to manager.
     *
     * @param _jasperVault       Address of JasperVault
     * @return  uint256       Percent inflation of supply
     */
    function getFee(IJasperVault _jasperVault) external view returns (uint256) {
        return _calculateStreamingFee(_jasperVault);
    }

    function get_profitSharingPercentage(
        IJasperVault _jasperVault
    ) external view returns (uint256) {
        return _profitSharingPercentage(_jasperVault);
    }

    /* ============ Internal Functions ============ */

    /**
     * Calculates streaming fee by multiplying streamingFeePercentage by the elapsed amount of time since the last fee
     * was collected divided by one year in seconds, since the fee is a yearly fee.
     *
     * @param  _jasperVault          Address of Set to have feeState updated
     * @return uint256            Streaming fee denominated in percentage of totalSupply
     */
    function _calculateStreamingFee(
        IJasperVault _jasperVault
    ) internal view returns (uint256) {
        uint256 timeSinceLastFee = block.timestamp.sub(
            _lastStreamingFeeTimestamp(_jasperVault)
        );

        // Streaming fee is streaming fee times years since last fee
        return
            timeSinceLastFee.mul(_streamingFeePercentage(_jasperVault)).div(
                ONE_YEAR_IN_SECONDS
            );
    }

    /**
     * Returns the new incentive fee denominated in the number of SetTokens to mint. The calculation for the fee involves
     * implying mint quantity so that the feeRecipient owns the fee percentage of the entire supply of the Set.
     *
     * The formula to solve for fee is:
     * (feeQuantity / feeQuantity) + totalSupply = fee / scaleFactor
     *
     * The simplified formula utilized below is:
     * feeQuantity = fee * totalSupply / (scaleFactor - fee)
     *
     * @param   _jasperVault               JasperVault instance
     * @param   _feePercentage          Fee levied to feeRecipient
     * @return  uint256                 New RebalancingSet issue quantity
     */
    function _calculateStreamingFeeInflation(
        IJasperVault _jasperVault,
        uint256 _feePercentage
    ) internal view returns (uint256) {
        uint256 totalSupply = _jasperVault.totalSupply();

        // fee * totalSupply
        uint256 a = _feePercentage.mul(totalSupply);

        // ScaleFactor (10e18) - fee
        uint256 b = PreciseUnitMath.preciseUnit().sub(_feePercentage);

        return a.div(b);
    }

    /**
     * Mints sets to both the manager and the protocol. Protocol takes a percentage fee of the total amount of Sets
     * minted to manager.
     *
     * @param   _jasperVault               JasperVault instance
     * @param   _feeQuantity            Amount of Sets to be minted as fees
     * @return  uint256                 Amount of Sets accrued to manager as fee
     * @return  uint256                 Amount of Sets accrued to protocol as fee
     */
    function _mintManagerAndProtocolFee(
        IJasperVault _jasperVault,
        uint256 _feeQuantity
    ) internal returns (uint256, uint256) {
        address protocolFeeRecipient = controller.feeRecipient();
        uint256 protocolFee = controller.getModuleFee(
            address(this),
            PROTOCOL_STREAMING_FEE_INDEX
        );

        uint256 protocolFeeAmount = _feeQuantity.preciseMul(protocolFee);
        uint256 managerFeeAmount = _feeQuantity.sub(protocolFeeAmount);

        _jasperVault.mint(_feeRecipient(_jasperVault), managerFeeAmount);

        if (protocolFeeAmount > 0) {
            _jasperVault.mint(protocolFeeRecipient, protocolFeeAmount);
        }

        return (managerFeeAmount, protocolFeeAmount);
    }

    /**
     * Calculates new position multiplier according to following formula:
     *
     * newMultiplier = oldMultiplier * (1-inflationFee)
     *
     * This reduces position sizes to offset increase in supply due to fee collection.
     *
     * @param   _jasperVault               JasperVault instance
     * @param   _inflationFee           Fee inflation rate
     */
    function _editPositionMultiplier(
        IJasperVault _jasperVault,
        uint256 _inflationFee
    ) internal {
        int256 currentMultipler = _jasperVault.positionMultiplier();
        int256 newMultiplier = currentMultipler.preciseMul(
            PreciseUnitMath.preciseUnit().sub(_inflationFee).toInt256()
        );

        _jasperVault.editPositionMultiplier(newMultiplier);
    }

    function _feeRecipient(IJasperVault _set) internal view returns (address) {
        return feeStates[_set].feeRecipient;
    }

    function _lastStreamingFeeTimestamp(
        IJasperVault _set
    ) internal view returns (uint256) {
        return feeStates[_set].lastStreamingFeeTimestamp;
    }

    function _maxStreamingFeePercentage(
        IJasperVault _set
    ) internal view returns (uint256) {
        return feeStates[_set].maxStreamingFeePercentage;
    }

    function _streamingFeePercentage(
        IJasperVault _set
    ) internal view returns (uint256) {
        return feeStates[_set].streamingFeePercentage;
    }

    function _profitSharingPercentage(
        IJasperVault _set
    ) internal view returns (uint256) {
        return feeStates[_set].profitSharingPercentage;
    }
}
