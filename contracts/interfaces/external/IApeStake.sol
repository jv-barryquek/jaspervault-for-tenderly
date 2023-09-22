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

import {ICErc20} from "./ICErc20.sol";

/**
 * @title IApeStake
 * @author ApeStake
 *
 * Interface for interacting with ApeStake Staking contract
 */
interface IApeStake {
  function addressPosition(
    address staker
  ) external returns (uint256 stakedAmount, int256 rewardsDebt);

  function pendingRewards(
    uint256 poolId,
    address staker,
    uint256 nftId
  ) external returns (uint256 pendingRewards);
}
