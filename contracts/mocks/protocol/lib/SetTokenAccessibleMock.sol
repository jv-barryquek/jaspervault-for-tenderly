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

import { IController } from "../../../interfaces/IController.sol";
import { IJasperVault } from "../../../interfaces/IJasperVault.sol";
import { SetTokenAccessible } from "../../../protocol/lib/SetTokenAccessible.sol";

contract SetTokenAccessibleMock is SetTokenAccessible {

    constructor(IController _controller) public SetTokenAccessible(_controller) {}

    /* ============ External Functions ============ */

    function testOnlyAllowedSet(IJasperVault _jasperVault)
        external
        view
        onlyAllowedSet(_jasperVault) {}

    /* ============ Helper Functions ============ */

    function initializeModuleOnSet(IJasperVault _jasperVault) external {
        _jasperVault.initializeModule();
    }
}
