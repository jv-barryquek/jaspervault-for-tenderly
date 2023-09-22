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
pragma experimental "ABIEncoderV2";

import {IApeStake} from "../../../../interfaces/external/IApeStake.sol";
import {IJasperVault} from "../../../../interfaces/IJasperVault.sol";

/**
 * @title BAKCPoolClaimAdapter
 * @author Jasper Vault
 *
 * Claim adapter that allows managers to claim ApeCoin from BAYC-BAKC and MAYC-BAKC NFT Pair(s) committed with ApeCoins staked in the ApeStake staking contract. See the 'PairNftDepositWithAmount' struct in the `ApeStakingAdapter.sol` file/the ApeStake Staking Contract API for the shape of this data structure.
 * As per the ClaimModule's design, we have 4 different adapters for claiming rewards from the 4 different pools accessible via ApeStake's staking contract.
 */
contract BAKCPoolClaimAdapter {
  /* ============ Structs ============ */
  // from ApeStake's staking contract
  struct PairNft {
    uint128 mainTokenId;
    uint128 bakcTokenId;
  }

  /* ============ State Variables ============ */
  IApeStake private apeStakeStakingContract;
  address public APECOIN_TOKEN_ADDRESS;
  uint256 public BAKC_POOL_ID;

  /* ============ Constructor ============ */

  /**
   * Set state variables
   *
   */
  constructor(
    IApeStake _apeStakeContract,
    address _apeCoinTokenAddress,
    uint256 bakcPoolId
  ) public {
    apeStakeStakingContract = _apeStakeContract;
    APECOIN_TOKEN_ADDRESS = _apeCoinTokenAddress;
    BAKC_POOL_ID = bakcPoolId;
  }

  /* ============ External Getter Functions ============ */

  /**
   * Generates the calldata for claiming all COMP tokens for the JasperVault.
   * https://compound.finance/docs/comptroller#claim-comp
   *
   * @param _jasperVault     Set token address
   * _rewardPool          Not specified as parameter as the pool is located in ApeStake's staking contract, whose address is initialized when this adapter is constructed.
   * @param _additionalClaimData  Encoded args for claimBAKC function
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
      "Ids of BAKC and BAYC/MAYC NFT pairs used in stake must be provided"
    );
    (PairNft[] memory baycBakcStakes, PairNft[] memory maycBakcStakes) = abi
      .decode(_additionalClaimData, (PairNft[], PairNft[]));
    bytes memory callData = abi.encodeWithSignature(
      "claimBAKC((uint128,uint128)[],(uint128,uint128)[],address)",
      baycBakcStakes,
      maycBakcStakes,
      address(_jasperVault)
    );
    return (address(apeStakeStakingContract), 0, callData);
  }

  /**
   * Returns balance of pending ApeCoin reward for _jasperVault's stake including BAKC token.
   * @param _jasperVault     Set token address
   * _rewardPool          Not specified as parameter as the pool is located in ApeStake's staking contract, whose address is initialized when this adapter is constructed.
   * @param _data         Encoded arguments for `pendingRewards()` function on ApeStake staking contract. In this case, the id of an NFT committed by _jasperVault into the Pair pool should be encoded.
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
      "ID of BAKC NFT committed must be given to see pending stake rewards"
    );
    uint256 nftId = abi.decode(_data, (uint256));
    return
      apeStakeStakingContract.pendingRewards(
        BAKC_POOL_ID,
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
