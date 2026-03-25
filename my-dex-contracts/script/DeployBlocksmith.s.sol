// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

contract DeployBlocksmith is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        bytes memory bytecode = vm.getCode(
            "BlocksmithToken.sol:BlocksmithToken"
        );
        address bsAddr;
        assembly {
            bsAddr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(bsAddr != address(0), "BS deployment failed");

        vm.stopBroadcast();

        console.log("Blocksmith (BS) deployed at:", bsAddr);
        console.log("Add this to deployments/sepolia.json:");
        console.log(
            string.concat('  "BlocksmithToken": "', vm.toString(bsAddr), '"')
        );
    }
}
