/**
 * @notice This is a simple script used for...
 * todo: fill this in when implementation is more final
 */

const { ethers } = require("hardhat");
const {
  EthereumTokenAddresses,
} = require("../networkSpecificAddresses/TokenAddresses");
const {
  EthereuemProtocolAddresses,
} = require("../networkSpecificAddresses/ProtocolAddresses");
const { CoreContractsDeployer } = require("./deployers/CoreContractsDeployer");
const { ModulesDeployer } = require("./deployers/ModulesDeployer");
const { ERC4337Deployer } = require("./deployers/ERC4337Deployer");

// * --- Change the variable values accordingly ---
/**
 * @notice This is required for creating the JSON file for contract addresses, it's different from the variable we use to index the ExecutionContext object.
 * @example This string should either be the name of an actual network "Polygon", "Ethereum", "Goerli", or some name that is explicit about it being a devnet e.g. "PolygonDevNet", "EthereumDevNet"
 * @type {string}
 */
const networkForFileName = "EthereumDevNet";

/**
 * @notice This is required for the CoreContractsDeployer.deployAndVerifyAll function to deploy the PriceOracle contract
 * type the object below
 * @type {object}
 * @property {string[]} quoteAssets addresses of quote assets; first one is Master Quote Asset
 * @property {string[]} adapters addresses of adapters for PriceOracle to use to interact w various protocols
 * The next three args should be considered together--
 * @property {string[]} assetOneAddresses addresses of assetOne in assetPair price
 * @property {string[]} assetTwoAddresses addresses of assetTwo in assetPair price
 * @property {string[]} priceOracleAddresses addresses of Price Oracles that give the assetPair price specified in the previous two args
 * @example A minimal example if you just want to get a PriceOracle deployed and verified on Tenderly:
 * ```
  const additionalPriceOracleArgs = {
  quoteAssets: [EthereumTokenAddresses["USDC"]],
  adapters: [],
  assetOneAddresses: [],
  assetTwoAddresses: [],
  priceOracleAddresses: [],
};
 * ```
 */
const additionalPriceOracleArgs = {
  quoteAssets: [EthereumTokenAddresses["USDC"]],
  adapters: [],
  assetOneAddresses: [],
  assetTwoAddresses: [],
  priceOracleAddresses: [],
};

// * --- Execution ---

/**
 * @notice Main function which instantiates the contract deployer objects and invokes their functions to deploy/setup the various contracts
 */
async function main() {
  const [deployer] = await ethers.getSigners();

  // Need to instantiate CoreContractsDeployer first because other deployers need the Controller address
  const coreContractsDeployer = new CoreContractsDeployer(
    deployer.address,
    networkForFileName
  );

  await coreContractsDeployer.deployAndVerifyAll(
    additionalPriceOracleArgs["quoteAssets"],
    additionalPriceOracleArgs["adapters"],
    additionalPriceOracleArgs["assetOneAddresses"],
    additionalPriceOracleArgs["assetTwoAddresses"],
    additionalPriceOracleArgs["priceOracleAddresses"]
  );
  await coreContractsDeployer.saveDevContractsToJSONFile();

  const [controllerAddress, subscribeFeePoolAddress] =
    coreContractsDeployer.getAddressesForModuleDeployer();
  const modulesDeployer = new ModulesDeployer(
    deployer.address,
    networkForFileName,
    controllerAddress,
    subscribeFeePoolAddress
  );
  // ! Verification not working for AaveLeverageModule
  await modulesDeployer.deployAaveLeverageModule(
    EthereuemProtocolAddresses["AaveV2LendingPoolAddressesProvider"]
  );

  const delegatedManagerFactoryAddress =
    coreContractsDeployer.getAddressesForERC4337Deployer();
  const erc4337Deployer = new ERC4337Deployer(
    deployer.address,
    networkForFileName,
    delegatedManagerFactoryAddress
  );
  await erc4337Deployer.deployVaultFactory();
}

// This pattern lets us use async/await everywhere and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
