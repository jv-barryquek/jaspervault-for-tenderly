require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

const tdly = require("@tenderly/hardhat-tenderly");
// Disable automatication verifications by Tenderly to have more control via manual verification.
tdly.setup({ automaticVerifications: false });

module.exports = {
  solidity: {
    // compiler versions taken from nft_lending_backend/spark-integration's hardhat.config.js
    compilers: [
      {
        version: "0.4.18",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
      {
        version: "0.6.10",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
      {
        version: "0.6.12",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },

      {
        version: "0.8.0",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },

      {
        version: "0.8.11",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.12",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
      {
        version: "0.8.6",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
    ],
  },
  networks: {
    devnet: {
      // Devnets have the benefit of all Tenderly's tools (e.g. debugger, gas profiler) as well as being shareable across the team
      // You can always spawn new runs from a particular devnet template to start with a 'fresh' execution history
      url: `${process.env.TENDERLY_DEVNET_URL}`,
      chainId: 1,
    },
  },
  tenderly: {
    project: `${process.env.TENDERLY_PROJECT_NAME}`,
    username: `${process.env.TENDERLY_USERNAME}`,
  },
};
