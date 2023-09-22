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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";

import { IJasperVault } from "../../../interfaces/IJasperVault.sol";
import { IModuleIssuanceHook } from "../../../interfaces/IModuleIssuanceHook.sol";
import { Invoke } from "../../../protocol/lib/Invoke.sol";
import { Position } from "../../../protocol/lib/Position.sol";
import { PreciseUnitMath } from "../../../lib/PreciseUnitMath.sol";

contract ModuleIssuanceHookMock is IModuleIssuanceHook {
    using Invoke for IJasperVault;
    using Position for IJasperVault;
    using SafeCast for int256;
    using PreciseUnitMath for uint256;

    function initialize(IJasperVault _jasperVault) external {
        _jasperVault.initializeModule();
    }

    function addExternalPosition(IJasperVault _jasperVault, address _component, int256 _quantity) external {
        _jasperVault.editExternalPosition(_component, address(this), _quantity, "");
    }

    function moduleIssueHook(IJasperVault _jasperVault, uint256 _setTokenQuantity) external override {}
    function moduleRedeemHook(IJasperVault _jasperVault, uint256 _setTokenQuantity) external override {}

    function componentIssueHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity,
        IERC20 _component,
        bool /* _isEquity */
    ) external override {
        int256 externalPositionUnit = _jasperVault.getExternalPositionRealUnit(address(_component), address(this));
        uint256 totalNotionalExternalModule = _setTokenQuantity.preciseMul(externalPositionUnit.toUint256());

        // Invoke the JasperVault to send the token of total notional to this address
        _jasperVault.invokeTransfer(address(_component), address(this), totalNotionalExternalModule);
    }

    function componentRedeemHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity,
        IERC20 _component,
        bool /* _isEquity */
    ) external override {
        // Send the component to the settoken
        int256 externalPositionUnit = _jasperVault.getExternalPositionRealUnit(address(_component), address(this));
        uint256 totalNotionalExternalModule = _setTokenQuantity.preciseMul(externalPositionUnit.toUint256());
        _component.transfer(address(_jasperVault), totalNotionalExternalModule);
    }
}
