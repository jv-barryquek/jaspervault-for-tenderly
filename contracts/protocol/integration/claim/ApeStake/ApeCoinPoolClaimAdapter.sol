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

import {IApeStake} from "../../../../interfaces/external/IApeStake.sol";
import {IJasperVault} from "../../../../interfaces/IJasperVault.sol";

/**
 * @title ApeCoinPoolClaimAdapter
 * @author Jasper Vault
 *
 * Claim adapter that allows managers to claim ApeCoin reward from ApeCoin staked in the ApeStake staking contract.
 * As per the ClaimModule's design, we have 4 different adapters for claiming rewards from the 4 different pools accessible via ApeStake's staking contract.
 */
contract ApeCoinPoolClaimAdapter {
  /* ============ State Variables ============ */
  IApeStake apeStakeStakingContract;
  address public APECOIN_TOKEN_ADDRESS;
  uint256 public APECOIN_POOL_ID;

  /* ============ Constructor ============ */
  /**
   * Set state variables
   *
   */
  constructor(
    IApeStake _apeStakeContract,
    address _apeCoinTokenAddress,
    uint256 apeCoinPoolId
  ) public {
    apeStakeStakingContract = _apeStakeContract;
    APECOIN_TOKEN_ADDRESS = _apeCoinTokenAddress;
    APECOIN_POOL_ID = apeCoinPoolId;
  }

  /* ============ External Getter Functions ============ */

  /**
   * Generates the calldata for claiming ApeCoin token rewards for the JasperVault.
   * https://compound.finance/docs/comptroller#claim-comp
   *
   * @param _jasperVault     Set token address
   * _rewardPool          Not specified as parameter as the pool is located in ApeStake's staking contract, whose address is initialized when this adapter is constructed.
   * _additionalClaimData Arbtirary bytes containing additional arguments as needed by specific protocol
   *
   * @return address      Contract holding the reward pool
   * @return uint256      Unused, since it claims total claimable balance
   * @return bytes        Claim calldata
   */
  function getClaimCallData(
    IJasperVault _jasperVault,
    address /* _rewardPool */,
    bytes memory /*_additionalClaimData*/
  ) external view returns (address, uint256, bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "claimApeCoin(address)",
      address(_jasperVault)
    );

    return (address(apeStakeStakingContract), 0, callData);
  }

  /**
   * Returns balance of pending ApeCoin reward for _jasperVault's stake
   * @param _jasperVault     Set token address
   * _rewardPool          Not specified as parameter as the pool is located in ApeStake's staking contract, whose address is initialized when this adapter is constructed.
   * _data         Not specified as parameter as pending reward can be gotten by simply calling the `addressPosition` getter with _jasperVautl param
   *
   * @return uint256      Claimable ApeCoin balance
   */
  function getRewardsAmount(
    IJasperVault _jasperVault,
    address /* _rewardPool */,
    bytes memory /* _data */
  ) external returns (int256) {
    (, int256 rewardsDebt) = apeStakeStakingContract.addressPosition(
      address(_jasperVault)
    );
    return rewardsDebt;
  }

  /**
   * Returns ApeCoin token address
   * _rewardPool          Param not used as ApeStake contract does not provide API for returning ApeCoin token address
   *
   * @return address      ApeCoin token address
   */
  function getTokenAddress(
    address /* _rewardPool */
  ) external view returns (address) {
    return APECOIN_TOKEN_ADDRESS;
  }
}
