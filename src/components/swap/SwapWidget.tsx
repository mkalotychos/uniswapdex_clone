import { useState, useEffect, useRef, useCallback } from "react";
import { ArrowDownUp, ChevronDown, ChevronUp } from "lucide-react";
import { useAccount } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import clsx from "clsx";
import { MOCK_TOKENS, type Token } from "../../constants/tokens";
import { MOCK_PRICES } from "../../constants/prices";
import { useSwapSettings } from "../../store/useSwapSettings";
import { useToast } from "../../store/useToast";
import SwapInput from "./SwapInput";
import SwapSettings from "./SwapSettings";

const DEFAULT_TOKEN_IN = MOCK_TOKENS[0]; // ETH
const DEFAULT_TOKEN_OUT = MOCK_TOKENS[1]; // USDC

function computeQuote(
  amountIn: string,
  tokenIn: Token,
  tokenOut: Token
): string {
  const input = parseFloat(amountIn);
  if (isNaN(input) || input === 0) return "";
  const priceIn = MOCK_PRICES[tokenIn.symbol] ?? 0;
  const priceOut = MOCK_PRICES[tokenOut.symbol] ?? 1;
  const output = (input * priceIn) / priceOut;
  return output.toFixed(6).replace(/\.?0+$/, "");
}

function formatRate(tokenIn: Token, tokenOut: Token, inverted: boolean) {
  const pIn = MOCK_PRICES[tokenIn.symbol] ?? 0;
  const pOut = MOCK_PRICES[tokenOut.symbol] ?? 1;

  if (inverted) {
    const rate = pOut / pIn;
    return `1 ${tokenOut.symbol} = ${rate.toLocaleString("en-US", {
      maximumFractionDigits: 6,
    })} ${tokenIn.symbol}`;
  }
  const rate = pIn / pOut;
  return `1 ${tokenIn.symbol} = ${rate.toLocaleString("en-US", {
    maximumFractionDigits: 2,
  })} ${tokenOut.symbol}`;
}

export default function SwapWidget() {
  const { isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const { slippage } = useSwapSettings();
  const toast = useToast();

  const [tokenIn, setTokenIn] = useState<Token>(DEFAULT_TOKEN_IN);
  const [tokenOut, setTokenOut] = useState<Token>(DEFAULT_TOKEN_OUT);
  const [amountIn, setAmountIn] = useState("");
  const [amountOut, setAmountOut] = useState("");
  const [quoteLoading, setQuoteLoading] = useState(false);
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [rateInverted, setRateInverted] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(null);

  const getQuote = useCallback(
    (input: string) => {
      if (debounceRef.current) clearTimeout(debounceRef.current);

      if (!input || parseFloat(input) === 0) {
        setAmountOut("");
        setQuoteLoading(false);
        return;
      }

      setQuoteLoading(true);
      debounceRef.current = setTimeout(() => {
        const result = computeQuote(input, tokenIn, tokenOut);
        setAmountOut(result);
        setQuoteLoading(false);
      }, 300);
    },
    [tokenIn, tokenOut]
  );

  useEffect(() => {
    getQuote(amountIn);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [amountIn, getQuote]);

  const handleSwapDirection = () => {
    setTokenIn(tokenOut);
    setTokenOut(tokenIn);
    setAmountIn(amountOut);
    setAmountOut(amountIn);
  };

  const hasAmount = amountIn !== "" && parseFloat(amountIn) > 0;
  const minReceived =
    amountOut && parseFloat(amountOut) > 0
      ? (parseFloat(amountOut) * (1 - slippage / 100)).toFixed(
          amountOut.includes(".") ? amountOut.split(".")[1].length : 2
        )
      : "0";

  const [swapping, setSwapping] = useState(false);

  const buttonState = !isConnected
    ? "connect"
    : !hasAmount
      ? "enter"
      : "swap";

  const handleSwap = () => {
    setSwapping(true);
    setTimeout(() => {
      setSwapping(false);
      toast.add("success", "Swap submitted — View on Etherscan");
    }, 2000);
  };

  return (
    <div className="w-full max-w-[480px] rounded-2xl border border-border bg-surface p-1 shadow-lg shadow-black/20">
      <div className="p-4">
        {/* Header */}
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-white">Swap</h2>
          <SwapSettings />
        </div>

        {/* Token In */}
        <SwapInput
          label="You pay"
          token={tokenIn}
          otherToken={tokenOut}
          amount={amountIn}
          onAmountChange={setAmountIn}
          onTokenSelect={(t) => {
            if (t.address === tokenOut.address) {
              handleSwapDirection();
            } else {
              setTokenIn(t);
            }
          }}
          showMax={isConnected}
        />

        {/* Direction toggle */}
        <div className="relative z-10 -my-2.5 flex justify-center">
          <button
            onClick={handleSwapDirection}
            className="group rounded-xl border-2 border-border bg-surface p-2 transition-all hover:border-primary"
          >
            <ArrowDownUp className="h-4 w-4 text-gray-400 transition-transform duration-300 group-hover:rotate-180 group-hover:text-primary" />
          </button>
        </div>

        {/* Token Out */}
        <SwapInput
          label="You receive"
          token={tokenOut}
          otherToken={tokenIn}
          amount={amountOut}
          onTokenSelect={(t) => {
            if (t.address === tokenIn.address) {
              handleSwapDirection();
            } else {
              setTokenOut(t);
            }
          }}
          readonly
          loading={quoteLoading}
        />
      </div>

      {/* Price details */}
      {hasAmount && amountOut && (
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
              {formatRate(tokenIn, tokenOut, rateInverted)}
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
                  <span className="text-gray-500">Price impact</span>
                  <span className="text-gray-300">0.01%</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">Min. received</span>
                  <span className="text-gray-300">
                    {minReceived} {tokenOut.symbol}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">Network fee</span>
                  <span className="text-gray-300">~$3.40</span>
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

      {/* Action button */}
      <div className="p-3 pt-2">
        {buttonState === "connect" && (
          <button
            onClick={() => openConnectModal?.()}
            className="w-full rounded-xl py-4 text-base font-bold text-black transition-all hover:scale-[1.01] hover:brightness-110 active:scale-[0.99]"
            style={{
              background: "linear-gradient(135deg, #00f5a0, #00d9f5)",
            }}
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

        {buttonState === "swap" && (
          <button
            onClick={handleSwap}
            disabled={swapping}
            className="flex w-full items-center justify-center gap-2 rounded-xl py-4 text-base font-bold text-black transition-all hover:scale-[1.01] hover:brightness-110 active:scale-[0.99] disabled:pointer-events-none disabled:opacity-70"
            style={{
              background: "linear-gradient(135deg, #00f5a0, #00d9f5)",
            }}
          >
            {swapping ? (
              <>
                <div className="h-5 w-5 animate-spin rounded-full border-2 border-black/30 border-t-black" />
                Swapping...
              </>
            ) : (
              "Swap"
            )}
          </button>
        )}
      </div>
    </div>
  );
}
