require("@nomicfoundation/hardhat-toolbox");

const fs = require("fs");
const path = require("path");

function loadEnvFile(filePath) {
  try {
    if (!fs.existsSync(filePath)) return;

    const content = fs.readFileSync(filePath, "utf8");
    for (const rawLine of content.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line || line.startsWith("#")) continue;

      const eqIndex = line.indexOf("=");
      if (eqIndex === -1) continue;

      const key = line.slice(0, eqIndex).trim();
      const value = line.slice(eqIndex + 1).trim();
      if (!key) continue;
      if (process.env[key] === undefined) {
        process.env[key] = value;
      }
    }
  } catch (_) {
    // ignore
  }
}

loadEnvFile(path.join(__dirname, ".env.contracts"));

if (process.env.DEPLOYER_PK && !process.env.DEPLOYER_PK.startsWith("0x")) {
  process.env.DEPLOYER_PK = `0x${process.env.DEPLOYER_PK}`;
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.6.6", // For Uniswap V2
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.5.16", // For Uniswap V2 Core
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  networks: {
    hardhat: {
    },
    polkadot_hub_testnet: {
      url: "https://testnet-passet-hub-eth-rpc.polkadot.io",
      chainId: 420420422,
      accounts: process.env.DEPLOYER_PK ? [process.env.DEPLOYER_PK] : [],
      timeout: 120000
    },
    // Placeholder (legacy)
    polkadot_evm: {
      url: "https://rpc.api.moonbeam.network",
      chainId: 1284,
      accounts: process.env.DEPLOYER_PK ? [process.env.DEPLOYER_PK] : []
    }
  }
};
