import SwapWidget from "../components/swap/SwapWidget";

export default function SwapPage() {
  return (
    <div className="flex min-h-[calc(100vh-8rem)] flex-col items-center justify-center">
      <p className="mb-6 text-center text-sm font-medium tracking-wide text-gray-500">
        Swap tokens instantly
      </p>
      <SwapWidget />
    </div>
  );
}
