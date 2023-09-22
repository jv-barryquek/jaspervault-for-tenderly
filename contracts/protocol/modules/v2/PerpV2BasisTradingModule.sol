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

import { IController } from "../../../interfaces/IController.sol";
import { IMarketRegistry } from "../../../interfaces/external/perp-v2/IMarketRegistry.sol";
import { Invoke } from "../../lib/Invoke.sol";
import { IQuoter } from "../../../interfaces/external/perp-v2/IQuoter.sol";
import { IJasperVault } from "../../../interfaces/IJasperVault.sol";
import { IVault } from "../../../interfaces/external/perp-v2/IVault.sol";
import { ModuleBase } from "../../lib/ModuleBase.sol";
import { PerpV2LeverageModuleV2 } from "./PerpV2LeverageModuleV2.sol";
import { Position } from "../../lib/Position.sol";
import { PreciseUnitMath } from "../../../lib/PreciseUnitMath.sol";

/**
 * @title PerpV2BasisTradingModule
 * @author Set Protocol
 *
 * @notice Smart contract that extends functionality offered by PerpV2LeverageModuleV2. It tracks funding that is settled due to
 * actions on Perpetual protocol and allows it to be withdrawn by the manager. The withdrawn funding can be reinvested in the Set
 * to create a yield generating basis trading product. The manager can also collect performance fees on the withdrawn funding.
 *
 * NOTE: The external position unit is only updated on an as-needed basis during issuance/redemption. It does not reflect the current
 * value of the Set's perpetual position. The current value can be calculated from getPositionNotionalInfo.
 */
