import { Signer } from '@ethersproject/abstract-signer'
import { task } from 'hardhat/config'

task(
  'accounts',
  'Prints the list of accounts',
  async (_taskArgs, { ethers, network }) => {
    const accounts: Signer[] = await ethers.getSigners()
    const {
      config: { chainId },
    } = network

    for (const account of accounts) {
      const address = await account.getAddress()
      const balance = await ethers.provider.getBalance(address)

      console.log(
        chainId,
        address,
        balance.toString(),
        `(${ethers.utils.formatEther(balance)})`
      )
    }
  }
)
