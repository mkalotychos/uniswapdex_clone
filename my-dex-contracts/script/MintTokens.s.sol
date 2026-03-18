// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ITestToken} from "./ITestToken.sol";

contract MintTokens is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address mintTo = vm.envAddress("MINT_TO");

        address ftbAddr = vm.envAddress("FTB_ADDRESS");
        address tusdcAddr = vm.envAddress("TUSDC_ADDRESS");

        ITestToken ftb = ITestToken(ftbAddr);
        ITestToken tusdc = ITestToken(tusdcAddr);

        console.log("Minting to:", mintTo);
        console.log("FTB at:", ftbAddr);
        console.log("tUSDC at:", tusdcAddr);

        vm.startBroadcast(deployerKey);

        // Mint 10,000 FTB (max per call)
        ftb.mint(mintTo, 10_000 * 1e18);
        console.log("Minted 10,000 FTB. Balance:", ftb.balanceOf(mintTo));

        // Mint 100,000 tUSDC (max per call)
        tusdc.mint(mintTo, 100_000 * 1e6);
        console.log("Minted 100,000 tUSDC. Balance:", tusdc.balanceOf(mintTo));

        vm.stopBroadcast();

        console.log("Done!");
    }
}
