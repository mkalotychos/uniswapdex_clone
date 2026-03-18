// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ITestToken} from "./ITestToken.sol";

contract DeployTokens is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerKey);

        // Deploy FTB token (0.7.6 bytecode via getCode)
        bytes memory ftbBytecode = vm.getCode(
            "FreeTheBlocksTestToken.sol:FreeTheBlocksTestToken"
        );
        address ftbAddr;
        assembly {
            ftbAddr := create(0, add(ftbBytecode, 0x20), mload(ftbBytecode))
        }
        require(ftbAddr != address(0), "FTB deployment failed");
        ITestToken ftb = ITestToken(ftbAddr);

        console.log("FTB deployed at:", ftbAddr);
        console.log("  name:", ftb.name());
        console.log("  symbol:", ftb.symbol());
        console.log("  decimals:", ftb.decimals());
        console.log("  deployer balance:", ftb.balanceOf(deployer));

        // Deploy tUSDC token (0.7.6 bytecode via getCode)
        bytes memory usdcBytecode = vm.getCode(
            "FreeTheBlocksTestUSDC.sol:FreeTheBlocksTestUSDC"
        );
        address usdcAddr;
        assembly {
            usdcAddr := create(0, add(usdcBytecode, 0x20), mload(usdcBytecode))
        }
        require(usdcAddr != address(0), "tUSDC deployment failed");
        ITestToken tusdc = ITestToken(usdcAddr);

        console.log("tUSDC deployed at:", usdcAddr);
        console.log("  name:", tusdc.name());
        console.log("  symbol:", tusdc.symbol());
        console.log("  decimals:", tusdc.decimals());
        console.log("  deployer balance:", tusdc.balanceOf(deployer));

        // Mint extra tokens for testing (respecting per-call limits)
        for (uint256 i = 0; i < 10; i++) {
            ftb.mint(deployer, 10_000 * 1e18);   // 10k FTB × 10 = 100k
        }
        console.log("Minted 100k FTB. New balance:", ftb.balanceOf(deployer));

        for (uint256 i = 0; i < 5; i++) {
            tusdc.mint(deployer, 100_000 * 1e6);  // 100k tUSDC × 5 = 500k
        }
        console.log("Minted 500k tUSDC. New balance:", tusdc.balanceOf(deployer));

        vm.stopBroadcast();

        console.log("");
        console.log("=== COPY TO FRONTEND (.env) ===");
        console.log(string.concat("VITE_FTB_ADDRESS=", vm.toString(ftbAddr)));
        console.log(string.concat("VITE_TUSDC_ADDRESS=", vm.toString(usdcAddr)));
    }
}
