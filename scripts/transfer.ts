/**
 * usage:
 *   SECRET=0xPrivateKey \
 *   TO=0xYourWallet \
 *   AMOUNT=1000000 \
 *     yarn hardhat run ./scripts/transfer.ts --network GSC_TESTNET
 */

import { ethers, network } from 'hardhat'

import debug from 'debug'

const DEBUG_NAME = 'scripts:transfer'
const logger = debug(DEBUG_NAME)

const {
  SECRET = process.env.KEY,
  TO = '0xbbbb690a9B1ACdbF0e7BAE4f9aCB457703f02556',
  AMOUNT = '1000000',
} = process.env

async function main() {
  debug.enable(DEBUG_NAME)

  const { chainId } = network.config

  const from = new ethers.Wallet(SECRET!, ethers.provider)
  const balanceBefore = await from.getBalance()

  logger('[%d] Transfer from: %s (%s ethers)', chainId, from.address, ethers.utils.formatEther(balanceBefore))

  const tx = await from.sendTransaction({
    to: TO,
    value: ethers.utils.parseEther(AMOUNT),
  })

  logger(
    '[%d] %s native token has transfered to %s at tx: %s',
    chainId,
    AMOUNT,
    TO,
    tx.hash
  )
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error)
  process.exitCode = 1
})
