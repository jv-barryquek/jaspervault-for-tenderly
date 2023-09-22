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

import { AddressArrayUtils } from "../lib/AddressArrayUtils.sol";
import { IJasperVault } from "./IJasperVault.sol";

interface IAirdropModule {
    using AddressArrayUtils for address[];

    struct AirdropSettings {
        address[] airdrops;                     // Array of tokens manager is allowing to be absorbed
        address feeRecipient;                   // Address airdrop fees are sent to
        uint256 airdropFee;                     // Percentage in preciseUnits of airdrop sent to feeRecipient (1e16 = 1%)
        bool anyoneAbsorb;                      // Boolean indicating if any address can call absorb or just the manager
    }

    struct AirdropReturnSettings {
        address feeRecipient;
        uint256 airdropFee;
        bool anyoneAbsorb;
    }

    function initialize(IJasperVault _jasperVault, AirdropSettings memory _airdropSettings) external;

    function airdropSettings(IJasperVault _jasperVault) external view returns(AirdropReturnSettings memory);
    function batchAbsorb(IJasperVault _jasperVault, address[] memory _tokens) external;
    function absorb(IJasperVault _jasperVault, IERC20 _token) external;
    function addAirdrop(IJasperVault _jasperVault, IERC20 _airdrop) external;
    function removeAirdrop(IJasperVault _jasperVault, IERC20 _airdrop) external;
    function updateAnyoneAbsorb(IJasperVault _jasperVault, bool _anyoneAbsorb) external;
    function updateFeeRecipient(IJasperVault _jasperVault, address _newFeeRecipient) external;
    function updateAirdropFee(IJasperVault _jasperVault, uint256 _newFee) external;
    function removeModule() external;
    function getAirdrops(IJasperVault _jasperVault) external returns(address[] memory);
    function isAirdropToken(IJasperVault _jasperVault, IERC20 _token) external returns(bool);
}
