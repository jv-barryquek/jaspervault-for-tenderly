/**
 * @notice This script will contain the addresses/constants for various protocol contracts on various networks. Took some addresses from settings.ethereum.json file in `nft_lending_backend`.
 */

/**
 * @template T
 * @typedef {Object.<string,T>} ProtocolAddresses
 */
const EthereuemProtocolAddresses = {
  UniswapV2Router02: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  UniswapV2Factory: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
  UniswapV3SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
  AaveV2LendingPoolAddressesProvider:
    "0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5",
};

module.exports = {
  EthereuemProtocolAddresses,
};
