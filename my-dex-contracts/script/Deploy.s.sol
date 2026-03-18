// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

// ──────────── Interfaces for 0.7.6 contracts ────────────

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface ITestToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IFactory {
    function owner() external view returns (address);
    function setTreasury(address) external;
    function setFeeCollector(address) external;
    function setPendingOwner(address) external;
}

interface IMasterChef {
    function add(address, address, uint24, uint256) external;
}

// ═══════════════════════════════════════════════════════════
//  FreeTheBlocks — Master Deployment Script (Sepolia)
// ═══════════════════════════════════════════════════════════
//
//  BEFORE RUNNING:
//  1. cp .env.example .env && fill in PRIVATE_KEY, SEPOLIA_RPC_URL
//  2. Compute the pool INIT_CODE_HASH:
//       forge inspect FreeTheBlocksPool bytecode | xargs cast keccak
//     Set the result as INIT_CODE_HASH in .env
//  3. Build: forge build
//
//  RUN LOCALLY (Anvil):
//    anvil &
//    forge script script/Deploy.s.sol --rpc-url localhost --broadcast
//
//  RUN ON SEPOLIA:
//    forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
//
// ═══════════════════════════════════════════════════════════

contract Deploy is Script {
    address constant WETH9 = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    struct Deployment {
        // Test tokens
        address ftb;
        address tusdc;
        // Governance
        address fblk;
        address teamVesting;
        address investorVesting;
        // V3 Core
        address factory;
        bytes32 poolHash;
        // V3 Periphery
        address positionManager;
        address swapRouter;
        address quoter;
        // Staking
        address masterChef;
        uint256 startBlock;
        // Tokenomics
        address votingEscrow;
        address feeDistributor;
        address buyAndBurn;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);
        console.log("Balance :", deployer.balance);
        console.log("");

        vm.startBroadcast(pk);

        Deployment memory d;

        _deployTestTokens(d, deployer);
        _deployGovernance(d, deployer);
        _deployV3Core(d);
        _deployV3Periphery(d);
        _deployStaking(d, deployer);
        _deployTokenomics(d);
        _wireContracts(d, deployer);

        vm.stopBroadcast();

        _logSummary(d);
    }

    // ════════════════════════════════════════════
    //  STEP 1 — Test Tokens
    // ════════════════════════════════════════════

    function _deployTestTokens(Deployment memory d, address deployer) internal {
        d.ftb   = _deploy("FreeTheBlocksTestToken.sol:FreeTheBlocksTestToken", "");
        d.tusdc = _deploy("FreeTheBlocksTestUSDC.sol:FreeTheBlocksTestUSDC", "");

        for (uint256 i = 0; i < 10; i++) {
            ITestToken(d.ftb).mint(deployer, 10_000 * 1e18);
        }
        for (uint256 i = 0; i < 5; i++) {
            ITestToken(d.tusdc).mint(deployer, 100_000 * 1e6);
        }
    }

    // ════════════════════════════════════════════
    //  STEP 2 & 3 — FBLK + Vesting Wallets
    // ════════════════════════════════════════════
    //  FreeTheBlocksToken requires non-zero addresses for all 5 allocations.
    //  We deploy with deployer as all recipients (gets 100M FBLK), then
    //  transfer to vesting wallets and MasterChef in later steps.

    function _deployGovernance(Deployment memory d, address deployer) internal {
        d.fblk = _deploy(
            "FreeTheBlocksToken.sol:FreeTheBlocksToken",
            abi.encode(deployer, deployer, deployer, deployer, deployer)
        );

        // On testnet: beneficiary & treasury both = deployer
        d.teamVesting = _deploy(
            "VestingWallet.sol:VestingWallet",
            abi.encode(
                d.fblk,             // token
                deployer,           // beneficiary
                deployer,           // treasury (for cancel)
                block.timestamp,    // start
                365 days,           // cliff: 1 year
                4 * 365 days,       // total vesting: 4 years
                20_000_000 * 1e18   // 20M FBLK (20%)
            )
        );

        d.investorVesting = _deploy(
            "VestingWallet.sol:VestingWallet",
            abi.encode(
                d.fblk,
                deployer,
                deployer,
                block.timestamp,
                365 days,
                4 * 365 days,
                10_000_000 * 1e18   // 10M FBLK (10%)
            )
        );

        IERC20(d.fblk).transfer(d.teamVesting,     20_000_000 * 1e18);
        IERC20(d.fblk).transfer(d.investorVesting,  10_000_000 * 1e18);
    }

    // ════════════════════════════════════════════
    //  STEP 4 — V3 Core (Factory)
    // ════════════════════════════════════════════

    function _deployV3Core(Deployment memory d) internal {
        d.factory = _deploy("FreeTheBlocksFactory.sol:FreeTheBlocksFactory", "");

        d.poolHash = keccak256(
            vm.getCode("FreeTheBlocksPool.sol:FreeTheBlocksPool")
        );

        bytes32 expectedHash = vm.envBytes32("INIT_CODE_HASH");
        require(
            d.poolHash == expectedHash,
            "INIT_CODE_HASH MISMATCH - update PoolAddress.sol in periphery"
        );
    }

    // ════════════════════════════════════════════
    //  STEP 5 — V3 Periphery
    // ════════════════════════════════════════════
    //  Deployed from lib/v3-periphery compiled artifacts.
    //  PoolAddress.sol in periphery MUST have the correct
    //  INIT_CODE_HASH for FreeTheBlocksPool before deploying.

    function _deployV3Periphery(Deployment memory d) internal {
        d.positionManager = _deploy(
            "NonfungiblePositionManager.sol:NonfungiblePositionManager",
            abi.encode(d.factory, WETH9, address(0))
        );

        d.swapRouter = _deploy(
            "SwapRouter.sol:SwapRouter",
            abi.encode(d.factory, WETH9)
        );

        d.quoter = _deploy(
            "QuoterV2.sol:QuoterV2",
            abi.encode(d.factory, WETH9)
        );
    }

    // ════════════════════════════════════════════
    //  STEP 6 — Staking (MasterChef)
    // ════════════════════════════════════════════

    function _deployStaking(Deployment memory d, address deployer) internal {
        d.startBlock = block.number + 100;

        d.masterChef = _deploy(
            "MasterChef.sol:MasterChef",
            abi.encode(d.fblk, d.positionManager, d.startBlock)
        );

        IERC20(d.fblk).transfer(d.masterChef, 40_000_000 * 1e18);

        // Add FTB/tUSDC as incentivized pool (100% of emissions)
        IMasterChef(d.masterChef).add(d.ftb, d.tusdc, 3000, 100);
    }

    // ════════════════════════════════════════════
    //  STEP 7 — Tokenomics
    // ════════════════════════════════════════════
    //  VotingEscrow and BuyAndBurn must be compiled.
    //  vm.getCode will revert if artifacts are missing.

    function _deployTokenomics(Deployment memory d) internal {
        d.votingEscrow = _deploy(
            "VotingEscrow.sol:VotingEscrow",
            abi.encode(d.fblk)
        );

        d.feeDistributor = _deploy(
            "FeeDistributor.sol:FeeDistributor",
            abi.encode(d.votingEscrow, d.factory, WETH9, d.swapRouter)
        );

        d.buyAndBurn = _deploy(
            "BuyAndBurn.sol:BuyAndBurn",
            abi.encode(d.fblk, d.swapRouter, WETH9)
        );
    }

    // ════════════════════════════════════════════
    //  STEP 8 & 9 — Wire + Ownership
    // ════════════════════════════════════════════

    function _wireContracts(Deployment memory d, address deployer) internal {
        IFactory(d.factory).setTreasury(deployer);
        IFactory(d.factory).setFeeCollector(d.feeDistributor);

        // On testnet: keep deployer as owner
        // On mainnet: factory.setPendingOwner(MULTISIG_ADDRESS)
        IFactory(d.factory).setPendingOwner(deployer);
    }

    // ════════════════════════════════════════════
    //  Deployment Summary
    // ════════════════════════════════════════════

    function _logSummary(Deployment memory d) internal pure {
        console.log("");
        console.log("=============================================");
        console.log("  FREETHEBLOCKS SEPOLIA DEPLOYMENT");
        console.log("=============================================");
        console.log("");
        console.log("--- TEST TOKENS ---");
        console.log("  FTB:               ", d.ftb);
        console.log("  tUSDC:             ", d.tusdc);
        console.log("");
        console.log("--- GOVERNANCE ---");
        console.log("  FBLK Token:        ", d.fblk);
        console.log("  Team Vesting:      ", d.teamVesting);
        console.log("  Investor Vesting:  ", d.investorVesting);
        console.log("");
        console.log("--- V3 CORE ---");
        console.log("  Factory:           ", d.factory);
        console.log("  INIT_CODE_HASH:");
        console.logBytes32(d.poolHash);
        console.log("");
        console.log("--- V3 PERIPHERY ---");
        console.log("  PositionManager:   ", d.positionManager);
        console.log("  SwapRouter:        ", d.swapRouter);
        console.log("  QuoterV2:          ", d.quoter);
        console.log("");
        console.log("--- STAKING ---");
        console.log("  MasterChef:        ", d.masterChef);
        console.log("  Emissions start:    block");
        // Can't concat uint with string in view — logged separately
        console.log(d.startBlock);
        console.log("");
        console.log("--- TOKENOMICS ---");
        console.log("  VotingEscrow:      ", d.votingEscrow);
        console.log("  FeeDistributor:    ", d.feeDistributor);
        console.log("  BuyAndBurn:        ", d.buyAndBurn);
        console.log("");
        console.log("--- FBLK DISTRIBUTION ---");
        console.log("  MasterChef (40%):   40,000,000 FBLK");
        console.log("  Team Vesting (20%): 20,000,000 FBLK");
        console.log("  Investor (10%):     10,000,000 FBLK");
        console.log("  Treasury (25%):     deployer holds");
        console.log("  Community (5%):     deployer holds");
        console.log("");
        console.log("=============================================");
        console.log("  Next: run script/CreatePool.s.sol");
        console.log("=============================================");
    }

    // ──────────── Deploy helper ────────────
    //  Loads compiled bytecode for any solc version via vm.getCode
    //  and deploys using CREATE opcode with optional constructor args.

    function _deploy(string memory artifact, bytes memory args)
        internal
        returns (address addr)
    {
        bytes memory code = vm.getCode(artifact);
        bytes memory initCode = args.length > 0
            ? abi.encodePacked(code, args)
            : code;
        assembly {
            addr := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(addr != address(0), string.concat("Deploy failed: ", artifact));
    }
}
