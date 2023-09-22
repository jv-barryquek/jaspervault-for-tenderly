const {
  deployAndVerifyContractOnTenderly,
  deployAndVerifyContractWithLibrariesOnTenderly,
} = require("../utils/deployAndVerifyOnTenderly");
const { BaseDeployer } = require("./BaseDeployer");
/**
 * @title  ModulesDeployer
 * @author Jasper Vault
 *
 * @description The ModulesDeployer handles the deployment ...
 * todo: fill this in
 *
 */
class ModulesDeployer extends BaseDeployer {
  /**
   * @param {string} _deployerAddress Address of Signer used for deployment transactions; typically gotten by the first item from `ethers.getSigners()`.
   * @param {string} _network The network to deploy the modules to
   * @param {string} _controllerAddress The address of the deployed Controller contract
   * @param {string} _subscribeFeePoolAddress The address of the deployed SubscribeFeePool contract
   */
  constructor(
    _deployerAddress,
    _network,
    _controllerAddress,
    _subscribeFeePoolAddress
  ) {
    super(_deployerAddress, _network);
    if (!_controllerAddress) {
      throw new Error(`${this.constructor.name}: ControllerAddress required`);
    }
    if (!_subscribeFeePoolAddress) {
      throw new Error(
        `${this.constructor.name}: SubscribeFeePoolAddress required`
      );
    }
    this.namesToAddresses["Controller"] = _controllerAddress;
    this.namesToAddresses["SubscribeFeePool"] = _subscribeFeePoolAddress;
  }
  /**
   */
  async deployAllModules(_aavePoolAddressProvider) {
    await this.deployAaveLeverageModule(_aavePoolAddressProvider);
  }

  /**
   * @description Helper to deploy AaveV2 Contract library
   * @dev Should be used in conjunction with this class' `deployAaveLeverageModule` function
   * @returns {Promise<string>} Address of deployed AaveV2 contract
   */
  async deployAaveV2() {
    const aaveV2Address = await deployAndVerifyContractOnTenderly("AaveV2");
    this.setNamesToAddressesObject("AaveV2", aaveV2Address);
    return aaveV2Address;
  }
  /**
   *
   * @param {string} _poolAddressProviderAddress Address of AaveV2's PoolAddressProvider contract
   * @param {string} _controllerAddress Address of deployed Controller contract(optional)
   */
  async deployAaveLeverageModule(
    _poolAddressProviderAddress,
    _controllerAddress = this.namesToAddresses["Controller"]
  ) {
    if (!_poolAddressProviderAddress) {
      throw new Error(
        `${this.constructor.name}: PoolAddressProviderAddress required for AaveLeverageModule deployment`
      );
    }
    this.checkControllerAddressIsNotNull(
      _controllerAddress,
      "AaveLeverageModule"
    );

    const aaveV2Address = await this.deployAaveV2();
    if (!this.namesToAddresses["AaveV2"] || !aaveV2Address) {
      throw new Error(
        `${this.constructor.name}: AaveV2 address not saved in namesToAddresses`
      );
    }

    const aaveLeverageModuleAddress =
      await deployAndVerifyContractWithLibrariesOnTenderly(
        "AaveLeverageModule",
        { AaveV2: this.namesToAddresses["AaveV2"] },
        _controllerAddress,
        _poolAddressProviderAddress
      );

    this.setNamesToAddressesObject(
      "AaveLeverageModule",
      // @ts-ignore
      aaveLeverageModuleAddress
    );
  }
}

module.exports = {
  ModulesDeployer,
};
