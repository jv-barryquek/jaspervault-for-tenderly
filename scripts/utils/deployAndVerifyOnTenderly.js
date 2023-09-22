/**
 * @notice This file exports ...
 * todo: fill this in
 */
require("@openzeppelin/hardhat-upgrades");
const { ethers, tenderly, upgrades } = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");

/**
 * @notice Helper function to import into scripts deploying and verifying specific contracts
 * @dev Normally, we would want to ensure that all contracts we deploy are verified on Tenderly because this lets us use their various tools (e.g. debugger, gas profiler, transaction simulations)
 * @param {string} _contractName  The name of the contract to be deployed and verified
 * @param  {...any} args   Any arguments for the construction of the contract
 * @returns {Promise<string>}
 */
async function deployAndVerifyContractOnTenderly(_contractName, ...args) {
  console.log(`\nDeploying ${_contractName}...`);
  const ContractFactory = await ethers.getContractFactory(_contractName);
  const contract = await ContractFactory.deploy(...args);

  // MUST wait for contract to finish deploying before manual verification
  await contract.deployed();
  console.log(`${_contractName} deployed at ${contract.address}`);

  // We manually verify (as opposed to doing auto-verify) the contracts using the tenderly-hardhat plugin for greater control over the verification process.
  console.log(`Attempting to verify ${_contractName} with Tenderly...`);
  await tenderly.verify({
    name: _contractName,
    // @ts-ignore
    address: contract.address,
  });

  // Return the address so other functions can know the address the contract has been deployed at
  // @ts-ignore
  return contract.address;
}

/**
 * @description Helper function to deploy and verify contracts with library dependencies on Tenderly
 * @notice This function should be used if the contract being deployed has a library dependency that has already been deployed and verified on Tenderly
 * @dev This function does "simple" manual verification as opposed to "advanced" manual verification. "Advanced" should be used if you want even more control over the verification process. See this repo for the various ways that contracts with libraries can be verified on Tenderly: [examples of tenderly-hardhat manual verification](https://github.com/Tenderly/hardhat-tenderly/tree/master/examples/contract-verification)
 * @dev This function presupposes that the library has already been deployed and verified on Tenderly. See the repo linked above for how to deploy a contract with a non-deployed library dependency.
 * generate the jsdoc for the parameters
 * @param {string} _contractName The name of the contract to be deployed and verified
 * @param {Object.<string,string>} _libraries The libraries that the contract depends on
 * @param  {...any} args Any arguments for the construction of the contract
 */
async function deployAndVerifyContractWithLibrariesOnTenderly(
  _contractName,
  _libraries,
  ...args
) {
  // check _libraries object is non-empty
  if (Object.keys(_libraries).length === 0) {
    console.log("_libraries is: ");
    console.dir(_libraries);
    throw new Error(
      `${this.constructor.name}: _libraries object must be non-empty`
    );
  }

  const contractAddress = deployContractWithLibraries(
    _contractName,
    _libraries,
    ...args
  );

  console.log(`Attempting to verify ${_contractName} with Tenderly...`);
  await tenderly.verify({
    name: _contractName,
    // @ts-ignore
    address: contractAddress,
    libraries: _libraries,
  });
  // Return the address so other functions can know the address the contract has been deployed at
  return contractAddress;
}

/**
 * @description Helper function for deploying contracts with library dependencies. Used by `deployAndVerifyContractWithLibrariesOnTenderly`.
 * @param {string} _contractName The name of the contract to be deployed and verified
 * @param {Object.<string,string>} _libraries The libraries that the contract depends on
 * @param  {...any} args Any arguments for the construction of the contract
 * @return {Promise<string>} Returns the address of the deployed contract
 */
async function deployContractWithLibraries(_contractName, _libraries, ...args) {
  console.log(`\nDeploying ${_contractName}...`);

  const ContractFactory = await ethers.getContractFactory(_contractName, {
    libraries: _libraries,
  });
  const contract = await ContractFactory.deploy(...args);
  await contract.deployed();

  console.log(`${_contractName} deployed at ${contract.address}`);
  //@ts-expect-error
  return contract.address;
}

/**
 *
 * @param {string} _contractName Name of the upgradeable contract to be deployed and verified
 * @param  {...any} args Arguments for the initialisation of the implementation contract
 * @returns {Promise<[string,string]>} Returns a tuple of the proxy address and the implementation address
 */
async function deployUUPSUpgradeableContractAndVerifyOnTenderly(
  _contractName,
  ...args
) {
  console.log(`\nDeploying UUPS Upgradeable Contract ${_contractName}...`);
  // ? Not sure why this deployProxy call is failng with "invalid format type argument"
  console.log(`Entrypoint address is ${args[0]}`);
  console.log(`DelegatedManagerFactory address is ${args[1]}`);
  const ContractFactory = await ethers.getContractFactory(_contractName);
  const proxy = await upgrades.deployProxy(ContractFactory, args, {
    kind: "uups",
  });

  await proxy.deployed();
  const proxyAddress = proxy.address;
  const implementationAddress = await getImplementationAddress(
    ethers.provider,
    //@ts-expect-error
    proxy.address
  );
  console.log(`${_contractName} proxy deployed at ${proxyAddress}`);
  console.log(
    `${_contractName} (the implementation) deployed at ${implementationAddress}`
  );

  await tenderly.verify(
    // Verify the implementation contract
    {
      name: _contractName,
      address: implementationAddress,
    },
    // Verify the proxy instance
    {
      // For Tenderly's plugin to work, the proxy that is deployed when using OpenZeppelin's `deployProxy` function must be imported into our project and compiled as well. See `DummyProxy.sol` for more details.
      // ! Not sure how to do this? My issues are in `DummyProxy.sol`
      // ? However, the docs page on this doesn't mention the need to import the proxy contract into our project and compile it. So maybe we don't need to?
      name: "ERC1967Proxy",
      //@ts-expect-error
      address: proxyAddress,
    }
  );
  //@ts-expect-error
  return [proxyAddress, implementationAddress];
}

module.exports = {
  deployAndVerifyContractOnTenderly,
  deployAndVerifyContractWithLibrariesOnTenderly,
  deployUUPSUpgradeableContractAndVerifyOnTenderly,
};
