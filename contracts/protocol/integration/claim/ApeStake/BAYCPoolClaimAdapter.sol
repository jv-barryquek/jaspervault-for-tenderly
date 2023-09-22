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
 * @title BAYCPoolClaimAdapter
 * @author Jasper Vault
 *
 * Claim adapter that allows managers to claim ApeCoin from BAYC NFT and ApeCoin pair(s) staked in the ApeStake staking contract. See the 'SingleNft' struct in the `ApeStakingAdapter.sol` file/the ApeStake Staking Contract API for the shape of this data structure.
 * As per the ClaimModule's design, we have 4 different adapters for claiming rewards from the 4 different pools accessible via ApeStake's staking contract.
 */
contract BAYCPoolClaimAdapter {
  /* ============ State Variables ============ */
  IApeStake private apeStakeStakingContract;
  address public APECOIN_TOKEN_ADDRESS;
  uint256 public BAYC_POOL_ID;

  /* ============ Constructor ============ */

  /**
   * Set state variables
   *
   */
  constructor(
    IApeStake _apeStakeContract,
    address _apeCoinTokenAddress,
    uint256 baycPoolId
  ) public {
    apeStakeStakingContract = _apeStakeContract;
    APECOIN_TOKEN_ADDRESS = _apeCoinTokenAddress;
    BAYC_POOL_ID = baycPoolId;
  }

  /* ============ External Getter Functions ============ */

  /**
   * Generates the calldata for claiming all COMP tokens for the JasperVault.
   * https://compound.finance/docs/comptroller#claim-comp
   *
   * @param _jasperVault     Set token address
   * _rewardPool          Not specified as parameter as the pool is located in ApeStake's staking contract, whose address is initialized when this adapter is constructed.
   * @param _additionalClaimData Arbtirary bytes containing additional arguments as needed by specific protocol
   *
   * @return address      Contract holding the reward pool
   * @return uint256      Unused, since it claims total claimable balance
   * @return bytes        Claim calldata
   */
  function getClaimCallData(
    IJasperVault _jasperVault,
    address /* _rewardPool */,
    bytes memory _additionalClaimData
  ) external view returns (address, uint256, bytes memory) {
    require(
      _additionalClaimData.length > 0,
      "IDs of BAYC NFTs committed must be given to claim staking rewards"
    );
    uint256[] memory nftIds = abi.decode(_additionalClaimData, (uint256[]));
    bytes memory callData = abi.encodeWithSignature(
      "claimBAYC(uint256[], address)",
      nftIds,
      address(_jasperVault)
    );

    return (address(apeStakeStakingContract), 0, callData);
  }

  /**
   * Returns balance of pending ApeCoin reward for _jasperVault's stake
   * @param _jasperVault     Set token address
   * _rewardPool          Not specified as parameter as the pool is located in ApeStake's staking contract, whose address is initialized when this adapter is constructed.
   * @param _data         Encoded arguments for `pendingRewards()` function on ApeStake staking contract. In this case, the id of an NFT committed by _jasperVault into the BAYC pool should be encoded.
   *
   * @return uint256      Claimable ApeCoin balance
   */
  function getRewardsAmount(
    IJasperVault _jasperVault,
    address /* _rewardPool */,
    bytes memory _data
  ) external returns (uint256) {
    require(
      _data.length > 0,
      "ID of BAYC NFT committed must be given to see pending stake rewards"
    );
    uint256 nftId = abi.decode(_data, (uint256));
    return
      apeStakeStakingContract.pendingRewards(
        BAYC_POOL_ID,
        address(_jasperVault),
        nftId
      );
  }

  /**
   * Returns reward token address
   * _rewardPool          Param not used as ApeStake contract does not provide API for returning ApeCoin token address
   *
   * @return address      reward token address
   */
  function getTokenAddress(
    address /* _rewardPool */
  ) external view returns (address) {
    return APECOIN_TOKEN_ADDRESS;
  }
}
