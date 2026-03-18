import type { ReactNode } from "react";
import Header from "./Header";

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <div className="relative min-h-screen bg-background text-white">
      {/* Ambient background glow */}
      <div
        aria-hidden
        className="pointer-events-none fixed inset-0 z-0"
        style={{
          background:
            "radial-gradient(ellipse 60% 50% at 50% 40%, rgba(0,245,160,0.07) 0%, rgba(0,217,245,0.03) 40%, transparent 70%)",
        }}
      />

      <Header />

      <main className="relative z-10 mx-auto max-w-7xl px-4 pt-20 pb-12">
        {children}
      </main>
    </div>
  );
}
