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

import { IJasperVault } from "../../interfaces/IJasperVault.sol";

import { BaseGlobalExtension } from "../lib/BaseGlobalExtension.sol";
import { IDelegatedManager } from "../interfaces/IDelegatedManager.sol";
import { IManagerCore } from "../interfaces/IManagerCore.sol";
import { ModuleMock } from "./ModuleMock.sol";
contract BaseGlobalExtensionMock is BaseGlobalExtension {

    /* ============ State Variables ============ */

    ModuleMock public immutable module;

    /* ============ Constructor ============ */

    constructor(
        IManagerCore _managerCore,
        ModuleMock _module
    )
        public
        BaseGlobalExtension(_managerCore)
    {
        module = _module;
    }

    /* ============ External Functions ============ */

    function initializeExtension(
        IDelegatedManager _delegatedManager
    )
        external
        onlyOwnerAndValidManager(_delegatedManager)
    {
        require(_delegatedManager.isPendingExtension(address(this)), "Extension must be pending");

        _initializeExtension(_delegatedManager.jasperVault(), _delegatedManager);
    }

    function initializeModuleAndExtension(
        IDelegatedManager _delegatedManager
    )
        external
        onlyOwnerAndValidManager(_delegatedManager)
    {
        require(_delegatedManager.isPendingExtension(address(this)), "Extension must be pending");

        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        bytes memory callData = abi.encodeWithSignature("initialize(address)", jasperVault);
        _invokeManager(_delegatedManager, address(module), callData);
    }

    function testInvokeManager(IJasperVault _jasperVault, address _module, bytes calldata _encoded) external {
        _invokeManager(_manager(_jasperVault), _module, _encoded);
    }

    function testOnlyOwner(IJasperVault _jasperVault)
        external
        onlyOwner(_jasperVault)
    {}

    function testOnlyMethodologist(IJasperVault _jasperVault)
        external
        onlyMethodologist(_jasperVault)
    {}

    function testOnlyOperator(IJasperVault _jasperVault)
        external
        onlyOperator(_jasperVault)
    {}

    function testOnlyOwnerAndValidManager(IDelegatedManager _delegatedManager)
        external
        onlyOwnerAndValidManager(_delegatedManager)
    {}

    function testOnlyAllowedAsset(IJasperVault _jasperVault, address _asset)
        external
        onlyAllowedAsset(_jasperVault, _asset)
    {}

    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();

        _removeExtension(jasperVault, delegatedManager);
    }
}
