import { useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { Zap } from "lucide-react";
import clsx from "clsx";
import WalletButton from "../common/WalletButton";

const NAV_LINKS = [
  { label: "Swap", to: "/", enabled: true },
  { label: "Pool", to: "/", enabled: false },
] as const;

export default function Header() {
  const location = useLocation();
  const [hoveredDisabled, setHoveredDisabled] = useState<string | null>(null);

  return (
    <header className="fixed top-0 left-0 right-0 z-50 h-16 border-b border-border bg-surface/80 backdrop-blur-xl">
      <div className="mx-auto flex h-full max-w-7xl items-center justify-between px-4">
        {/* Logo */}
        <Link to="/" className="flex items-center gap-2">
          <Zap className="h-5 w-5 text-primary" fill="currentColor" />
          <span className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-lg font-bold text-transparent">
            FreeTheBlocks
          </span>
        </Link>

        {/* Nav — hidden on mobile */}
        <nav className="hidden items-center gap-1 sm:flex">
          {NAV_LINKS.map((link) => {
            const isActive = link.enabled && location.pathname === link.to;

            if (!link.enabled) {
              return (
                <div
                  key={link.label}
                  className="relative"
                  onMouseEnter={() => setHoveredDisabled(link.label)}
                  onMouseLeave={() => setHoveredDisabled(null)}
                >
                  <span className="cursor-default rounded-lg px-4 py-2 text-sm font-medium text-gray-500">
                    {link.label}
                  </span>

                  {hoveredDisabled === link.label && (
                    <div className="absolute left-1/2 top-full mt-2 -translate-x-1/2 whitespace-nowrap rounded-lg border border-border bg-surface px-3 py-1.5 text-xs text-gray-400 shadow-lg">
                      Coming Soon
                      <div className="absolute -top-1 left-1/2 h-2 w-2 -translate-x-1/2 rotate-45 border-l border-t border-border bg-surface" />
                    </div>
                  )}
                </div>
              );
            }

            return (
              <Link
                key={link.label}
                to={link.to}
                className={clsx(
                  "rounded-lg px-4 py-2 text-sm font-medium transition-colors",
                  isActive
                    ? "bg-white/10 text-white"
                    : "text-gray-400 hover:text-white"
                )}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>

        <WalletButton />
      </div>
    </header>
  );
}
