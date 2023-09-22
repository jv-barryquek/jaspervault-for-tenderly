/**
 * @notice This script will contain the addresses/constants for various entities involed in the ERC-4337 execution of our transactions (e.g. the Bundler RPC-URL, the address of the Paymaster).
 */
const { Constants } = require("userop");

/**
 * @type {Object.<string,string>}
 */
const Ethereum4337Addresses = {
  EntryPoint: Constants.ERC4337.EntryPoint,
};

module.exports = {
  Ethereum4337Addresses,
};
