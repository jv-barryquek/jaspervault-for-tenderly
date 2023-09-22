const { BaseDeployer } = require("./BaseDeployer");
const {
  deployAndVerifyContractOnTenderly,
} = require("../utils/deployAndVerifyOnTenderly");

/**
 * @title  CoreContractsDeployer
 * @author Jasper Vault
 *
 * @description The CoreContractsDeployer handles the deployment of the core contracts in the smart contract system. Placing the deployment functions in a class rather than in a large script makes managing the data we need to pass around from function to function easier to manage.
 *
 */
class CoreContractsDeployer extends BaseDeployer {
  /**
   *
   * @param {string} _deployerAddress Address of Signer used for deployment transactions; typically gotten by the first item from `ethers.getSigners()`.
   * @param {string} _network The name of the network which will be used in constructing the name of the JSON file that will store the contract addresses
   */
  constructor(_deployerAddress, _network) {
    super(_deployerAddress, _network);
    console.log(`\n${this.constructor.name} constructed for ${this.network}`);
  }

  /**
   * @notice Function to deploy all the core contracts with minimal manual configuration
   * @dev If you want to deploy specific contracts/have more control on the constructor args, then use the specific deployAndVerify* contracts
   * @param {string[]} _quoteAssets Addresses of quote assets. First one is Master Quote asset address
   * @param {string[]} _adapters Addresses of adapters PriceOracle should use to get prices via various protocols
   * @param {string[]} _assetOnes Addresses of first asset in asset pairs to have prices for
   * @param {string[]} _assetTwos Addresses of second asset in asset pairs to have prices for
   * @param {string[]} _oracles Addresses of oracles from which to get prices for asset pairs
   */
  async deployAndVerifyAll(
    _quoteAssets,
    _adapters,
    _assetOnes,
    _assetTwos,
    _oracles
  ) {
    if (!this.deployerAddress) {
      throw new Error(
        `${this.constructor.name}: deployerAddress not initialized`
      );
    }
    if (_quoteAssets.length === 0) {
      throw new Error(
        `${this.constructor.name}: _quoteAssets must be passed for PriceOracle to be deployed`
      );
    }
    await this.deployAndVerifyController();
    await this.deployAndVerifySetTokenCreator();
    await this.deployAndVerifyIntegrationRegistry();
    await this.deployAndVerifySetValuer();
    await this.deployAndVerifyPriceOracle(
      this.namesToAddresses["Controller"], // should be non-null from the preceding deploy of Controller
      _quoteAssets,
      _adapters,
      _assetOnes,
      _assetTwos,
      _oracles
    );
    await this.deployAndVerifyIdentityService();
    await this.deployAndVerifyManagerCore();
    await this.deployAndVerifyDelegatedManagerFactory();
    await this.deployAndVerifySubscribeFeePool();

    console.log("Core contracts deployed");
  }

  /**
   *
   * @param {string} _deployerAddress Address for Signer that will sign the deployment transaction; defaults to CoreContractsDeployer's `deployerAddress` field if no arg is given
   */
  async deployAndVerifyController(_deployerAddress = this.deployerAddress) {
    if (!_deployerAddress) {
      throw new Error(
        `${this.constructor.name}: Controller requires deployer address for construction`
      );
    }
    const controllerAddress = await deployAndVerifyContractOnTenderly(
      "Controller",
      _deployerAddress
    );
    this.setNamesToAddressesObject("Controller", controllerAddress);
  }

  /**
   *
   * @param {string} _controllerAddress Address of deployed Controller contract (optional). Default value is the address stored in the CoreContractsDeployer instance.
   */
  async deployAndVerifySetTokenCreator(
    _controllerAddress = this.namesToAddresses["Controller"]
  ) {
    this.checkControllerAddressIsNotNull(_controllerAddress, "SetTokenCreator");
    const setTokenCreatorAddress = await deployAndVerifyContractOnTenderly(
      "SetTokenCreator",
      _controllerAddress
    );
    this.setNamesToAddressesObject("SetTokenCreator", setTokenCreatorAddress);
  }

  /**
   *
   * @param {string} _controllerAddress Address of deployed Controller contract (optional). Default value is the address stored in the CoreContractsDeployer instance.
   */
  async deployAndVerifyIntegrationRegistry(
    _controllerAddress = this.namesToAddresses["Controller"]
  ) {
    this.checkControllerAddressIsNotNull(
      _controllerAddress,
      "IntegrationRegistry"
    );

    const integrationRegistryAddress = await deployAndVerifyContractOnTenderly(
      "IntegrationRegistry",
      _controllerAddress
    );

    this.setNamesToAddressesObject(
      "IntegrationRegistry",
      integrationRegistryAddress
    );
  }

