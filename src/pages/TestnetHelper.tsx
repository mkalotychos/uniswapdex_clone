import { useState, useEffect } from "react";
import { useAccount, useChainId, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseUnits } from "viem";
import { Copy, Check, ExternalLink } from "lucide-react";
import { getAddresses, SEPOLIA_CHAIN_ID } from "../constants/deployments";
import { FTB_ABI, TUSDC_ABI } from "../abis";
import { useTokenBalance } from "../hooks/useTokenBalance";

const ETHERSCAN = "https://sepolia.etherscan.io";

function AddTokenButton({ symbol, tokenAddress, decimals }: {
  symbol: string;
  tokenAddress: string;
  decimals: number;
}) {
  const [added, setAdded] = useState(false);

  const handleAdd = async () => {
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (window as any).ethereum?.request({
        method: "wallet_watchAsset",
        params: {
          type: "ERC20",
          options: { address: tokenAddress, symbol, decimals },
        },
      });
      setAdded(true);
      setTimeout(() => setAdded(false), 3000);
    } catch {
      /* user rejected */
    }
  };

  return (
    <button
      onClick={handleAdd}
      className="flex-1 rounded-xl border border-border bg-background px-4 py-3 text-sm font-semibold text-white transition-colors hover:border-primary/50 hover:bg-primary/5"
    >
      {added ? `✓ ${symbol} Added!` : `Add ${symbol}`}
    </button>
  );
}

function MintCard({ symbol, tokenAddress, decimals, abi, defaultAmount, maxAmount }: {
  symbol: string;
  tokenAddress: string;
  decimals: number;
  abi: typeof FTB_ABI;
  defaultAmount: string;
  maxAmount: string;
}) {
  const { address } = useAccount();
  const balance = useTokenBalance(tokenAddress, decimals);
  const [amount, setAmount] = useState(defaultAmount);

  const {
    writeContract,
    data: txHash,
    isPending,
    error,
    reset,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (isConfirmed) balance.refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConfirmed]);

  const handleMint = () => {
    if (!address) return;
    const parsed = parseFloat(amount);
    if (isNaN(parsed) || parsed <= 0 || parsed > parseFloat(maxAmount)) return;
    writeContract({
      address: tokenAddress as `0x${string}`,
      abi,
      functionName: "mint",
      args: [address, parseUnits(amount, decimals)],
    });
  };

  const balanceDisplay = parseFloat(balance.formatted).toLocaleString("en-US", {
    maximumFractionDigits: decimals > 8 ? 4 : 2,
  });

  return (
    <div className="rounded-xl border border-border bg-background p-4">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="font-semibold text-white">{symbol}</h3>
        <span className="text-sm text-gray-400">Balance: {balanceDisplay}</span>
      </div>

      <div className="mb-3">
        <input
          type="text"
          value={amount}
          onChange={(e) => {
            setAmount(e.target.value.replace(/[^0-9.]/g, ""));
            if (isConfirmed) reset();
          }}
          placeholder={`Max: ${maxAmount}`}
          className="w-full rounded-lg bg-surface px-3 py-2 text-sm text-white outline-none placeholder:text-gray-500 focus:ring-1 focus:ring-primary/40"
        />
      </div>

      <button
        onClick={handleMint}
        disabled={isPending || isConfirming || !address}
        className="w-full rounded-lg py-2.5 text-sm font-semibold transition-all disabled:cursor-not-allowed disabled:opacity-60"
        style={{
          background: isConfirmed
            ? "rgba(0, 245, 160, 0.15)"
            : "linear-gradient(135deg, #00f5a0, #00d9f5)",
          color: isConfirmed ? "#00f5a0" : "#000",
        }}
      >
        {isPending
          ? "Waiting for wallet..."
          : isConfirming
            ? "Confirming..."
            : isConfirmed
              ? `✓ Minted ${symbol}!`
              : `Mint ${symbol}`}
      </button>

      {txHash && (
        <a
          href={`${ETHERSCAN}/tx/${txHash}`}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-2 flex items-center justify-center gap-1 text-xs text-primary hover:underline"
        >
          View on Etherscan <ExternalLink className="h-3 w-3" />
        </a>
      )}

      {error && (
        <p className="mt-2 text-xs text-red-400">
          {error.message.slice(0, 80)}
        </p>
      )}
    </div>
  );
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button
      onClick={handleCopy}
      className="rounded p-1 text-gray-500 transition-colors hover:bg-white/5 hover:text-white"
    >
      {copied ? <Check className="h-3.5 w-3.5 text-primary" /> : <Copy className="h-3.5 w-3.5" />}
    </button>
  );
}

