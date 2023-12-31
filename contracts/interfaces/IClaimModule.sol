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

import { IJasperVault } from "./IJasperVault.sol";

interface IClaimModule {
    function initialize(
        IJasperVault _jasperVault,
        bool _anyoneClaim,
        address[] calldata _rewardPools,
        string[] calldata _integrationNames
    ) external;

    function anyoneClaim(IJasperVault _jasperVault) external view returns(bool);
    function claim(IJasperVault _jasperVault, address _rewardPool, string calldata _integrationName) external;
    function batchClaim(IJasperVault _jasperVault, address[] calldata _rewardPools, string[] calldata _integrationNames) external;
    function updateAnyoneClaim(IJasperVault _jasperVault, bool _anyoneClaim) external;
    function addClaim(IJasperVault _jasperVault, address _rewardPool, string calldata _integrationName) external;
    function batchAddClaim(IJasperVault _jasperVault, address[] calldata _rewardPools, string[] calldata _integrationNames) external;
    function removeClaim(IJasperVault _jasperVault, address _rewardPool, string calldata _integrationName) external;
    function batchRemoveClaim(IJasperVault _jasperVault, address[] calldata _rewardPools, string[] calldata _integrationNames) external;
    function removeModule() external;
    function getRewardPools(IJasperVault _jasperVault) external returns(address[] memory);
    function isRewardPool(IJasperVault _jasperVault, address _rewardPool) external returns(bool);
    function getRewardPoolClaims(IJasperVault _jasperVault, address _rewardPool) external returns(address[] memory);
    function isRewardPoolClaim(IJasperVault _jasperVault, address _rewardPool, string calldata _integrationName) external returns (bool);
    function getRewards(IJasperVault _jasperVault, address _rewardPool, string calldata _integrationName) external returns (uint256);
}
