import { Zap } from "lucide-react";

export default function LoadingScreen() {
  return (
    <div className="fixed inset-0 z-[999] flex flex-col items-center justify-center bg-background">
      <div className="animate-pulse">
        <div className="flex items-center gap-3">
          <Zap className="h-8 w-8 text-primary" fill="currentColor" />
          <span className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-3xl font-bold text-transparent">
            FreeTheBlocks
          </span>
        </div>
      </div>
    </div>
  );
}
