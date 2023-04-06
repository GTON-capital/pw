import "@typechain/hardhat"
import "@nomiclabs/hardhat-waffle"
import "hardhat-abi-exporter"
import "@nomiclabs/hardhat-etherscan"

require('dotenv').config();
import { resolve } from "path";
import { config as dotenvConfig } from "dotenv";
dotenvConfig({ path: resolve(__dirname, "./.env") });

const {
  PRIVATE_KEY,
} = process.env;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    ftm: {
      url: "https://rpcapi-tracing.fantom.network",
      accounts: [PRIVATE_KEY],
    },
    ftmtestnet: {
      url: "https://rpc.testnet.fantom.network",
      accounts: [PRIVATE_KEY],
    },
    gton: {
      url: "https://rpc.gton.network",
      accounts: [PRIVATE_KEY],
    },
    gtonTestnet: {
      url: "https://testnet.gton.network",
      accounts: [PRIVATE_KEY],
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999,
          },
        },
      },
      {
        version: '0.6.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999
          }
        },
        evmVersion: 'istanbul'
      },
      {
        version: '0.5.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999
          }
        },
        evmVersion: 'istanbul'
      },
    ],
  },
  abiExporter: {
    clear: true,
    flat: true,
    spacing: 2,
  },
  mocha: {
    timeout: "100000000000000",
  },
  etherscan: {
    apiKey: {
      opera: "PYTF1XH3ND5KGGQCKREIQEZQ8X2M8R12SP",
    },
  },
}
