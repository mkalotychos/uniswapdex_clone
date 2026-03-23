import { useReadContract, useAccount } from 'wagmi'
import { formatUnits } from 'viem'
import { ERC20_ABI } from '../abis'

export function useTokenBalance(tokenAddress: string | undefined, decimals: number = 18) {
  const { address } = useAccount()

  const { data, isLoading, refetch } = useReadContract({
    address: tokenAddress as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [address!],
    query: {
      enabled: !!tokenAddress && !!address,
      refetchInterval: 10_000,
    },
  })

  return {
    raw: data,
    formatted: data !== undefined ? formatUnits(data, decimals) : '0',
    isLoading,
    refetch,
  }
}
