import { create } from "zustand";

type SlippagePreset = 0.1 | 0.5 | 1.0;

interface SwapSettingsState {
  slippage: number;
  isCustom: boolean;
  setPreset: (value: SlippagePreset) => void;
  setCustom: (value: number) => void;
}

export const useSwapSettings = create<SwapSettingsState>((set) => ({
  slippage: 0.5,
  isCustom: false,
  setPreset: (value) => set({ slippage: value, isCustom: false }),
  setCustom: (value) => set({ slippage: value, isCustom: true }),
}));
