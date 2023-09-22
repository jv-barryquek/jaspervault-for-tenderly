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
pragma experimental "ABIEncoderV2"; // note: necessary for decoding and encoding struct[] types

import "hardhat/console.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @title ApeStakingAdapter
 * @author JasperVault Protocol
 *
 * Staking adapter for ApeCoin Staking that returns calldata to stake/unstake tokens, as well as claim rewards
 * ! < === Still To Be Tested === >
 */
contract ApeStakingAdapter {
  using SafeMath for uint256;

  /* ============ Structs ============ */
  // note : these structs are from ApeStake's Staking contract API specification
  struct SingleNft {
    uint32 tokenId;
    uint224 amount;
  }
  struct PairNftDepositWithAmount {
    uint32 mainTokenId;
    uint32 bakcTokenId;
    uint184 amount;
  }
  struct PairNftWithdrawWithAmount {
    uint32 mainTokenId;
    uint32 bakcTokenId;
    uint184 amount;
    bool isUncommit;
  }
  /* ============ State Variables ============ */
  uint256 public APESTAKE_APECOIN_POOL_ID;
  uint256 public APESTAKE_BAYC_POOL_ID;
  uint256 public APESTAKE_MAYC_POOL_ID;
  uint256 public APESTAKE_BAKC_POOL_ID;
  uint224 public BAYC_PER_TOKEN_STAKE_CAP;
  uint224 public MAYC_PER_TOKEN_STAKE_CAP;
  uint224 public BAKC_PER_TOKEN_STAKE_CAP;

  // note: ApeStake docs doesn't state a cap for the Pair Pool? But sources online state that there is a cap.

  /* ============ Constructor ============ */

  constructor(
    uint256 _apeCoinPoolId,
    uint256 _baycPoolId,
    uint256 _maycPoolId,
    uint256 _bakcPoolId,
    uint224 _baycPoolCap,
    uint224 _maycPoolCap,
    uint224 _bakcPoolCap
  ) public {
    APESTAKE_APECOIN_POOL_ID = _apeCoinPoolId;
    BAYC_PER_TOKEN_STAKE_CAP = _baycPoolCap;
    MAYC_PER_TOKEN_STAKE_CAP = _maycPoolCap;
    APESTAKE_BAYC_POOL_ID = _baycPoolId;
    APESTAKE_MAYC_POOL_ID = _maycPoolId;
    APESTAKE_BAKC_POOL_ID = _bakcPoolId;
    BAKC_PER_TOKEN_STAKE_CAP = _bakcPoolCap;
  }

  /* ============ External Functions ============ */

  /**
   * Generates the calldata to stake lp tokens in the staking contract
   *
   * @param _stakingContract          Address of the gauge staking contract
   * @param _notionalAmount           Quantity of token to stake
   * @param _additionalStakeData      Data should be encoded in this order: a uint256 pool ID and either a SingleNft[] if staking in BAYC or MAYC Pool, or another uint256 and a PairNftDepositWithAmount[] if staking in BAKC. See comment in `getUnstakeCallData` signature for design of encoding arguments for BAKC staking.
   * @return address                  Target address
   * @return uint256                  Call value
   * @return bytes                    Stake tokens calldata
   */
  function getStakeCallData(
    address _stakingContract,
    uint256 _notionalAmount,
    bytes calldata _additionalStakeData
  ) external view returns (address, uint256, bytes memory) {
    require(_notionalAmount > 0, "must be depositing at least 1 ApeCoin");
    require(
      _additionalStakeData.length >= 32,
      "at least poolId to be specified in _additionalStakeData"
    );
    bytes memory callData;
    uint256 poolId = abi.decode(_additionalStakeData, (uint256));
    if (poolId == APESTAKE_APECOIN_POOL_ID) {
      callData = _getStakeInApeCoinPoolCallData(_notionalAmount);
    } else if (
      poolId == APESTAKE_BAYC_POOL_ID || poolId == APESTAKE_MAYC_POOL_ID
    ) {
      callData = _getStakeInBAYCOrMAYCPoolCallData(
        _notionalAmount,
        _additionalStakeData
      );
    } else if (poolId == APESTAKE_BAKC_POOL_ID) {
      callData = _getStakeInPairPoolCallData(
        _notionalAmount,
        _additionalStakeData
      );
    } else {
      revert("unrecognised poolId");
    }
    return (_stakingContract, 0, callData);
  }

  /**
   * Generates the calldata to unstake lp tokens from the staking contract
   *
   * @param _stakingContract          Address of the gauge staking contract
   * @param _notionalAmount           Quantity of token to stake
   * @param _additionalUnstakeData      Data should be encoded in this order: a uint256 pool ID and if withdrawing from the BAKC pool, the additional args required
   *
   * @return address                  Target address
   * @return uint256                  Call value
   * @return bytes                    Unstake tokens calldata
   */
  function getUnstakeCallData(
    address _stakingContract,
    uint256 _notionalAmount,
    bytes calldata _additionalUnstakeData
  ) external view returns (address, uint256, bytes memory) {
    require(_notionalAmount > 0, "must be withdrawing more than 0 ApeCoin");
    require(
      _additionalUnstakeData.length >= 32,
      "at least poolId to be specified in _additionalUnstakeData"
    );
    bytes memory callData;
    string memory withdrawFunctionToCall;
    uint256 poolId = abi.decode(_additionalUnstakeData, (uint256));

    if (poolId == APESTAKE_APECOIN_POOL_ID) {
      withdrawFunctionToCall = "withdrawSelfApeCoin(uint256)";
      callData = abi.encodeWithSignature(
        withdrawFunctionToCall,
        _notionalAmount
      );
      // -- lines added to make it easier to read
    } else if (poolId == APESTAKE_BAYC_POOL_ID) {
      withdrawFunctionToCall = "withdrawSelfBAYC(uint256)";
      callData = abi.encodeWithSignature(
        withdrawFunctionToCall,
        _notionalAmount
      );
      // --
    } else if (poolId == APESTAKE_MAYC_POOL_ID) {
      withdrawFunctionToCall = "withdrawSelfMAYC(uint256)";
      callData = abi.encodeWithSignature(
        withdrawFunctionToCall,
        _notionalAmount
      );
      // --
    } else if (poolId == APESTAKE_BAKC_POOL_ID) {
      withdrawFunctionToCall = "withdrawBAKC((uint32,uint32,uint184,bool)[],(uint32,uint32,uint184,bool)[])";
      callData = _getUnstakeFromPairPoolCallData(
        withdrawFunctionToCall,
        _notionalAmount,
        _additionalUnstakeData
      );
    } else {
      revert("unrecognised poolId.");
    }
    return (_stakingContract, 0, callData);
  }

  /**
   * Returns the address to approve component for staking tokens.
   *
   * @param _stakingContract          Address of the gauge staking contract
   *
   * @return address                  Address of the contract to approve tokens transfers to
   */
  function getSpenderAddress(
    address _stakingContract
  ) external pure returns (address) {
    // in this case, the spender is the staking contract itself, which handles the depositing of ApeCoin.
    return _stakingContract;
  }

  /* ============ Internal Functions ============
   * These functions aim to reduce code block size of the external functions.
   */
  function _getStakeInApeCoinPoolCallData(
    uint256 _notionalAmount
  ) internal pure returns (bytes memory) {
    bytes memory callData = abi.encodeWithSignature(
      "depositSelfApeCoin(uint256)",
      _notionalAmount
    );
    return callData;
  }

  function _getStakeInBAYCOrMAYCPoolCallData(
    uint256 _notionalAmount,
    bytes calldata _additionalData
  ) internal view returns (bytes memory) {
    (uint256 poolId, SingleNft[] memory nftAndAmountPairs) = abi.decode(
      _additionalData,
      (uint256, SingleNft[])
    );
    string memory depositFunctionToCall = poolId == APESTAKE_BAYC_POOL_ID
      ? "depositBAYC((uint32,uint224)[])"
      : "depositMAYC((uint32,uint224)[])";
    uint224 poolCapToUse = poolId == APESTAKE_BAYC_POOL_ID
      ? BAYC_PER_TOKEN_STAKE_CAP
      : MAYC_PER_TOKEN_STAKE_CAP;
    uint256 total;
    // ! SafeMath .add() operations should be used instead of '++' and '+=', but not possible with `uint224` type.
    // ? SafeMath.add() not compatible with encoded ethers.js values? Throwing error even when typing amountToStakeWithNFT as uint256
    for (uint256 i = 0; i < nftAndAmountPairs.length; i++) {
      uint256 amountToStakeWithNFT = nftAndAmountPairs[i].amount;
      require(
        amountToStakeWithNFT <= poolCapToUse,
        "amount paired with Single NFT exceeds pool cap"
      ); // note: ultimately, full cap checking will need to be handled on the ape-staking contract itself, but this is a stop gap measure.
      total += amountToStakeWithNFT;
    }
    require(
      _notionalAmount == total,
      "_notionalAmount does not match amounts paired with single nfts"
    );
    bytes memory callData = abi.encodeWithSignature(
      depositFunctionToCall,
      nftAndAmountPairs
    );
    return callData;
  }

  function _getStakeInPairPoolCallData(
    uint256 _notionalAmount,
    bytes calldata _additionalData
  ) internal view returns (bytes memory) {
    (
      ,
      // ^ poolId; not needed here
      PairNftDepositWithAmount[] memory baycBakcPairs,
      PairNftDepositWithAmount[] memory maycBakcPairs
    ) = abi.decode(
        _additionalData,
        (uint256, PairNftDepositWithAmount[], PairNftDepositWithAmount[])
      );
    // * uint184 is type of 'amount' field in struct anyway
    uint184 total;
    for (uint184 i = 0; i < baycBakcPairs.length; i++) {
      uint184 amountToStakePerNFTPair = baycBakcPairs[i].amount;
      require(
        amountToStakePerNFTPair <= BAKC_PER_TOKEN_STAKE_CAP,
        "amount paired with NFT Pair exceeds BAKC pool cap"
      );
      total += amountToStakePerNFTPair;
    }
    for (uint184 i = 0; i < maycBakcPairs.length; i++) {
      uint184 amountToStakePerNFTPair = maycBakcPairs[i].amount;
      require(
        amountToStakePerNFTPair <= BAKC_PER_TOKEN_STAKE_CAP,
        "amount paired with NFT Pair exceeds BAKC pool cap"
      );
      total += amountToStakePerNFTPair;
    }
    require(
      _notionalAmount == total,
      "notionalAmount != ApeCoin paired with NFT pairs"
    );
    bytes memory callData = abi.encodeWithSignature(
      "depositBAKC((uint32,uint32,uint184)[],(uint32,uint32,uint184)[])",
      baycBakcPairs,
      maycBakcPairs
    );

    return callData;
  }

  function _getUnstakeFromPairPoolCallData(
    string memory _functionSignature,
    uint256 _notionalAmount,
    bytes calldata _unstakeData
  ) internal pure returns (bytes memory) {
    //
    (
      ,
      // ^ poolId; not needed here
      PairNftWithdrawWithAmount[] memory baycBakcPairs,
      PairNftWithdrawWithAmount[] memory maycBakcPairs
    ) = abi.decode(
        _unstakeData,
        (uint256, PairNftWithdrawWithAmount[], PairNftWithdrawWithAmount[])
      );
    uint184 total;
    for (uint184 i = 0; i < baycBakcPairs.length; i++) {
      uint184 amountToStakePerNFTPair = baycBakcPairs[i].amount;
      total += amountToStakePerNFTPair;
    }
    for (uint184 i = 0; i < maycBakcPairs.length; i++) {
      uint184 amountToStakePerNFTPair = maycBakcPairs[i].amount;
      total += amountToStakePerNFTPair;
    }
    require(
      _notionalAmount == total,
      "notionalAmount != ApeCoin paired with NFT pairs"
    );

    bytes memory callData = abi.encodeWithSignature(
      _functionSignature,
      baycBakcPairs,
      maycBakcPairs
    );
    return callData;
  }
}
