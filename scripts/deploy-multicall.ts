import { ethers, network } from 'hardhat'

import debug from 'debug'
import { extractDeployLogs, DeployLog } from './utils'

const logger = debug('scripts:deploy-multicall')

async function main() {
  debug.enable('scripts:deploy-multicall')
  const { chainId } = network.config

  const [deployer] = await ethers.getSigners()
  const balanceBefore = await deployer.getBalance()
  logger('[%d] Deployer: %s (%s ethers)', chainId, deployer.address, ethers.utils.formatEther(balanceBefore))

  const m3 = await ethers.getContractFactory('Multicall3').then(f => f.deploy())
  await m3.deployed()

  const [log3] = extractDeployLogs([m3]) as DeployLog[]
  logger('[%d] Multicall3: %o', chainId, log3)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error)
  process.exitCode = 1
})
