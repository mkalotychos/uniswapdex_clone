import { create } from "zustand";

export type ToastType = "info" | "success" | "error";

export interface Toast {
  id: string;
  type: ToastType;
  message: string;
}

interface ToastState {
  toasts: Toast[];
  add: (type: ToastType, message: string, duration?: number) => void;
  dismiss: (id: string) => void;
}

let counter = 0;

export const useToast = create<ToastState>((set, get) => ({
  toasts: [],
  add: (type, message, duration = 5000) => {
    const id = String(++counter);
    set({ toasts: [...get().toasts, { id, type, message }] });
    setTimeout(() => get().dismiss(id), duration);
  },
  dismiss: (id) => {
    set({ toasts: get().toasts.filter((t) => t.id !== id) });
  },
}));
