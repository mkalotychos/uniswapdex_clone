import { useState, useEffect } from "react";
import { ArrowDownUp, ChevronDown, ChevronUp } from "lucide-react";
import { useAccount, useChainId } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import clsx from "clsx";
import { MOCK_TOKENS, type Token } from "../../constants/tokens";
import { MOCK_PRICES } from "../../constants/prices";
import { useSwapSettings } from "../../store/useSwapSettings";
import { useToast } from "../../store/useToast";
import { useSwapQuote } from "../../hooks/useSwapQuote";
import { useSwapExecute } from "../../hooks/useSwapExecute";
import { useTokenBalance } from "../../hooks/useTokenBalance";
import { SEPOLIA_CHAIN_ID } from "../../constants/deployments";
import SwapInput from "./SwapInput";
import SwapSettings from "./SwapSettings";

function getSepoliaDefaults(): [Token, Token] {
  const ftb = MOCK_TOKENS.find((t) => t.symbol === "FTB");
  const tusdc = MOCK_TOKENS.find((t) => t.symbol === "tUSDC");
  if (ftb && tusdc) return [ftb, tusdc];
  return [MOCK_TOKENS[0], MOCK_TOKENS[1]];
}

export default function SwapWidget() {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const { openConnectModal } = useConnectModal();
  const { slippage } = useSwapSettings();
  const toast = useToast();

  const isSepolia = chainId === SEPOLIA_CHAIN_ID;

  const [defaults] = useState(getSepoliaDefaults);
  const [tokenIn, setTokenIn] = useState<Token>(defaults[0]);
  const [tokenOut, setTokenOut] = useState<Token>(defaults[1]);
  const [amountIn, setAmountIn] = useState("");
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [rateInverted, setRateInverted] = useState(false);

  const hasAmount = amountIn !== "" && parseFloat(amountIn) > 0;

  const {
    amountOut: quoteAmountOut,
    amountOutFormatted,
    isLoading: quoteLoading,
    noLiquidity,
  } = useSwapQuote({
    tokenIn: tokenIn.address,
    tokenOut: tokenOut.address,
    amountIn,
    decimalsIn: tokenIn.decimals,
    decimalsOut: tokenOut.decimals,
    enabled: hasAmount && isSepolia,
  });

  const displayAmountOut = amountOutFormatted ?? "";

  const balanceIn = useTokenBalance(
    isSepolia ? tokenIn.address : undefined,
    tokenIn.decimals
  );
  const balanceOut = useTokenBalance(
    isSepolia ? tokenOut.address : undefined,
    tokenOut.decimals
  );

  const {
    needsApproval,
    isApproving,
    isSwapping,
    swapConfirmed,
    approve,
    swap,
    swapTxHash,
    error: swapError,
    reset: resetSwap,
  } = useSwapExecute({
    tokenIn: tokenIn.address,
    tokenOut: tokenOut.address,
    amountIn,
    decimalsIn: tokenIn.decimals,
    amountOut: quoteAmountOut,
    enabled: hasAmount && !noLiquidity && isSepolia,
  });

  useEffect(() => {
    if (swapConfirmed && swapTxHash) {
      toast.add(
        "success",
        `Swap confirmed! https://sepolia.etherscan.io/tx/${swapTxHash}`,
        8000
      );
      setAmountIn("");
      balanceIn.refetch();
      balanceOut.refetch();
      resetSwap();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [swapConfirmed, swapTxHash]);

  useEffect(() => {
    if (swapError) {
      toast.add("error", swapError.message.slice(0, 120));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [swapError]);

  const handleSwapDirection = () => {
    setTokenIn(tokenOut);
    setTokenOut(tokenIn);
    setAmountIn(displayAmountOut);
  };

  const minReceived =
    displayAmountOut && parseFloat(displayAmountOut) > 0
      ? (parseFloat(displayAmountOut) * (1 - slippage / 100)).toFixed(6)
      : "0";

  const rateString = (() => {
    const inVal = parseFloat(amountIn);
    const outVal = parseFloat(displayAmountOut);
    if (inVal > 0 && outVal > 0) {
      if (rateInverted) {
        return `1 ${tokenOut.symbol} = ${(inVal / outVal).toFixed(6)} ${tokenIn.symbol}`;
      }
      return `1 ${tokenIn.symbol} = ${(outVal / inVal).toFixed(6)} ${tokenOut.symbol}`;
    }
    const pIn = MOCK_PRICES[tokenIn.symbol] ?? 0;
    const pOut = MOCK_PRICES[tokenOut.symbol] ?? 1;
    if (rateInverted) {
      return `1 ${tokenOut.symbol} = ${(pOut / pIn).toFixed(6)} ${tokenIn.symbol}`;
    }
    return `1 ${tokenIn.symbol} = ${(pIn / pOut).toFixed(2)} ${tokenOut.symbol}`;
  })();

  type BtnState =
    | "connect"
    | "enter"
    | "loading"
    | "noLiquidity"
    | "approve"
    | "approving"
    | "swapping"
    | "swap";

  const buttonState: BtnState = !isConnected
    ? "connect"
    : !hasAmount
      ? "enter"
      : quoteLoading
        ? "loading"
        : noLiquidity
          ? "noLiquidity"
          : needsApproval
            ? isApproving
              ? "approving"
              : "approve"
            : isSwapping
              ? "swapping"
              : "swap";

  const gradientStyle = {
    background: "linear-gradient(135deg, #00f5a0, #00d9f5)",
  };

  return (
    <div className="w-full max-w-[480px] rounded-2xl border border-border bg-surface p-1 shadow-lg shadow-black/20">
      <div className="p-4">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-white">Swap</h2>
          <SwapSettings />
        </div>

        <SwapInput
          label="You pay"
          token={tokenIn}
          otherToken={tokenOut}
          amount={amountIn}
          onAmountChange={setAmountIn}
          onTokenSelect={(t) => {
            if (t.address === tokenOut.address) handleSwapDirection();
            else setTokenIn(t);
          }}
          showMax={isConnected}
          balance={balanceIn.formatted}
        />

        <div className="relative z-10 -my-2.5 flex justify-center">
          <button
            onClick={handleSwapDirection}
            className="group rounded-xl border-2 border-border bg-surface p-2 transition-all hover:border-primary"
          >
            <ArrowDownUp className="h-4 w-4 text-gray-400 transition-transform duration-300 group-hover:rotate-180 group-hover:text-primary" />
          </button>
        </div>

        <SwapInput
          label="You receive"
          token={tokenOut}
          otherToken={tokenIn}
          amount={displayAmountOut}
          onTokenSelect={(t) => {
            if (t.address === tokenIn.address) handleSwapDirection();
            else setTokenOut(t);
          }}
          readonly
          loading={quoteLoading}
          balance={balanceOut.formatted}
        />
      </div>

      {hasAmount && displayAmountOut && (
        <div className="mx-1 mb-1 rounded-xl border border-border bg-background">
          <button
            onClick={() => setDetailsOpen((p) => !p)}
            className="flex w-full items-center justify-between px-4 py-3 text-sm"
          >
            <span
              onClick={(e) => {
                e.stopPropagation();
                setRateInverted((p) => !p);
              }}
              className="cursor-pointer text-gray-300 hover:text-white"
            >
              {rateString}
            </span>
            {detailsOpen ? (
              <ChevronUp className="h-4 w-4 text-gray-400" />
            ) : (
              <ChevronDown className="h-4 w-4 text-gray-400" />
            )}
          </button>

          <div
            className={clsx(
              "grid transition-all duration-200",
              detailsOpen
                ? "grid-rows-[1fr] opacity-100"
                : "grid-rows-[0fr] opacity-0"
            )}
          >
            <div className="overflow-hidden">
              <div className="space-y-2 border-t border-border px-4 pt-3 pb-4 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-500">Min. received</span>
                  <span className="text-gray-300">
                    {minReceived} {tokenOut.symbol}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">Slippage tolerance</span>
                  <span className="text-gray-300">{slippage}%</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">Route</span>
                  <span className="text-gray-300">
                    {tokenIn.symbol} → {tokenOut.symbol}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {hasAmount && noLiquidity && (
        <div className="mx-4 mb-2 rounded-lg bg-red-500/10 p-3 text-center text-sm text-red-400">
          Insufficient liquidity for this trade
        </div>
      )}

      <div className="p-3 pt-2">
        {buttonState === "connect" && (
          <button
            onClick={() => openConnectModal?.()}
            className="w-full rounded-xl py-4 text-base font-bold text-black transition-all hover:scale-[1.01] hover:brightness-110 active:scale-[0.99]"
            style={gradientStyle}
          >
            Connect Wallet
          </button>
        )}

        {buttonState === "enter" && (
          <button
            disabled
            className="w-full cursor-not-allowed rounded-xl bg-background py-4 text-base font-semibold text-gray-500"
          >
            Enter an amount
          </button>
        )}

        {buttonState === "loading" && (
          <button
            disabled
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-background py-4 text-base font-semibold text-gray-400"
          >
            <div className="h-5 w-5 animate-spin rounded-full border-2 border-gray-500/30 border-t-gray-400" />
            Fetching quote...
          </button>
        )}

        {buttonState === "noLiquidity" && (
          <button
            disabled
            className="w-full cursor-not-allowed rounded-xl bg-red-500/10 py-4 text-base font-semibold text-red-400"
          >
            Insufficient liquidity
          </button>
        )}

        {buttonState === "approve" && (
          <button
            onClick={approve}
            className="w-full rounded-xl py-4 text-base font-bold text-black transition-all hover:scale-[1.01] hover:brightness-110 active:scale-[0.99]"
            style={gradientStyle}
          >
            Approve {tokenIn.symbol}
          </button>
        )}

        {buttonState === "approving" && (
          <button
            disabled
            className="flex w-full items-center justify-center gap-2 rounded-xl py-4 text-base font-bold text-black/70 opacity-70"
            style={gradientStyle}
          >
            <div className="h-5 w-5 animate-spin rounded-full border-2 border-black/30 border-t-black" />
            Approving...
          </button>
        )}

        {buttonState === "swapping" && (
          <button
            disabled
            className="flex w-full items-center justify-center gap-2 rounded-xl py-4 text-base font-bold text-black/70 opacity-70"
            style={gradientStyle}
          >
            <div className="h-5 w-5 animate-spin rounded-full border-2 border-black/30 border-t-black" />
            Swapping...
          </button>
        )}

        {buttonState === "swap" && (
          <button
            onClick={swap}
            className="w-full rounded-xl py-4 text-base font-bold text-black transition-all hover:scale-[1.01] hover:brightness-110 active:scale-[0.99]"
            style={gradientStyle}
          >
            Swap
          </button>
        )}
      </div>
    </div>
  );
}
