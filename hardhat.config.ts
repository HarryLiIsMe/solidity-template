import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'
import '@openzeppelin/hardhat-upgrades'
import { config as dotenvConfig } from 'dotenv'
import { Wallet } from 'ethers'
import { resolve } from 'path'

import './tasks'

dotenvConfig({ path: resolve(__dirname, './.env') })

/**
 * @dev Priority:
 *   1. env: MNEMONIC
 *   2. env: KEY
 *   3. generate random accounts
 */
const accounts = (function getAccounts(mnemonic = '', privateKey = '') {
  if (mnemonic) {
    return {
      count: 10,
      mnemonic,
      // path: "m/44'/60'/0'/0",
    }
  }

  if (privateKey) {
    return [privateKey]
  }

  console.log('Not assign secrets from environment variables, generate random accounts...')
  const wallet = Wallet.createRandom()
  return {
    count: 10,
    mnemonic: wallet.mnemonic!.phrase,
    // path: wallet.mnemonic!.path,
  }
})(process.env.MNEMONIC, process.env.KEY)

const config: HardhatUserConfig = {
  defaultNetwork: process.env.DEFAULT_NETWORK ?? 'hardhat',
  gasReporter: {
    currency: 'USD',
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: './contracts',
  },
  networks: {
    local: {
      chainId: 9487,
      url: `http://127.0.0.1:9487`,
    },
    'local:anvil': {
      chainId: 31337,
      accounts,
      url: `http://127.0.0.1:8545`,
    },
    'local:gsc': {
      accounts: {
        // address: 0x0B06f69fbE25be3bd18eA61827cd73EEbC218e77
        mnemonic: `prison kit have scare render sunny bacon group dutch gentle unfair neck`,
      },
      url: `http://127.0.0.1:8545`,
    },
    hardhat: {
      accounts: {
        accountsBalance: '10000000000000000000000000',
      },
      chainId: 31337,
    },
    'bnb': {
      accounts,
      chainId: 56,
      url: 'https://bsc-dataseed1.binance.org',
      gasPrice: 20e9,
    },
    'bnb:testnet': {
      accounts,
      chainId: 97,
      // Check latency here: https://chainlist.org/chain/97
      url: 'https://data-seed-prebsc-2-s1.binance.org:8545',
      // url: 'https://data-seed-prebsc-1-s1.binance.org:8545',
      // url: 'https://data-seed-prebsc-2-s3.binance.org:8545',
      gasPrice: 20e9,
    },
    'fra': {
      accounts,
      chainId: 2152,
      url: 'https://prod-mainnet.prod.findora.org:8545',
      // gas: 'auto',
      timeout: 20000000,
      // gasPrice: 'auto',
      gasMultiplier: 1.2,
    },
    'fra:anvil': {
      accounts,
      chainId: 2153,
      url: 'https://prod-testnet.prod.findora.org:8545',
      // gas: 'auto',
      timeout: 20000000,
      // gasPrice: 'auto',
      gasMultiplier: 1.2,
    },
    'fra:forge': {
      accounts,
      chainId: 2154,
      url: `https://prod-forge.prod.findora.org:8545`,
    },
    // Findora Game Side Chain Testnet
    'gsc:testnet': {
      accounts,
      chainId: 9527,
      url: `https://dev-qa03.dev.findora.org:8545`,
    },
    // Findora Game Side Chain Testnet
    'gsc:dev': {
      accounts,
      chainId: 9527,
      url: `http://54.69.91.103:8545`,
    },
    'tt': {
      accounts,
      chainId: 108,
      url: 'https://mainnet-rpc.thundercore.com',
      gasPrice: 20e9,
    },
    'tt:testnet': {
      accounts,
      chainId: 18,
      url: 'https://testnet-rpc.thundercore.com',
      gasPrice: 20e9,
    },
  },
  paths: {
    artifacts: './artifacts',
    cache: './cache',
    sources: './contracts',
    tests: './test',
  },
  solidity: {
    compilers: [
      {
        version: '0.8.18',
        settings: {
          metadata: {
            // Not including the metadata hash
            // https://github.com/paulrberg/solidity-template/issues/31
            bytecodeHash: 'none',
          },
          // Disable the optimizer when debugging
          // https://hardhat.org/hardhat-network/#solidity-optimizer-support
          optimizer: {
            enabled: true,
            runs: 200,
          },
          // evmVersion: 'default',
        },
      },
      {
        version: '0.8.12',
        settings: {
          metadata: { bytecodeHash: 'none' },
          optimizer: { enabled: true, runs: 200 },
        },
      },
    ],
  },
  typechain: {
    outDir: 'build/types',
    target: 'ethers-v5',
  },
}

export default config
