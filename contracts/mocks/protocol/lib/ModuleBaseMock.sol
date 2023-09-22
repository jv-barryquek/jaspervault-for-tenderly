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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IController } from "../../../interfaces/IController.sol";
import { IJasperVault } from "../../../interfaces/IJasperVault.sol";
import { ModuleBase } from "../../../protocol/lib/ModuleBase.sol";

contract ModuleBaseMock is ModuleBase {

    bool public removed;

    constructor(IController _controller) public ModuleBase(_controller) {}

    /* ============ External Functions ============ */

    function testTransferFrom(IERC20 _token, address _from, address _to, uint256 _quantity) external {
        return transferFrom(_token, _from, _to, _quantity);
    }


    function testIsSetPendingInitialization(IJasperVault _jasperVault) external view returns(bool) {
        return isSetPendingInitialization(_jasperVault);
    }

    function testIsSetManager(IJasperVault _jasperVault, address _toCheck) external view returns(bool) {
        return isSetManager(_jasperVault, _toCheck);
    }

    function testIsSetValidAndInitialized(IJasperVault _jasperVault) external view returns(bool) {
        return isSetValidAndInitialized(_jasperVault);
    }

    function testOnlyManagerAndValidSet(IJasperVault _jasperVault)
        external
        view
        onlyManagerAndValidSet(_jasperVault)
    {}

    function testGetAndValidateAdapter(string memory _integrationName) external view returns(address) {
        return getAndValidateAdapter(_integrationName);
    }

    function testGetAndValidateAdapterWithHash(bytes32 _integrationHash) external view returns(address) {
        return getAndValidateAdapterWithHash(_integrationHash);
    }

    function testGetModuleFee(uint256 _feeIndex, uint256 _quantity) external view returns(uint256) {
        return getModuleFee(_feeIndex, _quantity);
    }

    function testPayProtocolFeeFromSetToken(
        IJasperVault _jasperVault,
        address _component,
        uint256 _feeQuantity
    ) external {
        payProtocolFeeFromSetToken(_jasperVault, _component, _feeQuantity);
    }

    function testOnlySetManager(IJasperVault _jasperVault)
        external
        view
        onlySetManager(_jasperVault, msg.sender)
    {}

    function testOnlyModule(IJasperVault _jasperVault)
        external
        view
        onlyModule(_jasperVault)
    {}


    function removeModule() external override {
        removed = true;
    }

    function testOnlyValidAndInitializedSet(IJasperVault _jasperVault)
        external view onlyValidAndInitializedSet(_jasperVault) {}

    function testOnlyValidInitialization(IJasperVault _jasperVault)
        external view onlyValidAndPendingSet(_jasperVault) {}

    /* ============ Helper Functions ============ */

    function initializeModuleOnSet(IJasperVault _jasperVault) external {
        _jasperVault.initializeModule();
    }
}
