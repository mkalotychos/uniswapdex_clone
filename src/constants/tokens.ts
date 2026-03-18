export interface Token {
  symbol: string;
  name: string;
  address: string;
  decimals: number;
  logoURI: string;
}

const TW_ASSETS = "https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets";

export const MOCK_TOKENS: Token[] = [
  {
    symbol: "ETH",
    name: "Ethereum",
    address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
    decimals: 18,
    logoURI: `${TW_ASSETS}/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2/logo.png`,
  },
  {
    symbol: "USDC",
    name: "USD Coin",
    address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    decimals: 6,
    logoURI: `${TW_ASSETS}/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48/logo.png`,
  },
  {
    symbol: "USDT",
    name: "Tether USD",
    address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    decimals: 6,
    logoURI: `${TW_ASSETS}/0xdAC17F958D2ee523a2206206994597C13D831ec7/logo.png`,
  },
  {
    symbol: "DAI",
    name: "Dai Stablecoin",
    address: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    decimals: 18,
    logoURI: `${TW_ASSETS}/0x6B175474E89094C44Da98b954EedeAC495271d0F/logo.png`,
  },
  {
    symbol: "WBTC",
    name: "Wrapped BTC",
    address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
    decimals: 8,
    logoURI: `${TW_ASSETS}/0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599/logo.png`,
  },
  {
    symbol: "UNI",
    name: "Uniswap",
    address: "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984",
    decimals: 18,
    logoURI: `${TW_ASSETS}/0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984/logo.png`,
  },
  {
    symbol: "LINK",
    name: "Chainlink",
    address: "0x514910771AF9Ca656af840dff83E8264EcF986CA",
    decimals: 18,
    logoURI: `${TW_ASSETS}/0x514910771AF9Ca656af840dff83E8264EcF986CA/logo.png`,
  },
  {
    symbol: "AAVE",
    name: "Aave",
    address: "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9",
    decimals: 18,
    logoURI: `${TW_ASSETS}/0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9/logo.png`,
  },
];
