/**
 * @notice This file exportts...
 * todo: fill this in...
 */

/**
 * @description Helper function to save the contractNames : addresses to a JSON file in the `deploymentContractAddresses/` folder located in the root of the project
 * @notice This function should be used for saving addresses in DEVELOPMENT and NOT PRODUCTION. See the `README.md` in `deploymentContractAddresses/` for why.
 * @dev Ideally, the contract should be verified as well wherever it is deployed
 * @param {string} contractCategory The name of the contract category (e.g. Modules, Extensions, CoreContracts)
 * @param {string} devnet The name of the devnet that it was deployed and verified on
 * @param {{}} nameToAddresses A key:value matching of the contractCategory's contract name and their addresses
 */
async function writeDevContractAddressesToJSONFile(
  contractCategory,
  devnet,
  nameToAddresses
) {
  const fs = require("fs");
  const path = require("path");
  fs.writeFileSync(
    path.join(
      "developmentContractAddresses",
      `${contractCategory}.${devnet}.json`
    ),
    JSON.stringify(nameToAddresses)
  );
}

module.exports = {
  writeDevContractAddressesToJSONFile,
};