const CONTRACT_LABELS: [string, string][] = [
  ["Factory", "Factory"],
  ["SwapRouter", "SwapRouter"],
  ["QuoterV2", "QuoterV2"],
  ["PositionManager", "PositionManager"],
  ["FTBToken", "FTB Token"],
  ["tUSDC", "tUSDC"],
  ["BlocksmithToken", "Blocksmith (BS)"],
  ["MasterChef", "MasterChef"],
  ["VotingEscrow", "VotingEscrow"],
  ["FeeDistributor", "FeeDistributor"],
  ["BuyAndBurn", "BuyAndBurn"],
];

export default function TestnetHelper() {
  const chainId = useChainId();
  const { isConnected } = useAccount();

  if (chainId !== SEPOLIA_CHAIN_ID) {
    return (
      <div className="flex min-h-[calc(100vh-8rem)] items-center justify-center">
        <p className="text-gray-400">
          Switch to Sepolia testnet to access testnet tools.
        </p>
      </div>
    );
  }

  let addresses: ReturnType<typeof getAddresses> | null = null;
  try {
    addresses = getAddresses(chainId);
  } catch {
    /* fallback */
  }

  if (!addresses) {
    return (
      <div className="flex min-h-[calc(100vh-8rem)] items-center justify-center">
        <p className="text-gray-400">No deployment found for this network.</p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-8 py-8">
      <h1 className="text-2xl font-bold text-white">Testnet Tools</h1>

      {/* Section 1: Add Tokens to MetaMask */}
      <section className="rounded-2xl border border-border bg-surface p-6">
        <h2 className="mb-4 text-lg font-semibold text-white">
          Add Tokens to MetaMask
        </h2>
        <div className="flex flex-wrap gap-4">
          <AddTokenButton
            symbol="FTB"
            tokenAddress={addresses.FTBToken}
            decimals={18}
          />
          <AddTokenButton
            symbol="tUSDC"
            tokenAddress={addresses.tUSDC}
            decimals={6}
          />
          <AddTokenButton
            symbol="BS"
            tokenAddress={addresses.BlocksmithToken}
            decimals={18}
          />
        </div>
      </section>

      {/* Section 2: Faucet */}
      <section className="rounded-2xl border border-border bg-surface p-6">
        <h2 className="mb-4 text-lg font-semibold text-white">
          Faucet — Get Test Tokens
        </h2>
        {!isConnected ? (
          <p className="text-sm text-gray-400">
            Connect your wallet to mint test tokens.
          </p>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <MintCard
              symbol="FTB"
              tokenAddress={addresses.FTBToken}
              decimals={18}
              abi={FTB_ABI}
              defaultAmount="1000"
              maxAmount="10000"
            />
            <MintCard
              symbol="tUSDC"
              tokenAddress={addresses.tUSDC}
              decimals={6}
              abi={TUSDC_ABI}
              defaultAmount="5000"
              maxAmount="100000"
            />
            <MintCard
              symbol="BS"
              tokenAddress={addresses.BlocksmithToken}
              decimals={18}
              abi={FTB_ABI}
              defaultAmount="1000"
              maxAmount="10000"
            />
          </div>
        )}
      </section>

      {/* Section 3: Deployed Contracts */}
      <section className="rounded-2xl border border-border bg-surface p-6">
        <h2 className="mb-4 text-lg font-semibold text-white">
          Deployed Contracts
        </h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border text-left text-gray-500">
                <th className="pb-3 font-medium">Contract</th>
                <th className="pb-3 font-medium">Address</th>
                <th className="pb-3 font-medium">Links</th>
              </tr>
            </thead>
            <tbody>
              {CONTRACT_LABELS.map(([key, label]) => {
                const addr =
                  addresses![key as keyof typeof addresses] ?? "";
                return (
                  <tr key={key} className="border-b border-border/50">
                    <td className="py-3 font-medium text-gray-300">
                      {label}
                    </td>
                    <td className="py-3 font-mono text-xs text-gray-400">
                      {addr.slice(0, 6)}...{addr.slice(-4)}
                    </td>
                    <td className="flex items-center gap-1 py-3">
                      <CopyButton text={addr} />
                      <a
                        href={`${ETHERSCAN}/address/${addr}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="rounded p-1 text-gray-500 transition-colors hover:bg-white/5 hover:text-white"
                      >
                        <ExternalLink className="h-3.5 w-3.5" />
                      </a>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
