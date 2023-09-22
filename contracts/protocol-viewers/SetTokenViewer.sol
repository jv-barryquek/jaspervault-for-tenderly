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


import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IJasperVault } from "../interfaces/IJasperVault.sol";


/**
 * @title SetTokenViewer
 * @author Set Protocol
 *
 * SetTokenViewer enables batch queries of SetToken state.
 *
 * UPDATE:
 * - Added getSetDetails functions
 */
contract SetTokenViewer {

    struct SetDetails {
        string name;
        string symbol;
        address manager;
        address[] modules;
        IJasperVault.ModuleState[] moduleStatuses;
        IJasperVault.Position[] positions;
        uint256 totalSupply;
    }

    function batchFetchManagers(
        IJasperVault[] memory _setTokens
    )
        external
        view
        returns (address[] memory)
    {
        address[] memory managers = new address[](_setTokens.length);

        for (uint256 i = 0; i < _setTokens.length; i++) {
            managers[i] = _setTokens[i].manager();
        }
        return managers;
    }

    function batchFetchModuleStates(
        IJasperVault[] memory _setTokens,
        address[] calldata _modules
    )
        public
        view
        returns (IJasperVault.ModuleState[][] memory)
    {
        IJasperVault.ModuleState[][] memory states = new IJasperVault.ModuleState[][](_setTokens.length);
        for (uint256 i = 0; i < _setTokens.length; i++) {
            IJasperVault.ModuleState[] memory moduleStates = new IJasperVault.ModuleState[](_modules.length);
            for (uint256 j = 0; j < _modules.length; j++) {
                moduleStates[j] = _setTokens[i].moduleStates(_modules[j]);
            }
            states[i] = moduleStates;
        }
        return states;
    }

    function batchFetchDetails(
        IJasperVault[] memory _setTokens,
        address[] calldata _moduleList
    )
        public
        view
        returns (SetDetails[] memory)
    {
        IJasperVault.ModuleState[][] memory moduleStates = batchFetchModuleStates(_setTokens, _moduleList);

        SetDetails[] memory details = new SetDetails[](_setTokens.length);
        for (uint256 i = 0; i < _setTokens.length; i++) {
            IJasperVault jasperVault = _setTokens[i];

            details[i] = SetDetails({
                name: ERC20(address(jasperVault)).name(),
                symbol: ERC20(address(jasperVault)).symbol(),
                manager: jasperVault.manager(),
                modules: jasperVault.getModules(),
                moduleStatuses: moduleStates[i],
                positions: jasperVault.getPositions(),
                totalSupply: jasperVault.totalSupply()
            });
        }
        return details;
    }

    function getSetDetails(
        IJasperVault _jasperVault,
        address[] calldata _moduleList
    )
        external
        view
        returns(SetDetails memory)
    {
        IJasperVault[] memory setAddressForBatchFetch = new IJasperVault[](1);
        setAddressForBatchFetch[0] = _jasperVault;

        return batchFetchDetails(setAddressForBatchFetch, _moduleList)[0];
    }
}