contract PerpV2BasisTradingModule is PerpV2LeverageModuleV2 {

    /* ============ Structs ============ */

    struct FeeState {
        address feeRecipient;                     // Address to accrue fees to
        uint256 maxPerformanceFeePercentage;      // Max performance fee manager commits to using (1% = 1e16, 100% = 1e18)
        uint256 performanceFeePercentage;         // Performance fees accrued to manager (1% = 1e16, 100% = 1e18)
    }

    /* ============ Events ============ */

    /**
     * @dev Emitted on performance fee update
     * @param _jasperVault             Instance of JasperVault
     * @param _newPerformanceFee    New performance fee percentage (1% = 1e16)
     */
    event PerformanceFeeUpdated(IJasperVault indexed _jasperVault, uint256 _newPerformanceFee);

    /**
     * @dev Emitted on fee recipient update
     * @param _jasperVault             Instance of JasperVault
     * @param _newFeeRecipient      New performance fee recipient
     */
    event FeeRecipientUpdated(IJasperVault indexed _jasperVault, address _newFeeRecipient);

    /**
     * @dev Emitted on funding withdraw
     * @param _jasperVault             Instance of JasperVault
     * @param _collateralToken      Token being withdrawn as funding (USDC)
     * @param _amountWithdrawn      Amount of funding being withdrawn from Perp (USDC)
     * @param _managerFee           Amount of performance fee accrued to manager (USDC)
     * @param _protocolFee          Amount of performance fee accrued to protocol (USDC)
     */
    event FundingWithdrawn(
        IJasperVault indexed  _jasperVault,
        IERC20 _collateralToken,
        uint256 _amountWithdrawn,
        uint256 _managerFee,
        uint256 _protocolFee
    );

    /* ============ Constants ============ */

    // 1 index stores protocol performance fee % on the controller, charged in the _handleFees function
    uint256 private constant PROTOCOL_PERFORMANCE_FEE_INDEX = 1;

    /* ============ State Variables ============ */

    // Mapping to store fee settings for each JasperVault
    mapping(IJasperVault => FeeState) public feeSettings;

    // Mapping to store funding that has been settled on Perpetual Protocol due to actions via this module
    // and hasn't been withdrawn for reinvesting yet. Values are stored in precise units (10e18).
    mapping(IJasperVault => uint256) public settledFunding;

    /* ============ Constructor ============ */

    /**
     * @dev Sets external PerpV2 Protocol contract addresses. Calls PerpV2LeverageModuleV2 constructor which sets `collateralToken`
     * and `collateralDecimals` to the Perp vault's settlement token (USDC) and its decimals, respectively.
     *
     * @param _controller               Address of controller contract
     * @param _perpVault                Address of Perp Vault contract
     * @param _perpQuoter               Address of Perp Quoter contract
     * @param _perpMarketRegistry       Address of Perp MarketRegistry contract
     * @param _maxPerpPositionsPerSet   Max perpetual positions in one JasperVault
     */
    constructor(
        IController _controller,
        IVault _perpVault,
        IQuoter _perpQuoter,
        IMarketRegistry _perpMarketRegistry,
        uint256 _maxPerpPositionsPerSet
    )
        public
        PerpV2LeverageModuleV2(
            _controller,
            _perpVault,
            _perpQuoter,
            _perpMarketRegistry,
            _maxPerpPositionsPerSet
        )
    {}

    /* ============ External Functions ============ */

    /**
     * @dev Reverts upon calling. Use `initialize(_jasperVault, _settings)` instead.
     */
    function initialize(IJasperVault /*_jasperVault*/) public override(PerpV2LeverageModuleV2) {
        revert("Use initialize(_jasperVault, _settings) instead");
    }

    /**
     * @dev MANAGER ONLY: Initializes this module to the JasperVault and sets fee settings. Either the JasperVault needs to
     * be on the allowed list or anySetAllowed needs to be true.
     *
     * @param _jasperVault             Instance of the JasperVault to initialize
     * @param _settings             FeeState struct defining performance fee settings
     */
    function initialize(
        IJasperVault _jasperVault,
        FeeState memory _settings
    )
        external
    {
        _validateFeeState(_settings);

        // Initialize by calling PerpV2LeverageModuleV2#initialize.
        // Verifies caller is manager. Verifies Set is valid, allowed and in pending state.
        PerpV2LeverageModuleV2.initialize(_jasperVault);

        feeSettings[_jasperVault] = _settings;
    }

    /**
     * @dev MANAGER ONLY: Similar to PerpV2LeverageModuleV2#trade. Allows manager to buy or sell perps to change exposure
     * to the underlying baseToken. Any pending funding that would be settled during opening a position on Perpetual
     * protocol is added to (or subtracted from) `settledFunding[_jasperVault]` and can be withdrawn later using
     * `withdrawFundingAndAccrueFees` by the JasperVault manager.
     * NOTE: Calling a `nonReentrant` function from another `nonReentrant` function is not supported. Hence, we can't
     * add the `nonReentrant` modifier here because `PerpV2LeverageModuleV2#trade` function has a reentrancy check.
     * NOTE: This method doesn't update the externalPositionUnit because it is a function of UniswapV3 virtual
     * token market prices and needs to be generated on the fly to be meaningful.
     *
     * @param _jasperVault                     Instance of the JasperVault
     * @param _baseToken                    Address virtual token being traded
     * @param _baseQuantityUnits            Quantity of virtual token to trade in position units
     * @param _quoteBoundQuantityUnits      Max/min of vQuote asset to pay/receive when buying or selling
     */
    function tradeAndTrackFunding(
        IJasperVault _jasperVault,
        address _baseToken,
        int256 _baseQuantityUnits,
        uint256 _quoteBoundQuantityUnits
    )
        external
        onlyManagerAndValidSet(_jasperVault)
    {
        // Track funding before it is settled
        _updateSettledFunding(_jasperVault);

        // Trade using PerpV2LeverageModuleV2#trade.
        PerpV2LeverageModuleV2.trade(
            _jasperVault,
            _baseToken,
            _baseQuantityUnits,
            _quoteBoundQuantityUnits
        );
    }

    /**
     * @dev MANAGER ONLY: Withdraws collateral token from the PerpV2 Vault to a default position on the JasperVault.
     * This method is useful when adjusting the overall composition of a Set which has a Perp account external
     * position as one of several components. Any pending funding that would be settled during withdrawl on Perpetual
     * protocol is added to (or subtracted from) `settledFunding[_jasperVault]` and can be withdrawn later using
     * `withdrawFundingAndAccrueFees` by the JasperVault manager.
     *
     * NOTE: Within PerpV2, `withdraw` settles `owedRealizedPnl` and any pending funding payments to the Perp vault
     * prior to transfer.
     *
     * @param  _jasperVault                    Instance of the JasperVault
     * @param  _collateralQuantityUnits     Quantity of collateral to withdraw in position units
     */
    function withdraw(
      IJasperVault _jasperVault,
      uint256 _collateralQuantityUnits
    )
      public
      override
      nonReentrant
      onlyManagerAndValidSet(_jasperVault)
    {
        require(_collateralQuantityUnits > 0, "Withdraw amount is 0");

        _updateSettledFunding(_jasperVault);

        uint256 notionalWithdrawnQuantity = _withdrawAndUpdatePositions(_jasperVault, _collateralQuantityUnits);

        emit CollateralWithdrawn(_jasperVault, collateralToken, notionalWithdrawnQuantity);
    }

    /**
     * @dev MANAGER ONLY: Withdraws tracked settled funding (in USDC) from the PerpV2 Vault to a default position
     * on the JasperVault. Collects manager and protocol performance fees on the withdrawn amount.
     * This method is useful when withdrawing funding to be reinvested into the Basis Trading product.
     * Allows the manager to withdraw entire funding accrued by setting `_notionalFunding` to MAX_UINT_256.
     *
     * NOTE: Within PerpV2, `withdraw` settles `owedRealizedPnl` and any pending funding payments
     * to the Perp vault prior to transfer.
     *
     * @param _jasperVault                 Instance of the JasperVault
     * @param _notionalFunding          Notional amount of funding to withdraw (in USDC decimals)
     */
    function withdrawFundingAndAccrueFees(
        IJasperVault _jasperVault,
        uint256 _notionalFunding
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        if (_notionalFunding == 0) return;

        uint256 newSettledFunding = _updateSettledFunding(_jasperVault);

        uint256 settledFundingInCollateralDecimals = newSettledFunding.fromPreciseUnitToDecimals(collateralDecimals);

        if (_notionalFunding > settledFundingInCollateralDecimals) { _notionalFunding = settledFundingInCollateralDecimals; }

        uint256 collateralBalanceBeforeWithdraw = collateralToken.balanceOf(address(_jasperVault));

        _withdraw(_jasperVault, _notionalFunding);

        (uint256 managerFee, uint256 protocolFee) = _handleFees(_jasperVault, _notionalFunding);

        _updateWithdrawFundingState(_jasperVault, _notionalFunding, collateralBalanceBeforeWithdraw);

        emit FundingWithdrawn(_jasperVault, collateralToken, _notionalFunding, managerFee, protocolFee);
    }

    /**
     * @dev SETTOKEN ONLY: Removes this module from the JasperVault, via call by the SetToken. Deletes
     * position mappings and fee states associated with SetToken. Resets settled funding to zero.
     * Fees are not accrued in case the reason for removing the module is related to fee accrual.
     *
     * NOTE: Function will revert if there is greater than a position unit amount of USDC of account value.
     */
    function removeModule() public override(PerpV2LeverageModuleV2) {
        // Call PerpV2LeverageModuleV2#removeModule to delete positions mapping and unregister on other modules.
        // Verifies Set is valid and initialized.
        PerpV2LeverageModuleV2.removeModule();

        IJasperVault jasperVault = IJasperVault(msg.sender);

        // Not charging any fees
        delete feeSettings[jasperVault];
        delete settledFunding[jasperVault];
    }

    /**
     * @dev MODULE ONLY: Hook called prior to issuance. Only callable by valid module. Should only be called ONCE
     * during issue. Trades into current positions and sets the collateralToken's externalPositionUnit so that
     * issuance module can transfer in the right amount of collateral accounting for accrued fees/pnl and slippage
     * incurred during issuance. Any pending funding payments and accrued owedRealizedPnl are attributed to current
     * Set holders. Any pending funding payment that would be settled during trading into positions on Perpetual
     * protocol is added to (or subtracted from) `settledFunding[_jasperVault]` and can be withdrawn later by the manager.
     *
     * @param _jasperVault             Instance of the SetToken
     * @param _setTokenQuantity     Quantity of Set to issue
     */
    function moduleIssueHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity
    )
        public
        override(PerpV2LeverageModuleV2)
        onlyModule(_jasperVault)
    {
        // Track funding before it is settled
        _updateSettledFunding(_jasperVault);

        // Call PerpV2LeverageModuleV2#moduleIssueHook to set external position unit.
        // Validates caller is module.
        PerpV2LeverageModuleV2.moduleIssueHook(_jasperVault, _setTokenQuantity);
    }

    /**
     * @dev MODULE ONLY: Hook called prior to redemption in the issuance module. Trades out of existing
     * positions to make redemption capital withdrawable from PerpV2 vault. Sets the `externalPositionUnit`
     * equal to the realizable value of account in position units (as measured by the trade outcomes for
     * this redemption) net performance fees to be paid by the redeemer for his share of positive funding yield.
     * Any `owedRealizedPnl` and pending funding payments are socialized in this step so that redeemer
     * pays/receives their share of them. Should only be called ONCE during redeem. Any pending funding payment
     * that would be settled during trading out of positions on Perpetual protocol is added to (or subtracted from)
     * `settledFunding[_jasperVault]` and can be withdrawn later by the manager.
     *
     * @param _jasperVault             Instance of the SetToken
     * @param _setTokenQuantity     Quantity of SetToken to redeem
     */
    function moduleRedeemHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity
    )
        external
        override(PerpV2LeverageModuleV2)
        onlyModule(_jasperVault)
    {
        if (_jasperVault.totalSupply() == 0) return;
        if (!_jasperVault.hasExternalPosition(address(collateralToken))) return;

        // Track funding before it is settled
        uint256 newSettledFunding = _updateSettledFunding(_jasperVault);

        int256 newExternalPositionUnit = _executePositionTrades(_jasperVault, _setTokenQuantity, false, false);

        int256 newExternalPositionUnitNetFees = _calculateNetFeesPositionUnit(_jasperVault, newExternalPositionUnit, newSettledFunding);

        // Set USDC externalPositionUnit such that DIM can use it for transfer calculation
        _jasperVault.editExternalPositionUnit(
            address(collateralToken),
            address(this),
            newExternalPositionUnitNetFees
        );
    }

    /* ============ External Setter Functions ============ */

    /**
     * @dev MANAGER ONLY. Update performance fee percentage.
     *
     * Note: This function requires settled funding (in USD) to be zero. Call `withdrawFundingAndAccrueFees()` with `_notionalAmount`
     * equals MAX_UINT_256 to withdraw all existing settled funding and set settled funding to zero. Funding accrues slowly, so calling
     * this function within a reasonable duration after `withdrawFundingAndAccrueFees` is called, should work in practice.
     *
     * @param _jasperVault         Instance of SetToken
     * @param _newFee           New performance fee percentage in precise units (1e16 = 1%)
     */
    function updatePerformanceFee(
        IJasperVault _jasperVault,
        uint256 _newFee
    )
        external
        onlyManagerAndValidSet(_jasperVault)
    {
        require(_newFee <= feeSettings[_jasperVault].maxPerformanceFeePercentage, "Fee must be less than max");

        // We require `settledFunding[_jasperVault]` to be zero. Hence, we do not call `_updateSettledFunding` here, which
        // eases the UX of updating performance fees for the manager. Although, manager loses the ability to collect fees
        // on pending funding that has been accrued on PerpV2 but not tracked on this module.

        // Assert all settled funding (in USD) has been withdrawn. Comparing USD amount allows us to neglect small
        // dust amounts that aren't withdrawable.
        require(
            settledFunding[_jasperVault].fromPreciseUnitToDecimals(collateralDecimals) == 0,
            "Non-zero settled funding remains"
        );

        feeSettings[_jasperVault].performanceFeePercentage = _newFee;

        emit PerformanceFeeUpdated(_jasperVault, _newFee);
    }

    /**
     * @dev MANAGER ONLY. Update performance fee recipient (address to which performance fees are sent).
     *
     * @param _jasperVault             Instance of SetToken
     * @param _newFeeRecipient      Address of new fee recipient
     */
    function updateFeeRecipient(IJasperVault _jasperVault, address _newFeeRecipient)
        external
        onlyManagerAndValidSet(_jasperVault)
    {
        require(_newFeeRecipient != address(0), "Fee Recipient must be non-zero address");

        feeSettings[_jasperVault].feeRecipient = _newFeeRecipient;

        emit FeeRecipientUpdated(_jasperVault, _newFeeRecipient);
    }


    /* ============ External Getter Functions ============ */

    /**
     * @dev Gets the positive equity collateral externalPositionUnit that would be calculated for
     * redeeming a quantity of SetToken representing the amount of collateral returned per SetToken.
     * Values in the returned arrays map to the same index in the SetToken's components array.
     *
     * @param _jasperVault             Instance of SetToken
     * @param _setTokenQuantity     Number of sets to redeem
     *
     * @return equityAdjustments array containing a single element and an empty debtAdjustments array
     */
    function getRedemptionAdjustments(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity
    )
        external
        override(PerpV2LeverageModuleV2)
        returns (int256[] memory, int256[] memory _)
    {
        int256 newExternalPositionUnitNetFees = 0;

        if (positions[_jasperVault].length > 0) {

            uint256 updatedSettledFunding = getUpdatedSettledFunding(_jasperVault);

            int256 newExternalPositionUnit = _executePositionTrades(_jasperVault, _setTokenQuantity, false, true);

            newExternalPositionUnitNetFees = _calculateNetFeesPositionUnit(_jasperVault, newExternalPositionUnit, updatedSettledFunding);
        }

        return _formatAdjustments(_jasperVault, newExternalPositionUnitNetFees);
    }

    /**
     * @dev Adds pending funding payment to tracked settled funding. Returns updated settled funding value in precise units (10e18).
     *
     * NOTE: Tracked settled funding value can not be less than zero, hence it is reset to zero if pending funding
     * payment is negative and |pending funding payment| >= |settledFunding[_jasperVault]|.
     *
     * NOTE: Returned updated settled funding value is correct only for the current block since pending funding payment
     * updates every block.
     *
     * @param _jasperVault             Instance of SetToken
     */
    function getUpdatedSettledFunding(IJasperVault _jasperVault) public view returns (uint256) {
        // NOTE: pendingFundingPayments are represented as in the Perp system as "funding owed"
        // e.g a positive number is a debt which gets subtracted from owedRealizedPnl on settlement.
        // We are flipping its sign here to reflect its settlement value.
        int256 pendingFundingToBeSettled =  perpExchange.getAllPendingFundingPayment(address(_jasperVault)).neg();

        if (pendingFundingToBeSettled >= 0) {
            return settledFunding[_jasperVault].add(pendingFundingToBeSettled.toUint256());
        }

        if (settledFunding[_jasperVault] > pendingFundingToBeSettled.abs()) {
            return settledFunding[_jasperVault].sub(pendingFundingToBeSettled.abs());
        }

        return 0;
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev Updates tracked settled funding. Once funding is settled to `owedRealizedPnl` on Perpetual protocol, it is difficult to
     * extract out the funding value again on-chain. This function is called in an external function and is used to track and store
     * pending funding payment that is about to be settled due to subsequent logic in the external function.
     *
     * @param _jasperVault             Instance of SetToken
     * @return uint256              Returns the updated settled funding value
     */
    function _updateSettledFunding(IJasperVault _jasperVault) internal returns (uint256) {
        uint256 newSettledFunding = getUpdatedSettledFunding(_jasperVault);
        settledFunding[_jasperVault] = newSettledFunding;
        return newSettledFunding;
    }

    /**
     * @dev Calculates manager and protocol fees on withdrawn funding amount and transfers them to
     * their respective recipients (in USDC).
     *
     * @param _jasperVault                     Instance of SetToken
     * @param _notionalFundingAmount        Notional funding amount on which fees is charged
     *
     * @return managerFee      Manager performance fees
     * @return protocolFee     Protocol performance fees
     */
    function _handleFees(
        IJasperVault _jasperVault,
        uint256 _notionalFundingAmount
    )
        internal
        returns (uint256 managerFee, uint256 protocolFee)
    {
        uint256 performanceFee = feeSettings[_jasperVault].performanceFeePercentage;

        if (performanceFee > 0) {
            uint256 protocolFeeSplit = controller.getModuleFee(address(this), PROTOCOL_PERFORMANCE_FEE_INDEX);

            uint256 totalFee = performanceFee.preciseMul(_notionalFundingAmount);
            protocolFee = totalFee.preciseMul(protocolFeeSplit);
            managerFee = totalFee.sub(protocolFee);

            _jasperVault.strictInvokeTransfer(address(collateralToken), feeSettings[_jasperVault].feeRecipient, managerFee);
            payProtocolFeeFromSetToken(_jasperVault, address(collateralToken), protocolFee);
        }

        return (managerFee, protocolFee);
    }

    /**
     * @dev Updates collateral token default position unit and tracked settled funding. Used in `withdrawFundingAndAccrueFees()`
     *
     * @param _jasperVault                         Instance of the SetToken
     * @param _notionalFunding                  Amount of funding withdrawn (in USDC decimals)
     * @param _collateralBalanceBeforeWithdraw  Balance of collateral token in the Set before withdrawing more USDC from Perp
     */
    function _updateWithdrawFundingState(IJasperVault _jasperVault, uint256 _notionalFunding, uint256 _collateralBalanceBeforeWithdraw) internal {
        // Update default position unit to add the withdrawn funding (in USDC)
        _jasperVault.calculateAndEditDefaultPosition(
            address(collateralToken),
            _jasperVault.totalSupply(),
            _collateralBalanceBeforeWithdraw
        );

        _updateExternalPositionUnit(_jasperVault);

        // Subtract withdrawn funding from tracked settled funding
        settledFunding[_jasperVault] = settledFunding[_jasperVault].sub(
            _notionalFunding.toPreciseUnitsFromDecimals(collateralDecimals)
        );
    }

    /**
     * @dev Returns external position unit net performance fees. Calculates performance fees unit and subtracts it from `_newExternalPositionUnit`.
     *
     * @param _jasperVault                     Instance of SetToken
     * @param _newExternalPositionUnit      New external position unit calculated using `_executePositionTrades`
     * @param _updatedSettledFunding        Updated track settled funding value
     */
    function _calculateNetFeesPositionUnit(
        IJasperVault _jasperVault,
        int256 _newExternalPositionUnit,
        uint256 _updatedSettledFunding
    )
        internal view returns (int256)
    {
        if (_updatedSettledFunding == 0) {
            return _newExternalPositionUnit;
        }

        // Calculate performance fee unit; Performance fee unit = (Tracked settled funding * Performance fee) / Set total supply
        uint256 performanceFeeUnit = _updatedSettledFunding
            .preciseDiv(_jasperVault.totalSupply())
            .preciseMulCeil(_performanceFeePercentage(_jasperVault))
            .fromPreciseUnitToDecimals(collateralDecimals);

        // Subtract performance fee unit from `_newExternalPositionUnit` to get `newExternalPositionUnitNetFees`.
        // Issuance module calculates equity amount by multiplying position unit with `_setTokenQuanity`, so,
        // equity amount = newExternalPositionUnitNetFees * _setTokenQuantity = (_newExternalPositionUnit - performanceFeeUnit) * _setTokenQuantity
        // where, `performanceFeeUnit * _setTokenQuantity` is share of the total performance fee to be paid by the redeemer.
        int newExternalPositionUnitNetFees = _newExternalPositionUnit.sub(performanceFeeUnit.toInt256());

        // Ensure the returned position unit is >= 0. Module is market neutral and some combination of high performance fee,
        // high yield, and low position values could lead to the position unit being negative.
        if (newExternalPositionUnitNetFees < 0) { newExternalPositionUnitNetFees = 0; }

        return newExternalPositionUnitNetFees;
    }

    /**
     * @dev Validates fee settings.
     *
     * @param _settings     FeeState struct containing performance fee settings
     */
    function _validateFeeState(FeeState memory _settings) internal pure {
        require(_settings.feeRecipient != address(0), "Fee Recipient must be non-zero address");
        require(_settings.maxPerformanceFeePercentage <= PreciseUnitMath.preciseUnit(), "Max fee must be <= 100%");
        require(_settings.performanceFeePercentage <= _settings.maxPerformanceFeePercentage, "Fee must be <= max");
    }

    /**
     * @dev Helper function that returns performance fee percentage.
     *
     * @param _jasperVault     Instance of SetToken
     */
    function _performanceFeePercentage(IJasperVault _jasperVault) internal view returns (uint256) {
        return feeSettings[_jasperVault].performanceFeePercentage;
    }

}
