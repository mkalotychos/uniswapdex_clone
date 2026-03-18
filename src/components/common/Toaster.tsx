import { useEffect, useState } from "react";
import { X, CheckCircle, AlertCircle, Info } from "lucide-react";
import clsx from "clsx";
import { useToast, type Toast } from "../../store/useToast";

const ICON_MAP = {
  success: CheckCircle,
  error: AlertCircle,
  info: Info,
} as const;

const COLOR_MAP = {
  success: "text-primary",
  error: "text-red-400",
  info: "text-secondary",
} as const;

function ToastItem({ toast }: { toast: Toast }) {
  const { dismiss } = useToast();
  const [visible, setVisible] = useState(false);
  const Icon = ICON_MAP[toast.type];

  useEffect(() => {
    requestAnimationFrame(() => setVisible(true));
  }, []);

  const handleDismiss = () => {
    setVisible(false);
    setTimeout(() => dismiss(toast.id), 200);
  };

  return (
    <div
      className={clsx(
        "flex items-start gap-3 rounded-xl border border-border bg-surface px-4 py-3 shadow-xl transition-all duration-200",
        visible
          ? "translate-x-0 opacity-100"
          : "translate-x-8 opacity-0"
      )}
    >
      <Icon className={clsx("mt-0.5 h-5 w-5 shrink-0", COLOR_MAP[toast.type])} />
      <p className="flex-1 text-sm text-gray-200">{toast.message}</p>
      <button
        onClick={handleDismiss}
        className="shrink-0 text-gray-500 transition-colors hover:text-white"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}

export default function Toaster() {
  const { toasts } = useToast();

  if (toasts.length === 0) return null;

  return (
    <div className="fixed bottom-5 right-5 z-[200] flex w-80 flex-col gap-2">
      {toasts.map((toast) => (
        <ToastItem key={toast.id} toast={toast} />
      ))}
    </div>
  );
}
