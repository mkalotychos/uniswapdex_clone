import { useState, useMemo } from "react";
import { ChevronDown } from "lucide-react";
import type { Token } from "../../constants/tokens";
import { MOCK_PRICES } from "../../constants/prices";
import TokenSelector from "../common/TokenSelector";

interface SwapInputProps {
  label: string;
  token: Token;
  otherToken: Token;
  amount: string;
  onAmountChange?: (value: string) => void;
  onTokenSelect: (token: Token) => void;
  readonly?: boolean;
  loading?: boolean;
  showMax?: boolean;
}

function TokenLogo({ token }: { token: Token }) {
  const [failed, setFailed] = useState(false);

  if (failed) {
    return (
      <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary/20 text-xs font-bold text-primary">
        {token.symbol.charAt(0)}
      </div>
    );
  }

  return (
    <img
      src={token.logoURI}
      alt={token.symbol}
      className="h-6 w-6 shrink-0 rounded-full"
      onError={() => setFailed(true)}
    />
  );
}

function formatUsd(amount: string, symbol: string): string {
  const num = parseFloat(amount);
  if (isNaN(num) || num === 0) return "$0.00";
  const price = MOCK_PRICES[symbol] ?? 0;
  return `$${(num * price).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

function inputFontSize(value: string): string {
  const len = value.length;
  if (len > 18) return "text-lg";
  if (len > 12) return "text-xl";
  if (len > 8) return "text-2xl";
  return "text-3xl";
}

export default function SwapInput({
  label,
  token,
  otherToken,
  amount,
  onAmountChange,
  onTokenSelect,
  readonly = false,
  loading = false,
  showMax = false,
}: SwapInputProps) {
  const [selectorOpen, setSelectorOpen] = useState(false);

  const usdValue = useMemo(() => formatUsd(amount, token.symbol), [amount, token.symbol]);

  const handleInput = (val: string) => {
    if (!onAmountChange) return;
    const cleaned = val.replace(/[^0-9.]/g, "");
    if (cleaned.split(".").length > 2) return;
    onAmountChange(cleaned);
  };

  return (
    <>
      <div className="rounded-xl bg-background p-4">
        <div className="mb-2 flex items-center justify-between">
          <span className="text-sm text-gray-400">{label}</span>
          {showMax && (
            <button
              onClick={() => onAmountChange?.("0")}
              className="text-xs font-medium text-primary hover:text-primary/80"
            >
              MAX
            </button>
          )}
        </div>

        <div className="flex items-center gap-3">
          <div className="relative min-w-0 flex-1">
            <input
              type="text"
              inputMode="decimal"
              value={amount}
              onChange={(e) => handleInput(e.target.value)}
              readOnly={readonly}
              placeholder="0"
              className={`w-full bg-transparent font-semibold text-white outline-none placeholder:text-gray-600 ${inputFontSize(amount)} ${
                readonly ? "cursor-default" : ""
              }`}
            />
            {loading && (
              <div className="absolute right-0 top-1/2 -translate-y-1/2">
                <div className="h-5 w-5 animate-spin rounded-full border-2 border-primary/30 border-t-primary" />
              </div>
            )}
          </div>

          <button
            onClick={() => setSelectorOpen(true)}
            className="flex shrink-0 items-center gap-2 rounded-xl bg-surface px-3 py-2 transition-colors hover:bg-white/10"
          >
            <TokenLogo token={token} />
            <span className="text-base font-semibold text-white">
              {token.symbol}
            </span>
            <ChevronDown className="h-4 w-4 text-gray-400" />
          </button>
        </div>

        <div className="mt-2 flex items-center justify-between">
          <span className="text-sm text-gray-500">{usdValue}</span>
          <span className="text-sm text-gray-500">Balance: 0.00</span>
        </div>
      </div>

      <TokenSelector
        isOpen={selectorOpen}
        onClose={() => setSelectorOpen(false)}
        onSelect={onTokenSelect}
        disabledToken={otherToken}
      />
    </>
  );
}
