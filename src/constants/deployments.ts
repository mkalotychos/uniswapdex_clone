import sepoliaDeployment from '../../deployments/sepolia.json'

export const DEPLOYMENTS = {
  11155111: sepoliaDeployment.contracts,
} as const

export type ContractAddresses = typeof sepoliaDeployment.contracts

export function getAddresses(chainId: number): ContractAddresses {
  const deployment = DEPLOYMENTS[chainId as keyof typeof DEPLOYMENTS]
  if (!deployment) throw new Error(`No deployment for chainId ${chainId}`)
  return deployment
}

export const SEPOLIA_CHAIN_ID = 11155111
