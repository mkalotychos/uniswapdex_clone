// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

// ──────────── Minimal interfaces for 0.7.6 contracts ────────────

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IFactory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IPool {
    function initialize(uint160 sqrtPriceX96) external;
    function slot0() external view returns (
        uint160 sqrtPriceX96, int24 tick, uint16 observationIndex,
        uint16 observationCardinality, uint16 observationCardinalityNext,
        uint8 feeProtocol, bool unlocked
    );
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

interface IMasterChef {
    function add(address, address, uint24, uint256) external;
    function poolLength() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════
//  FreeTheBlocks — Create Pool + Seed Liquidity (Sepolia)
// ═══════════════════════════════════════════════════════════
//
//  RUN:
//    source .env && \
//    FACTORY_ADDRESS=0x1823133D88a9E81092BeA794Cd696841d96261d9 \
//    FTB_ADDRESS=0xfea6d69A82f96A2AD3f71D380B4f9673da1bb045 \
//    TUSDC_ADDRESS=0xCe40c28887a61D3Dd6aa35fA0160A7909375c435 \
//    POSITION_MANAGER_ADDRESS=0xBa6C99810a811770F5A0e16f2703493b2d052863 \
//    QUOTER_ADDRESS=0x95d9b505549c17aa3e8bd917acDB7b82f6ae72Cd \
//    MASTERCHEF_ADDRESS=0xC2F16665fa07078E20C4933799E80D0A231a4F10 \
//    forge script script/CreatePool.s.sol \
//      --rpc-url $SEPOLIA_RPC_URL \
//      --private-key $PRIVATE_KEY \
//      --broadcast -vvvv
//
// ═══════════════════════════════════════════════════════════

contract CreatePool is Script {
    struct Env {
        address deployer;
        address factory;
        address ftb;
        address tusdc;
        address positionManager;
        address quoter;
        address masterChef;
        address token0;
        address token1;
        uint8 decimals0;
        uint8 decimals1;
        bool ftbIsToken0;
    }

    function run() external {
        Env memory e;

        uint256 pk = vm.envUint("PRIVATE_KEY");
        e.deployer         = vm.addr(pk);
        e.factory          = vm.envAddress("FACTORY_ADDRESS");
        e.ftb              = vm.envAddress("FTB_ADDRESS");
        e.tusdc            = vm.envAddress("TUSDC_ADDRESS");
        e.positionManager  = vm.envAddress("POSITION_MANAGER_ADDRESS");
        e.quoter           = vm.envAddress("QUOTER_ADDRESS");
        e.masterChef       = vm.envAddress("MASTERCHEF_ADDRESS");

        (e.token0, e.token1) = e.ftb < e.tusdc ? (e.ftb, e.tusdc) : (e.tusdc, e.ftb);
        e.ftbIsToken0 = (e.ftb == e.token0);
        e.decimals0   = IERC20(e.token0).decimals();
        e.decimals1   = IERC20(e.token1).decimals();

        console.log("Deployer:", e.deployer);
        console.log("token0:  ", e.token0, IERC20(e.token0).symbol());
        console.log("token1:  ", e.token1, IERC20(e.token1).symbol());
        console.log("");

        vm.startBroadcast(pk);

        address pool = _createPool(e);
        _initializePrice(e, pool);
        (uint256 tokenId, uint128 liquidity) = _addLiquidity(e, pool);
        _checkMasterChef(e);

        vm.stopBroadcast();

        _verifyQuote(e);

        console.log("");
        console.log("=============================================");
        console.log("  POOL SETUP COMPLETE");
        console.log("=============================================");
        console.log("  Pool:     ", pool);
        console.log("  fee:       3000 (0.3%)");
        console.log("  NFT ID:   ", tokenId);
        console.log("  Liquidity:", uint256(liquidity));
        console.log("=============================================");
    }

    // ════════════════════════════════════════════
    //  PART 1 — Create Pool
    // ════════════════════════════════════════════

    function _createPool(Env memory e) internal returns (address pool) {
        pool = IFactory(e.factory).getPool(e.token0, e.token1, 3000);

        if (pool == address(0)) {
            pool = IFactory(e.factory).createPool(e.ftb, e.tusdc, 3000);
            console.log("[1] Pool CREATED:", pool);
        } else {
            console.log("[1] Pool EXISTS: ", pool);
        }
    }

    // ════════════════════════════════════════════
    //  PART 2 — Initialize Price  (1 FTB = 1 tUSDC)
    // ════════════════════════════════════════════

    function _initializePrice(Env memory e, address pool) internal {
        (uint160 existing, , , , , , ) = IPool(pool).slot0();

        if (existing != 0) {
            console.log("[2] Already initialized, sqrtPriceX96:", uint256(existing));
            return;
        }

        uint160 sqrtPriceX96;
        if (e.ftbIsToken0) {
            // token0=FTB(18d), token1=tUSDC(6d) → price = 1e6/1e18
            sqrtPriceX96 = _encodePriceSqrt(1e6, 1e18);
        } else {
            // token0=tUSDC(6d), token1=FTB(18d) → price = 1e18/1e6
            sqrtPriceX96 = _encodePriceSqrt(1e18, 1e6);
        }

        IPool(pool).initialize(sqrtPriceX96);
        console.log("[2] Initialized, sqrtPriceX96:", uint256(sqrtPriceX96));
    }

    // ════════════════════════════════════════════
    //  PART 3 — Add Initial Liquidity (full range)
    // ════════════════════════════════════════════

    function _addLiquidity(Env memory e, address /* pool */)
        internal
        returns (uint256 tokenId, uint128 liquidity)
    {
        uint256 amt0 = 10_000 * (10 ** e.decimals0);
        uint256 amt1 = 10_000 * (10 ** e.decimals1);

        console.log("[3] Seeding liquidity...");
        console.log("    amount0:", amt0);
        console.log("    amount1:", amt1);

        require(IERC20(e.token0).balanceOf(e.deployer) >= amt0, "Low token0 bal");
        require(IERC20(e.token1).balanceOf(e.deployer) >= amt1, "Low token1 bal");

        IERC20(e.token0).approve(e.positionManager, type(uint256).max);
        IERC20(e.token1).approve(e.positionManager, type(uint256).max);

        uint256 amount0;
        uint256 amount1;

        (tokenId, liquidity, amount0, amount1) =
            INonfungiblePositionManager(e.positionManager).mint(
                INonfungiblePositionManager.MintParams({
                    token0:         e.token0,
                    token1:         e.token1,
                    fee:            3000,
                    tickLower:      -887220,   // full range (divisible by 60)
                    tickUpper:       887220,
                    amount0Desired: amt0,
                    amount1Desired: amt1,
                    amount0Min:     0,
                    amount1Min:     0,
                    recipient:      e.deployer,
                    deadline:       block.timestamp + 600
                })
            );

        console.log("    NFT tokenId:", tokenId);
        console.log("    liquidity:  ", uint256(liquidity));
        console.log("    amount0 used:", amount0);
        console.log("    amount1 used:", amount1);
    }

    // ════════════════════════════════════════════
    //  PART 4 — Verify with Quote (after broadcast)
    // ════════════════════════════════════════════

    function _verifyQuote(Env memory e) internal {
        uint256 ftbIn = 100 * 1e18;

        try IQuoterV2(e.quoter).quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn:           e.ftb,
                tokenOut:          e.tusdc,
                amountIn:          ftbIn,
                fee:               3000,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 amountOut, uint160, uint32, uint256) {
            console.log("");
            console.log("[4] Quote: 100 FTB ->", amountOut, "tUSDC wei");
            console.log("    (~", amountOut / 1e6, "tUSDC)");
        } catch {
            console.log("");
            console.log("[4] Quote reverted (pool may need more liquidity)");
        }
    }

    // ════════════════════════════════════════════
    //  PART 5 — MasterChef (skip if already added)
    // ════════════════════════════════════════════

    function _checkMasterChef(Env memory e) internal {
        uint256 len = IMasterChef(e.masterChef).poolLength();

        if (len == 0) {
            IMasterChef(e.masterChef).add(e.token0, e.token1, 3000, 100);
            console.log("[5] MasterChef: pool added (pid 0)");
        } else {
            console.log("[5] MasterChef: already has", len, "pool(s), skipping");
        }
    }

    // ──────────── Helpers ────────────

    /// @dev sqrtPriceX96 = sqrt(reserve1/reserve0) * 2^96
    ///      Uses 192-bit shift to maintain precision: sqrt((r1 << 192) / r0)
    function _encodePriceSqrt(uint256 reserve1, uint256 reserve0)
        internal
        pure
        returns (uint160)
    {
        return uint160(_sqrt((reserve1 << 192) / reserve0));
    }

    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = x / 2 + 1;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }
}
