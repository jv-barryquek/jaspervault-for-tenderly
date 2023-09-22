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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IJasperVault } from "./IJasperVault.sol";

pragma solidity 0.6.10;

/**
 * @title IClaimAdapter
 * @author Set Protocol
 *
 */
interface IClaimAdapter {

    /**
     * Generates the calldata for claiming tokens from the rewars pool
     *
     * @param _jasperVault     the set token that is owed the tokens
     * @param _rewardPool   the rewards pool to claim from
     *
     * @return _subject     the rewards pool to call
     * @return _value       the amount of ether to send in the call
     * @return _calldata    the calldata to use
     */
    function getClaimCallData(
        IJasperVault _jasperVault,
        address _rewardPool
    ) external view returns(address _subject, uint256 _value, bytes memory _calldata);

    /**
     * Gets the amount of unclaimed rewards
     *
     * @param _jasperVault     the set token that is owed the tokens
     * @param _rewardPool   the rewards pool to check
     *
     * @return uint256      the amount of unclaimed rewards
     */
    function getRewardsAmount(IJasperVault _jasperVault, address _rewardPool) external view returns(uint256);

    /**
     * Gets the rewards token
     *
     * @param _rewardPool   the rewards pool to check
     *
     * @return IERC20       the reward token
     */
    function getTokenAddress(address _rewardPool) external view returns(IERC20);
}