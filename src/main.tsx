import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { WagmiProvider, http } from "wagmi";
import { sepolia } from "wagmi/chains";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RainbowKitProvider, getDefaultConfig } from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";
import "./index.css";
import App from "./App";

const alchemyKey = import.meta.env.VITE_ALCHEMY_API_KEY as string | undefined;

const config = getDefaultConfig({
  appName: "FreeTheBlocks",
  projectId: (import.meta.env.VITE_WALLET_CONNECT_PROJECT_ID as string) || "placeholder",
  chains: [sepolia],
  transports: {
    [sepolia.id]: http(
      alchemyKey
        ? `https://eth-sepolia.g.alchemy.com/v2/${alchemyKey}`
        : undefined
    ),
  },
});

const queryClient = new QueryClient();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          <App />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </StrictMode>
);
