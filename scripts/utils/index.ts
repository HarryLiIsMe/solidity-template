import { BaseContract } from 'ethers'

export const extractDeployLog = (contract: BaseContract) => ({
  address: contract.address,
  tx: contract.deployTransaction.hash,
  blockCreated: contract.deployTransaction.blockNumber,
})

export type DeployLog = ReturnType<typeof extractDeployLog>

export type DeployContracts =
  | BaseContract
  | BaseContract[]
  | {
      [name: string]: BaseContract
    }

export const extractDeployLogs = (logs: DeployContracts) => {
  if (Array.isArray(logs)) {
    return logs.map(extractDeployLog)
  }

  if (logs instanceof BaseContract) {
    return extractDeployLog(logs)
  }

  if (typeof logs === 'object') {
    return Object.fromEntries(
      Object.entries(logs).map(([name, contract]) => [name, extractDeployLog(contract)])
    )
  }

  throw new Error('Invalid deploy logs')
}