  /**
   *
   * @param {string} _controllerAddress Address of deployed Controller contract (optional). Default value is the address stored in the CoreContractsDeployer instance.
   */
  async deployAndVerifySetValuer(
    _controllerAddress = this.namesToAddresses["Controller"]
  ) {
    this.checkControllerAddressIsNotNull(_controllerAddress, "SetValuer");

    const setValuerAddress = await deployAndVerifyContractOnTenderly(
      "SetValuer",
      _controllerAddress
    );

    this.setNamesToAddressesObject("SetValuer", setValuerAddress);
  }
  /**
    * @param {string} _controllerAddress Address of deployed Controller contract (optional; the value saved in namesToAddresses field is used if nothing is passed)
   * @param {string[]} _quoteAssets Addresses of quote assets. First one is Master Quote asset address
   * @param {string[]} _adapters Addresses of adapters PriceOracle should use to get prices via various protocols (optional)
   * @param {string[]} _assetOnes Addresses of first asset in asset pairs to have prices for (optional)
   * @param {string[]} _assetTwos Addresses of second asset in asset pairs to have prices for (optional)
   * @param {string[]} _oracles Addresses of oracles from which to get prices for asset pairs (optional)
   * @dev If provided, the last 3 array args must be aligned-- each item at each index of each array constitutes an asset-pair + the oracle fetch the pair's price for
   * @example A simple example when we want to set up price oracles for DAI-USDC and WBTC-AAVE asset pairings
   ```
    ["DAIAddress", "WBTCAddress"],
    ["USDCAddress", "AAVEAddress"],
    ["priceOracleForDAI-USDC", "priceOracleForWBTC-AAVE" ]
    ```
   */
  async deployAndVerifyPriceOracle(
    _controllerAddress = this.namesToAddresses["Controller"],
    _quoteAssets,
    _adapters = [],
    _assetOnes = [],
    _assetTwos = [],
    _oracles = []
  ) {
    this.checkControllerAddressIsNotNull(_controllerAddress, "PriceOracle");

    if (_quoteAssets === undefined || _quoteAssets.length === 0) {
      throw new Error(
        `${this.constructor.name}: PriceOracle requires at least non-empty arg for _quoteAssets`
      );
    }

    const priceOracleAddress = await deployAndVerifyContractOnTenderly(
      "PriceOracle",
      _controllerAddress,
      _quoteAssets,
      _adapters,
      _assetOnes,
      _assetTwos,
      _oracles
    );

    this.setNamesToAddressesObject("PriceOracle", priceOracleAddress);
  }

  /**
   *
   * @param {string} _controllerAddress Address of deployed Controller contract (optional; the value saved in namesToAddresses field is used if nothing is passed)
   */
  async deployAndVerifyIdentityService(
    _controllerAddress = this.namesToAddresses["Controller"]
  ) {
    this.checkControllerAddressIsNotNull(_controllerAddress, "IdentityService");

    const identityServiceAddress = await deployAndVerifyContractOnTenderly(
      "IdentityService",
      _controllerAddress
    );

    this.setNamesToAddressesObject("IdentityService", identityServiceAddress);
  }

  /**
   * @notice Deploy the ManagerCore contract
   */
  async deployAndVerifyManagerCore() {
    const managerCoreAddress = await deployAndVerifyContractOnTenderly(
      "ManagerCore"
    );

    this.setNamesToAddressesObject("ManagerCore", managerCoreAddress);
  }

  /**
   *
   * @param {string} _managerCoreAddress Address of deployed ManagerCore contract (optional)
   * @param {string} _controllerAddress Address of deployed Controller contract (optional)
   * @param {string} _setTokenCreatorAddress Address of SetTokenCreator contract (optional)
   */
  async deployAndVerifyDelegatedManagerFactory(
    _managerCoreAddress = this.namesToAddresses["ManagerCore"],
    _controllerAddress = this.namesToAddresses["Controller"],
    _setTokenCreatorAddress = this.namesToAddresses["SetTokenCreator"]
  ) {
    this.checkControllerAddressIsNotNull(
      _controllerAddress,
      "DelegatedManagerFactory"
    );

    if (
      _managerCoreAddress === undefined ||
      _setTokenCreatorAddress === undefined
    ) {
      throw new Error(
        `${this.constructor.name}: SetTokenCreator and ManagerCore addresses must be saved in namesToAddresses`
      );
    }

    const delegatedManagerFactoryAddress =
      await deployAndVerifyContractOnTenderly(
        "DelegatedManagerFactory",
        _managerCoreAddress,
        _controllerAddress,
        _setTokenCreatorAddress
      );

    this.setNamesToAddressesObject(
      "DelegatedManagerFactory",
      delegatedManagerFactoryAddress
    );
  }

  /**
   *
   * @param {string} _controllerAddress Address of deployed Controller contract (optional)
   * @param {string} _delegatedManagerFactoryAddress Address of deployed DelegatedManagerFactory contract (optional)
   */
  async deployAndVerifySubscribeFeePool(
    _controllerAddress = this.namesToAddresses["Controller"],
    _delegatedManagerFactoryAddress = this.namesToAddresses[
      "DelegatedManagerFactory"
    ]
  ) {
    this.checkControllerAddressIsNotNull(
      _controllerAddress,
      "SubscribeFeePool"
    );

    if (_delegatedManagerFactoryAddress === undefined) {
      throw new Error(
        `${this.constructor.name}: DelegatedManagerFactory addresses must be saved in namesToAddresses`
      );
    }

    const subscribeFeePoolAddress = await deployAndVerifyContractOnTenderly(
      "SubscribeFeePool",
      _controllerAddress,
      _delegatedManagerFactoryAddress
    );

    this.setNamesToAddressesObject("SubscribeFeePool", subscribeFeePoolAddress);
  }

  /**
   *
   * @returns {string[]} Array of addresses that the ModuleDeployer (Controller and SubscribeFeePool) needs to deploy its modules
   */
  getAddressesForModuleDeployer() {
    return [
      this.namesToAddresses["Controller"],
      this.namesToAddresses["SubscribeFeePool"],
    ];
  }

  /**
   *
   * @returns {string} Address of DelegatedManagerFactory contract that ERC4337Deployer needs to deploy VaultFactory
   */
  getAddressesForERC4337Deployer() {
    return this.namesToAddresses["DelegatedManagerFactory"];
  }
}

module.exports = {
  CoreContractsDeployer,
};
