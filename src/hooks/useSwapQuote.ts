import { useReadContract, useChainId } from 'wagmi'
import { parseUnits, formatUnits } from 'viem'
import { QUOTER_V2_ABI } from '../abis'
import { getAddresses } from '../constants/deployments'

interface UseSwapQuoteParams {
  tokenIn: string | undefined
  tokenOut: string | undefined
  amountIn: string
  decimalsIn: number
  decimalsOut: number
  enabled: boolean
}

export function useSwapQuote({
  tokenIn,
  tokenOut,
  amountIn,
  decimalsIn,
  decimalsOut,
  enabled,
}: UseSwapQuoteParams) {
  const chainId = useChainId()

  let addresses: ReturnType<typeof getAddresses> | null = null
  try {
    addresses = getAddresses(chainId)
  } catch {
    /* no deployment for this chain */
  }

  const amountInWei = (() => {
    try {
      return amountIn && parseFloat(amountIn) > 0
        ? parseUnits(amountIn, decimalsIn)
        : undefined
    } catch {
      return undefined
    }
  })()

  const { data, isLoading, isError } = useReadContract({
    address: (addresses?.QuoterV2 ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
    abi: QUOTER_V2_ABI,
    functionName: 'quoteExactInputSingle',
    args: [{
      tokenIn: (tokenIn ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
      tokenOut: (tokenOut ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
      amountIn: amountInWei ?? 0n,
      fee: 3000,
      sqrtPriceLimitX96: 0n,
    }],
    query: {
      enabled: enabled && !!tokenIn && !!tokenOut && !!amountInWei && !!addresses,
      staleTime: 10_000,
      refetchInterval: 15_000,
      retry: false,
    },
  })

  const result = data as readonly [bigint, bigint, bigint, bigint] | undefined

  return {
    amountOut: result?.[0],
    amountOutFormatted: result?.[0]
      ? formatUnits(result[0], decimalsOut)
      : undefined,
    isLoading,
    isError,
    noLiquidity: isError,
  }
}
