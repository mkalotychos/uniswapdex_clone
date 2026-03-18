import { useState, useEffect, useRef } from "react";
import { useAccount, useBalance, useDisconnect } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { Copy, Check, ExternalLink, LogOut } from "lucide-react";

function truncateAddress(address: string) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function formatBalance(value: bigint | undefined, decimals: number) {
  if (value === undefined) return "0.0000";
  const divisor = 10 ** decimals;
  const num = Number(value) / divisor;
  return num.toFixed(4);
}

export default function WalletButton() {
  const { address, isConnected, chain } = useAccount();
  const { data: balance } = useBalance({ address });
  const { disconnect } = useDisconnect();
  const { openConnectModal } = useConnectModal();

  const [dropdownOpen, setDropdownOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (
        containerRef.current &&
        !containerRef.current.contains(e.target as Node)
      ) {
        setDropdownOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleCopy = async () => {
    if (!address) return;
    await navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const etherscanBase =
    chain?.id === 11155111
      ? "https://sepolia.etherscan.io"
      : "https://etherscan.io";

  if (!isConnected) {
    return (
      <button
        onClick={() => openConnectModal?.()}
        className="relative rounded-xl px-5 py-2.5 text-sm font-bold text-black transition-all duration-200 hover:scale-[1.02] hover:brightness-110 active:scale-[0.98]"
        style={{
          background: "linear-gradient(135deg, #00f5a0, #00d9f5)",
        }}
      >
        Connect Wallet
      </button>
    );
  }

  const displayBalance = balance
    ? `${formatBalance(balance.value, balance.decimals)} ETH`
    : "0.0000 ETH";

  return (
    <div ref={containerRef} className="relative">
      <button
        onClick={() => setDropdownOpen((prev) => !prev)}
        className="flex items-center gap-2.5 rounded-xl border border-border bg-surface px-3 py-2 text-sm transition-colors hover:border-gray-500"
      >
        <span className="h-2 w-2 rounded-full bg-green-400 shadow-[0_0_6px_rgba(74,222,128,0.6)]" />
        <span className="text-gray-300">{displayBalance}</span>
        <span className="h-4 w-px bg-border" />
        <span className="font-medium text-white">
          {truncateAddress(address!)}
        </span>
      </button>

      {dropdownOpen && (
        <div className="absolute right-0 top-full z-50 mt-2 w-64 overflow-hidden rounded-xl border border-border bg-surface shadow-xl">
          {/* Copy address */}
          <button
            onClick={handleCopy}
            className="flex w-full items-center justify-between px-4 py-3 text-left text-sm text-gray-300 transition-colors hover:bg-white/5"
          >
            <span className="font-mono text-xs">
              {truncateAddress(address!)}
            </span>
            {copied ? (
              <Check className="h-4 w-4 text-primary" />
            ) : (
              <Copy className="h-4 w-4 text-gray-500" />
            )}
          </button>

          {/* Etherscan */}
          <a
            href={`${etherscanBase}/address/${address}`}
            target="_blank"
            rel="noopener noreferrer"
            className="flex w-full items-center justify-between px-4 py-3 text-left text-sm text-gray-300 transition-colors hover:bg-white/5"
          >
            View on Etherscan
            <ExternalLink className="h-4 w-4 text-gray-500" />
          </a>

          <div className="mx-3 border-t border-border" />

          {/* Disconnect */}
          <button
            onClick={() => {
              disconnect();
              setDropdownOpen(false);
            }}
            className="flex w-full items-center justify-between px-4 py-3 text-left text-sm text-red-400 transition-colors hover:bg-white/5"
          >
            Disconnect
            <LogOut className="h-4 w-4" />
          </button>
        </div>
      )}
    </div>
  );
}
