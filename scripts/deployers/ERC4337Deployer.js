const {
  deployUUPSUpgradeableContractAndVerifyOnTenderly,
} = require("../utils/deployAndVerifyOnTenderly.js");
const {
  Ethereum4337Addresses,
} = require("../../networkSpecificAddresses/4337Addresses.js");
const { BaseDeployer } = require("./BaseDeployer.js");

/**
 * ! Delete this file if merged into main. It is incomplete.
 */
class ERC4337Deployer extends BaseDeployer {
  /**
   *
   * @param {string} _deployerAddress
   * @param {string} _network
   * @param {string} _delegatedManagerFactoryAddress Address of deployed and ideally verified DelegatedManagerFactory.
   */
  constructor(_deployerAddress, _network, _delegatedManagerFactoryAddress) {
    super(_deployerAddress, _network);

    if (!_delegatedManagerFactoryAddress) {
      throw new Error(
        `${this.constructor.name}: _delegatedManagerFactoryAddress required`
      );
    }

    this.setNamesToAddressesObject(
      "DelegatedManagerFactory",
      _delegatedManagerFactoryAddress
    );
  }

  /**
   * @description Function to deploy the VaultFactory as a UUPS Upgradeable contract and verify it on Tenderly.
   */
  async deployVaultFactory() {
    // In order for verification to work, the DelegatedManagerFactory at the address specified must be verified first
    // ! Not working; ethers.js throwing a "invalid format type argument"
    const [proxyAddress, vaultFactoryAddress] =
      await deployUUPSUpgradeableContractAndVerifyOnTenderly(
        "VaultFactory",
        Ethereum4337Addresses["EntryPoint"],
        this.namesToAddresses["DelegatedManagerFactory"]
      );

    this.setNamesToAddressesObject("VaultFactoryProxy", proxyAddress);
    this.setNamesToAddressesObject("VaultFactory", vaultFactoryAddress);
  }
}

module.exports = {
  ERC4337Deployer,
};
