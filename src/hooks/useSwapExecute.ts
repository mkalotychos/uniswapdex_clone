import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useAccount, useChainId } from 'wagmi'
import { parseUnits } from 'viem'
import { useEffect, useCallback } from 'react'
import { ERC20_ABI, SWAP_ROUTER_ABI } from '../abis'
import { getAddresses } from '../constants/deployments'

interface UseSwapExecuteParams {
  tokenIn: string | undefined
  tokenOut: string | undefined
  amountIn: string
  decimalsIn: number
  amountOut: bigint | undefined
  enabled: boolean
}

export function useSwapExecute({
  tokenIn,
  tokenOut,
  amountIn,
  decimalsIn,
  amountOut,
  enabled,
}: UseSwapExecuteParams) {
  const { address } = useAccount()
  const chainId = useChainId()

  let addresses: ReturnType<typeof getAddresses> | null = null
  try {
    addresses = getAddresses(chainId)
  } catch {
    /* no deployment for this chain */
  }

  const routerAddress = addresses?.SwapRouter as `0x${string}` | undefined

  const amountInWei = (() => {
    try {
      return amountIn && parseFloat(amountIn) > 0
        ? parseUnits(amountIn, decimalsIn)
        : undefined
    } catch {
      return undefined
    }
  })()

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: tokenIn as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [address!, routerAddress!],
    query: {
      enabled: enabled && !!tokenIn && !!address && !!routerAddress,
    },
  })

  const needsApproval = !!amountInWei && (
    allowance === undefined || allowance < amountInWei
  )

  const {
    writeContract: doApprove,
    data: approveTxHash,
    isPending: isApprovePending,
    error: approveError,
    reset: resetApprove,
  } = useWriteContract()

  const {
    isLoading: isApproveConfirming,
    isSuccess: isApproveConfirmed,
  } = useWaitForTransactionReceipt({ hash: approveTxHash })

  useEffect(() => {
    if (isApproveConfirmed) refetchAllowance()
  }, [isApproveConfirmed, refetchAllowance])

  const {
    writeContract: doSwap,
    data: swapTxHash,
    isPending: isSwapPending,
    error: swapError,
    reset: resetSwap,
  } = useWriteContract()

  const {
    isLoading: isSwapConfirming,
    isSuccess: isSwapConfirmed,
  } = useWaitForTransactionReceipt({ hash: swapTxHash })

  const approve = useCallback(() => {
    if (!tokenIn || !routerAddress || !amountInWei) return
    doApprove({
      address: tokenIn as `0x${string}`,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [routerAddress, amountInWei],
    })
  }, [tokenIn, routerAddress, amountInWei, doApprove])

  const swap = useCallback(() => {
    if (!tokenIn || !tokenOut || !amountInWei || !amountOut || !address || !routerAddress) return
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 1200)
    const minOut = amountOut * 995n / 1000n

    doSwap({
      address: routerAddress,
      abi: SWAP_ROUTER_ABI,
      functionName: 'exactInputSingle',
      args: [{
        tokenIn: tokenIn as `0x${string}`,
        tokenOut: tokenOut as `0x${string}`,
        fee: 3000,
        recipient: address,
        deadline,
        amountIn: amountInWei,
        amountOutMinimum: minOut,
        sqrtPriceLimitX96: 0n,
      }],
    })
  }, [tokenIn, tokenOut, amountInWei, amountOut, address, routerAddress, doSwap])

  const reset = useCallback(() => {
    resetApprove()
    resetSwap()
  }, [resetApprove, resetSwap])

  return {
    needsApproval,
    isApproving: isApprovePending || isApproveConfirming,
    isSwapping: isSwapPending || isSwapConfirming,
    swapConfirmed: isSwapConfirmed,
    approve,
    swap,
    swapTxHash,
    error: approveError || swapError || undefined,
    reset,
    refetchAllowance,
  }
}
