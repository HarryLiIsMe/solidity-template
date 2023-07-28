import { ethers, network } from 'hardhat'

import debug from 'debug'
import { extractDeployLogs, DeployLog } from './utils'

const logger = debug('scripts:deploy-poker')

async function main() {
  debug.enable('scripts:deploy-poker')

  const { chainId } = network.config
  const [deployer] = await ethers.getSigners()
  const balanceBefore = await deployer.getBalance()
  logger('[%d] Deployer: %s (%s ethers)', chainId, deployer.address, ethers.utils.formatEther(balanceBefore))

  const TexasHoldemRound = await ethers
    .getContractFactory('TexasHoldemRound')
    .then(f => f.deploy(0))
  await TexasHoldemRound.deployed()

  const OneTimeDrawInstance = await ethers
    .getContractFactory('OneTimeDrawInstance')
    .then(f => f.deploy(
      TexasHoldemRound.address,
      '0x0000000000000000000000000000000000003000',
      '0x',
      [],
      3
    ))

  await OneTimeDrawInstance.deployed()

  await TexasHoldemRound.setGameInstance(OneTimeDrawInstance.address)

  const logs = extractDeployLogs({
    TexasHoldemRound,
    OneTimeDrawInstance,
  })

  logger('%O', logs)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error)
  process.exitCode = 1
})
