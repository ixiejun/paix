require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
      },
      {
        version: "0.6.6", // For Uniswap V2
      },
      {
        version: "0.5.16", // For Uniswap V2 Core
      }
    ]
  },
  networks: {
    hardhat: {
    },
    // Placeholder for Polkadot EVM Hub (e.g. Moonbeam or Acala EVM+, or Asset Hub if it supports EVM in future)
    polkadot_evm: {
      url: "https://rpc.api.moonbeam.network", 
      chainId: 1284, 
    }
  }
};
