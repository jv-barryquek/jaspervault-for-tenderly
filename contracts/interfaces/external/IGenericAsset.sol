// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.6.10;

/**
 * Interface created for getting symbol information via contract address in PriceOracleV2.
 */
interface IGenericAsset {
  function symbol() external view returns (string memory);
}
