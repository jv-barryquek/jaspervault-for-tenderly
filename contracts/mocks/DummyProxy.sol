// SPDX-License-Identifier: MIT
/// @notice This compiler version was taken from the example repo, but need to add this compiler version into hardhat.config.js if we want to use it
// pragma solidity ^0.8.17;
/**
 * @title DummyProxy
 * @dev This file is taken from the `tenderly-examples` repo for contract verification. It's purpose to include OpenZeppelin's proxy contracts into our compilation artifacts in our project. This is so that we can manually verify any upgradeable contracts we deploy using OpenZeppelin's upgrade-core helpers.
 * See [this repo for more details](https://github.com/Tenderly/tenderly-examples/tree/master/contract-verifications)
 * The `contracts/Vault/DummyProxy.sol` file is where this file was copied from.
 */

// ! Not sure how to import these contracts in now that they have been installed via the "openzeppelin-contracts-latest" repo
/// @notice commented out because I can't compile this contract
// import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
// import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
// import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// abstract contract ERC1967ProxyAccess is ERC1967Proxy {}

// abstract contract UpgradableBeaconAccess is UpgradeableBeacon {}

// abstract contract BeaconProxyAccess is BeaconProxy {}

// abstract contract TransparentUpgradeableProxyAccess is
//     TransparentUpgradeableProxy
// {}
