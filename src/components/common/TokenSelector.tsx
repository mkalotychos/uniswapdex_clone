import { useState, useEffect, useCallback, useRef } from "react";
import { X, Search } from "lucide-react";
import clsx from "clsx";
import { MOCK_TOKENS, type Token } from "../../constants/tokens";

const COMMON_SYMBOLS = ["FTB", "tUSDC", "ETH", "USDC", "USDT", "DAI", "WBTC"];

interface TokenSelectorProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (token: Token) => void;
  disabledToken?: Token;
}

function TokenLogo({ token, size = 36 }: { token: Token; size?: number }) {
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    setFailed(false);
  }, [token.address]);

  if (failed) {
    return (
      <div
        className="flex shrink-0 items-center justify-center rounded-full bg-primary/20 font-bold text-primary"
        style={{ width: size, height: size, fontSize: size * 0.4 }}
      >
        {token.symbol.charAt(0)}
      </div>
    );
  }

  return (
    <img
      src={token.logoURI}
      alt={token.symbol}
      width={size}
      height={size}
      className="shrink-0 rounded-full"
      onError={() => setFailed(true)}
    />
  );
}

export default function TokenSelector({
  isOpen,
  onClose,
  onSelect,
  disabledToken,
}: TokenSelectorProps) {
  const [query, setQuery] = useState("");
  const [visible, setVisible] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (isOpen) {
      requestAnimationFrame(() => setVisible(true));
      setTimeout(() => inputRef.current?.focus(), 80);
    } else {
      setVisible(false);
      setQuery("");
    }
  }, [isOpen]);

  const handleEsc = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    },
    [onClose]
  );

  useEffect(() => {
    if (isOpen) {
      document.addEventListener("keydown", handleEsc);
      return () => document.removeEventListener("keydown", handleEsc);
    }
  }, [isOpen, handleEsc]);

  if (!isOpen) return null;

  const lowerQuery = query.toLowerCase().trim();
  const filtered = MOCK_TOKENS.filter(
    (t) =>
      t.symbol.toLowerCase().includes(lowerQuery) ||
      t.name.toLowerCase().includes(lowerQuery) ||
      t.address.toLowerCase() === lowerQuery
  );

  const commonTokens = MOCK_TOKENS.filter((t) =>
    COMMON_SYMBOLS.includes(t.symbol)
  );

  const isDisabled = (t: Token) =>
    disabledToken?.address === t.address;

  const handleSelect = (token: Token) => {
    if (isDisabled(token)) return;
    onSelect(token);
    onClose();
  };

  return (
    <div
      className={clsx(
        "fixed inset-0 z-[100] flex items-center justify-center p-4 transition-all duration-200",
        visible ? "bg-black/60 backdrop-blur-sm" : "bg-transparent"
      )}
      onClick={onClose}
    >
      <div
        className={clsx(
          "flex max-h-[80vh] w-full max-w-md flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-2xl transition-all duration-200",
          visible
            ? "translate-y-0 scale-100 opacity-100"
            : "translate-y-4 scale-95 opacity-0"
        )}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 pt-5 pb-3">
          <h3 className="text-lg font-semibold text-white">Select a token</h3>
          <button
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-400 transition-colors hover:bg-white/10 hover:text-white"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Search */}
        <div className="px-5 pb-4">
          <div className="flex items-center gap-2.5 rounded-xl border border-border bg-background px-3 py-2.5 focus-within:border-primary/50">
            <Search className="h-4 w-4 shrink-0 text-gray-500" />
            <input
              ref={inputRef}
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search name or paste address"
              className="w-full bg-transparent text-sm text-white outline-none placeholder:text-gray-500"
            />
          </div>
        </div>

        {/* Common tokens */}
        <div className="px-5 pb-4">
          <p className="mb-2 text-xs font-medium text-gray-500">
            Common tokens
          </p>
          <div className="flex flex-wrap gap-2">
            {commonTokens.map((token) => (
              <button
                key={token.address}
                disabled={isDisabled(token)}
                onClick={() => handleSelect(token)}
                className={clsx(
                  "flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm font-medium transition-colors",
                  isDisabled(token)
                    ? "cursor-not-allowed border-border/50 text-gray-600"
                    : "border-border text-white hover:border-primary/50 hover:bg-primary/5"
                )}
              >
                <TokenLogo token={token} size={20} />
                {token.symbol}
              </button>
            ))}
          </div>
        </div>

        <div className="mx-5 border-t border-border" />

        {/* Token list */}
        <div className="flex-1 overflow-y-auto px-2 py-2">
          {filtered.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-gray-500">
              <Search className="mb-3 h-8 w-8 opacity-40" />
              <p className="text-sm">No tokens found</p>
            </div>
          ) : (
            filtered.map((token) => {
              const disabled = isDisabled(token);
              return (
                <button
                  key={token.address}
                  disabled={disabled}
                  onClick={() => handleSelect(token)}
                  className={clsx(
                    "flex w-full items-center gap-3 rounded-xl px-3 py-3 text-left transition-colors",
                    disabled
                      ? "cursor-not-allowed opacity-40"
                      : "hover:bg-white/5"
                  )}
                >
                  <TokenLogo token={token} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-white">
                      {token.symbol}
                    </p>
                    <p className="truncate text-xs text-gray-500">
                      {token.name}
                    </p>
                  </div>
                  <span className="text-sm text-gray-500">0.00</span>
                </button>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
