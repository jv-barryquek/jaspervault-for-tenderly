/**
 * @notice The rationale for this script is to streamline the way we deploy new integrations without cluttering the `script/` folder
 * @dev One possible way to use this script is:
 * 1. Copy it over to the `past-deployments/` folder
 * 2. Rename it to something like `deploy<NameOfIntegration/Protocol>.js`
 * 3. Fill it in to deploy the various bits of code you'd require to deploy and set up your new integration
 * This way, the team will have a record of how someone deployed a particular integration
 */

// const { ethers } = require("hardhat");
// testing this
// --- Import the Deployer Objects Needed (e.g. the CoreContractsDeployer)

async function main() {
  // --- Set Your Constants (e.g. the network, your Signer object) ---
  // --- Instantiate the deployer objects
  // --- Invoke deployer object functions
}

// This pattern lets us use async/await everywhere and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
