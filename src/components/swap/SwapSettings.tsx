import { useState, useEffect, useRef } from "react";
import { Settings } from "lucide-react";
import clsx from "clsx";
import { useSwapSettings } from "../../store/useSwapSettings";

const PRESETS = [0.1, 0.5, 1.0] as const;

export default function SwapSettings() {
  const { slippage, isCustom, setPreset, setCustom } = useSwapSettings();
  const [open, setOpen] = useState(false);
  const [customInput, setCustomInput] = useState("");
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  useEffect(() => {
    if (open && isCustom) {
      setCustomInput(String(slippage));
    }
  }, [open, isCustom, slippage]);

  const handleCustomChange = (val: string) => {
    setCustomInput(val);
    const num = parseFloat(val);
    if (!isNaN(num) && num > 0 && num <= 50) {
      setCustom(num);
    }
  };

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen((p) => !p)}
        className={clsx(
          "rounded-lg p-2 text-gray-400 transition-colors hover:bg-white/10 hover:text-white",
          open && "bg-white/10 text-white"
        )}
      >
        <Settings className="h-5 w-5" />
      </button>

      {open && (
        <div className="absolute right-0 top-full z-50 mt-2 w-72 rounded-xl border border-border bg-surface p-4 shadow-xl">
          <p className="mb-3 text-sm font-medium text-white">
            Slippage tolerance
          </p>

          <div className="flex items-center gap-2">
            {PRESETS.map((val) => (
              <button
                key={val}
                onClick={() => {
                  setPreset(val);
                  setCustomInput("");
                }}
                className={clsx(
                  "flex-1 rounded-lg py-2 text-sm font-medium transition-colors",
                  !isCustom && slippage === val
                    ? "bg-primary/15 text-primary"
                    : "bg-background text-gray-400 hover:text-white"
                )}
              >
                {val}%
              </button>
            ))}

            <div
              className={clsx(
                "flex flex-1 items-center rounded-lg px-2 py-1.5 transition-colors",
                isCustom
                  ? "bg-primary/15 ring-1 ring-primary/40"
                  : "bg-background"
              )}
            >
              <input
                type="text"
                inputMode="decimal"
                value={customInput}
                onChange={(e) => handleCustomChange(e.target.value)}
                onFocus={() => {
                  if (!isCustom) setCustomInput("");
                }}
                placeholder="Custom"
                className="w-full bg-transparent text-right text-sm text-white outline-none placeholder:text-gray-500"
              />
              <span className="ml-0.5 text-sm text-gray-400">%</span>
            </div>
          </div>

          {slippage > 5 && (
            <p className="mt-2 text-xs text-yellow-400">
              High slippage — your trade may be frontrun
            </p>
          )}
        </div>
      )}
    </div>
  );
}
