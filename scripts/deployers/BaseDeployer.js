/**
 * @notice Base class for all deployer objects
 */
const {
  writeDevContractAddressesToJSONFile,
} = require("../utils/writeContractAddresses");

class BaseDeployer {
  /**
   * @notice Global key:value pair that will be used after all the deployments to write to a `.json` file or for console.logging purposes
   * @type {Object.<string,string>}
   */
  namesToAddresses = {};

  /**
   * @notice Address of Signer used for deployment transactions; typically gotten by the first item from `ethers.getSigners()`.
   * @type {string}
   */
  deployerAddress;

  /**
   * @notice The name of the network which will be used in constructing the name of the JSON file that will store the contract addresses
   * @type {string}
   */
  network;

  constructor(_deployerAddress, _network) {
    if (!_deployerAddress) {
      throw new Error("BaseDeployer: DeployerAddress required");
    }
    if (!_network) {
      throw new Error("BaseDeployer: Network required");
    }
    this.deployerAddress = _deployerAddress;
    this.network = _network;
  }

  /**
   * @description Updates the namesToAddresses field and logs its state to the console
   * @param {string} _contractName Name of contract
   * @param {string} _contractAddress Address that it's been deployed at
   */
  setNamesToAddressesObject(_contractName, _contractAddress) {
    this.namesToAddresses[_contractName] = _contractAddress;
    console.log(`\n${this.constructor.name}.namesToAddresses is: `);
    console.dir(this.namesToAddresses);
  }

  /**
   * @notice Getter function used to get the names to address mapping.
   * @dev One use case is for the other deloyer objects to get hold of the deployed contract addresses at runtime
   * @returns {Object.<string,string>}
   */
  getNamesToAddressesObject() {
    if (JSON.stringify(this.namesToAddresses) === "{}") {
      throw new Error(`${this.constructor.name}.namesToAddresses is empty`);
    }
    return this.namesToAddresses;
  }

  /**
   * @notice Helper function to check that the purported Controller address is not null. We place it in the BaseDeployer because this is such a common check that we want to do for all deployers.
   * @param {string} _controllerAddress Purported address of deployed Controller contract
   * @param {string} _requiredFor Name of contract that requires non-null controller address
   */
  checkControllerAddressIsNotNull(_controllerAddress, _requiredFor) {
    if (!_controllerAddress) {
      throw new Error(
        `${this.constructor.name}: ${_requiredFor} requires Controller Address for construction`
      );
    }
  }

  /**
   *
   * @notice Write a JSON file to the `developmentContractAddresses/` folder using the `namesToAddresses` field
   * @dev If one wants to save the addresses to a `.json` file in the `productionContractAddresses/` folder, it is recommend to manually copy-paste the addresses from console output. Check the `README.md` in these directories for more information
   */
  async saveDevContractsToJSONFile() {
    await writeDevContractAddressesToJSONFile(
      this.constructor.name,
      this.network,
      this.namesToAddresses
    );
  }
}

module.exports = {
  BaseDeployer,
};
