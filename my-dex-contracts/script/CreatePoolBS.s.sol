// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IFactory {
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}

interface IPool {
    function initialize(uint160 sqrtPriceX96) external;
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
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
    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

contract CreatePoolBS is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address factory = vm.envAddress("FACTORY_ADDRESS");
        address bs = vm.envAddress("BS_ADDRESS");
        address ftb = vm.envAddress("FTB_ADDRESS");
        address positionManager = vm.envAddress("POSITION_MANAGER_ADDRESS");

        // Sort tokens (lower address = token0)
        (address token0, address token1) = bs < ftb ? (bs, ftb) : (ftb, bs);

        console.log("token0:", token0, IERC20(token0).symbol());
        console.log("token1:", token1, IERC20(token1).symbol());

        vm.startBroadcast(pk);

        // 1. Create pool
        address pool = IFactory(factory).getPool(token0, token1, 3000);
        if (pool == address(0)) {
            pool = IFactory(factory).createPool(bs, ftb, 3000);
            console.log("Pool CREATED:", pool);
        } else {
            console.log("Pool EXISTS:", pool);
        }

        // 2. Initialize price — 1 BS = 1 FTB (both 18 decimals, so 1:1)
        (uint160 existing, , , , , , ) = IPool(pool).slot0();
        if (existing == 0) {
            // Both tokens have 18 decimals, so price ratio is 1:1
            // sqrtPriceX96 = sqrt(1) * 2^96 = 2^96
            uint160 sqrtPriceX96 = 79228162514264337593543950336; // = 2^96
            IPool(pool).initialize(sqrtPriceX96);
            console.log("Price initialized: 1 BS = 1 FTB");
        }

        // 3. Add liquidity — 10,000 BS + 10,000 FTB
        uint256 amount = 10_000 * 1e18;
        IERC20(token0).approve(positionManager, type(uint256).max);
        IERC20(token1).approve(positionManager, type(uint256).max);

        (uint256 tokenId, uint128 liquidity, , ) = INonfungiblePositionManager(
            positionManager
        ).mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: 3000,
                    tickLower: -887220,
                    tickUpper: 887220,
                    amount0Desired: amount,
                    amount1Desired: amount,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: deployer,
                    deadline: block.timestamp + 600
                })
            );

        vm.stopBroadcast();

        console.log("NFT tokenId:", tokenId);
        console.log("Liquidity:", uint256(liquidity));
        console.log("Pool setup complete!");
    }
}
