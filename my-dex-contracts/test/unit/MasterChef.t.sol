// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

// ──────────── Interfaces for 0.7.6 MasterChef ────────────

interface IMasterChef {
    function owner() external view returns (address);
    function fblk() external view returns (address);
    function nftManager() external view returns (address);
    function startBlock() external view returns (uint256);
    function totalAllocPoint() external view returns (uint256);

    function poolLength() external view returns (uint256);
    function getFblkPerBlock() external view returns (uint256);
    function getPoolKey(address, address, uint24) external pure returns (bytes32);
    function getPoolId(address, address, uint24) external view returns (uint256);
    function pendingFblk(uint256 tokenId) external view returns (uint256);

    function poolInfo(uint256)
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accFblkPerLiquidity,
            uint256 totalLiquidity
        );

    function stakeInfo(uint256)
        external
        view
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 rewardDebt,
            address stakeOwner,
            uint256 poolId
        );

    function add(address, address, uint24, uint256) external;
    function set(uint256, uint256) external;
    function deposit(uint256 tokenId) external;
    function withdraw(uint256 tokenId) external;
    function harvest(uint256 tokenId) external;
    function emergencyWithdraw(uint256 tokenId) external;
    function updatePool(uint256) external;
    function massUpdatePools() external;
}

// ──────────── Mock ERC20 (FBLK stand-in) ────────────

contract MockFBLK {
    string public name = "Mock FBLK";
    string public symbol = "FBLK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// ──────────── Mock NFT Position Manager ────────────

contract MockNFTManager {
    struct Position {
        address token0;
        address token1;
        uint24 fee;
        uint128 liquidity;
    }

    mapping(uint256 => Position) internal _pos;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public getApproved;
    uint256 public nextTokenId = 1;

    function mintPosition(
        address to,
        address token0,
        address token1,
        uint24 fee,
        uint128 liquidity
    ) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        if (token0 > token1) (token0, token1) = (token1, token0);
        _pos[tokenId] = Position(token0, token1, fee, liquidity);
        ownerOf[tokenId] = to;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96, address, address, address, uint24,
            int24, int24, uint128, uint256, uint256, uint256, uint256
        )
    {
        Position memory p = _pos[tokenId];
        return (0, address(0), p.token0, p.token1, p.fee, 0, 0, p.liquidity, 0, 0, 0, 0);
    }

    function approve(address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == msg.sender, "NOT_NFT_OWNER");
        getApproved[tokenId] = to;
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == from, "NOT_NFT_OWNER");
        require(
            msg.sender == from || getApproved[tokenId] == msg.sender,
            "NOT_APPROVED"
        );
        ownerOf[tokenId] = to;
        delete getApproved[tokenId];
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == from, "NOT_NFT_OWNER");
        require(
            msg.sender == from || getApproved[tokenId] == msg.sender,
            "NOT_APPROVED"
        );
        ownerOf[tokenId] = to;
        delete getApproved[tokenId];
    }
}

// ──────────── Tests ────────────

contract MasterChefTest is Test {
    IMasterChef chef;
    MockFBLK fblkToken;
    MockNFTManager nft;

    address alice;
    address bob;
    address tokenA;
    address tokenB;

    uint256 startBlock;

    uint256 constant INITIAL_EMISSION = 10 * 1e18;
    uint256 constant MINIMUM_EMISSION = 1 * 1e18;
    uint256 constant HALVING_PERIOD   = 2_628_000;
    uint256 constant REWARD_SUPPLY    = 40_000_000 * 1e18;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        tokenA = makeAddr("tokenA");
        tokenB = makeAddr("tokenB");
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);

        fblkToken = new MockFBLK();
        nft = new MockNFTManager();

        startBlock = block.number + 1;

        bytes memory code = vm.getCode("MasterChef.sol:MasterChef");
        bytes memory initCode = abi.encodePacked(
            code,
            abi.encode(address(fblkToken), address(nft), startBlock)
        );
        address chefAddr;
        assembly {
            chefAddr := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(chefAddr != address(0), "chef deploy failed");
        chef = IMasterChef(chefAddr);

        fblkToken.mint(address(chef), REWARD_SUPPLY);

        chef.add(tokenA, tokenB, 3000, 100);
    }

    // ═══════════ Helpers ═══════════

    function _mintAndDeposit(address user, uint128 liquidity) internal returns (uint256 tokenId) {
        tokenId = nft.mintPosition(user, tokenA, tokenB, 3000, liquidity);
        vm.startPrank(user);
        nft.approve(address(chef), tokenId);
        chef.deposit(tokenId);
        vm.stopPrank();
    }

    // ═══════════ Initial State ═══════════

    function test_InitialState() public view {
        assertEq(chef.poolLength(), 1);
        assertEq(chef.totalAllocPoint(), 100);
        assertEq(chef.startBlock(), startBlock);
        assertEq(address(fblkToken), chef.fblk());
    }

    function test_PoolInfoCorrect() public view {
        (address t0, address t1, uint24 fee, uint256 alloc, , , uint256 totalLiq) =
            chef.poolInfo(0);
        assertEq(t0, tokenA);
        assertEq(t1, tokenB);
        assertEq(fee, 3000);
        assertEq(alloc, 100);
        assertEq(totalLiq, 0);
    }

    // ═══════════ Emission / Halving ═══════════

    function test_EmissionBeforeStart() public {
        assertEq(chef.getFblkPerBlock(), 0);
    }

    function test_EmissionAtStart() public {
        vm.roll(startBlock);
        assertEq(chef.getFblkPerBlock(), INITIAL_EMISSION);
    }

    function test_EmissionFirstHalving() public {
        vm.roll(startBlock + HALVING_PERIOD);
        assertEq(chef.getFblkPerBlock(), INITIAL_EMISSION / 2);
    }

    function test_EmissionSecondHalving() public {
        vm.roll(startBlock + 2 * HALVING_PERIOD);
        assertEq(chef.getFblkPerBlock(), INITIAL_EMISSION / 4);
    }

    function test_EmissionFloorAtMinimum() public {
        vm.roll(startBlock + 4 * HALVING_PERIOD);
        uint256 raw = INITIAL_EMISSION >> 4; // 0.625 FBLK — below floor
        assertLt(raw, MINIMUM_EMISSION);
        assertEq(chef.getFblkPerBlock(), MINIMUM_EMISSION);
    }

    function test_EmissionAfterTenHalvings() public {
        vm.roll(startBlock + 10 * HALVING_PERIOD);
        assertEq(chef.getFblkPerBlock(), MINIMUM_EMISSION);
    }

    // ═══════════ Deposit ═══════════

    function test_Deposit() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 5000);

        (, uint128 liq, , address stakeOwner, uint256 pid) = chef.stakeInfo(tokenId);
        assertEq(stakeOwner, alice);
        assertEq(uint256(liq), 5000);
        assertEq(pid, 0);
        assertEq(nft.ownerOf(tokenId), address(chef));

        (, , , , , , uint256 totalLiq) = chef.poolInfo(0);
        assertEq(totalLiq, 5000);
    }

    function test_Deposit_RevertsIfPoolNotFound() public {
        vm.roll(startBlock);
        address rando = makeAddr("rando");
        uint256 tokenId = nft.mintPosition(alice, tokenA, rando, 500, 1000);

        vm.startPrank(alice);
        nft.approve(address(chef), tokenId);
        vm.expectRevert(bytes("POOL_NOT_FOUND"));
        chef.deposit(tokenId);
        vm.stopPrank();
    }

    function test_Deposit_RevertsIfZeroLiquidity() public {
        vm.roll(startBlock);
        uint256 tokenId = nft.mintPosition(alice, tokenA, tokenB, 3000, 0);

        vm.startPrank(alice);
        nft.approve(address(chef), tokenId);
        vm.expectRevert(bytes("ZERO_LIQUIDITY"));
        chef.deposit(tokenId);
        vm.stopPrank();
    }

    // ═══════════ Pending & Harvest ═══════════

    function test_PendingFblk_AccumulatesCorrectly() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 1000);

        vm.roll(startBlock + 10);
        uint256 pending = chef.pendingFblk(tokenId);

        // 10 blocks × 10 FBLK/block × allocPoint(100)/totalAlloc(100) = 100 FBLK
        assertEq(pending, 100 * 1e18);
    }

    function test_Harvest() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 1000);

        vm.roll(startBlock + 10);

        vm.prank(alice);
        chef.harvest(tokenId);

        // 10 blocks of rewards accumulate, then harvest triggers updatePool at block startBlock+10
        // Total = 10 * 10e18 = 100e18
        assertEq(fblkToken.balanceOf(alice), 100 * 1e18);

        assertEq(chef.pendingFblk(tokenId), 0);
    }

    function test_Harvest_RevertsIfNotOwner() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 1000);

        vm.roll(startBlock + 5);

        vm.prank(bob);
        vm.expectRevert(bytes("NOT_STAKE_OWNER"));
        chef.harvest(tokenId);
    }

    function test_Harvest_RevertsIfNothingToHarvest() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 1000);

        // Harvest same block — 0 pending
        vm.prank(alice);
        vm.expectRevert(bytes("NOTHING_TO_HARVEST"));
        chef.harvest(tokenId);
    }

    // ═══════════ Withdraw ═══════════

    function test_Withdraw() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 2000);

        vm.roll(startBlock + 5);

        vm.prank(alice);
        chef.withdraw(tokenId);

        // NFT returned
        assertEq(nft.ownerOf(tokenId), alice);

        // Rewards paid: 5 blocks × 10 FBLK = 50 FBLK
        assertEq(fblkToken.balanceOf(alice), 50 * 1e18);

        // Pool liquidity zeroed
        (, , , , , , uint256 totalLiq) = chef.poolInfo(0);
        assertEq(totalLiq, 0);

        // Stake deleted
        (, , , address stakeOwner, ) = chef.stakeInfo(tokenId);
        assertEq(stakeOwner, address(0));
    }

    function test_Withdraw_RevertsIfNotOwner() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 1000);

        vm.prank(bob);
        vm.expectRevert(bytes("NOT_STAKE_OWNER"));
        chef.withdraw(tokenId);
    }

    // ═══════════ Emergency Withdraw ═══════════

    function test_EmergencyWithdraw() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 3000);

        vm.roll(startBlock + 20);

        // Should have big pending, but emergency skips rewards
        uint256 pendingBefore = chef.pendingFblk(tokenId);
        assertGt(pendingBefore, 0);

        vm.prank(alice);
        chef.emergencyWithdraw(tokenId);

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(fblkToken.balanceOf(alice), 0); // NO rewards

        (, , , , , , uint256 totalLiq) = chef.poolInfo(0);
        assertEq(totalLiq, 0);
    }

    function test_EmergencyWithdraw_RevertsIfNotOwner() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 1000);

        vm.prank(bob);
        vm.expectRevert(bytes("NOT_STAKE_OWNER"));
        chef.emergencyWithdraw(tokenId);
    }

    // ═══════════ Two Users — Proportional Sharing ═══════════

    function test_TwoUsers_ProportionalRewards() public {
        vm.roll(startBlock);

        // Both deposit in the same block so math is clean
        uint256 tidA = _mintAndDeposit(alice, 3000);
        uint256 tidB = _mintAndDeposit(bob, 1000);

        vm.roll(startBlock + 10);

        // Total: 10 blocks × 10 FBLK = 100 FBLK
        // Alice: 3000/4000 = 75%  → 75 FBLK
        // Bob:   1000/4000 = 25%  → 25 FBLK
        uint256 pendingA = chef.pendingFblk(tidA);
        uint256 pendingB = chef.pendingFblk(tidB);

        assertEq(pendingA, 75 * 1e18);
        assertEq(pendingB, 25 * 1e18);
    }

    function test_TwoUsers_SequentialDeposits() public {
        vm.roll(startBlock);
        uint256 tidA = _mintAndDeposit(alice, 1000);

        // Alice alone for 5 blocks
        vm.roll(startBlock + 5);
        uint256 tidB = _mintAndDeposit(bob, 1000);

        // Both for 5 more blocks
        vm.roll(startBlock + 10);

        uint256 pendingA = chef.pendingFblk(tidA);
        uint256 pendingB = chef.pendingFblk(tidB);

        // Alice: 5 blocks solo (50 FBLK) + 5 blocks 50% (25 FBLK) = 75 FBLK
        // Bob:   5 blocks 50% (25 FBLK)
        assertEq(pendingA, 75 * 1e18);
        assertEq(pendingB, 25 * 1e18);
    }

    // ═══════════ Multiple Pools ═══════════

    function test_MultiplePools_WeightedRewards() public {
        address tokenC = makeAddr("tokenC");
        if (tokenA > tokenC) (tokenA, tokenC) = (tokenC, tokenA);

        // Pool 0: (tokenA, tokenB, 3000) allocPoint=100  (added in setUp)
        // Pool 1: (tokenA, tokenC, 500) allocPoint=300
        chef.add(tokenA, tokenC, 500, 300);
        // totalAllocPoint = 400

        vm.roll(startBlock);

        // Deposit into pool 0
        uint256 tid0 = nft.mintPosition(alice, tokenA, tokenB, 3000, 1000);
        vm.startPrank(alice);
        nft.approve(address(chef), tid0);
        chef.deposit(tid0);
        vm.stopPrank();

        // Deposit into pool 1
        uint256 tid1 = nft.mintPosition(bob, tokenA, tokenC, 500, 1000);
        vm.startPrank(bob);
        nft.approve(address(chef), tid1);
        chef.deposit(tid1);
        vm.stopPrank();

        vm.roll(startBlock + 10);

        // Pool 0: 100/400 = 25% of 100 FBLK = 25 FBLK
        // Pool 1: 300/400 = 75% of 100 FBLK = 75 FBLK
        uint256 pendingA = chef.pendingFblk(tid0);
        uint256 pendingB = chef.pendingFblk(tid1);

        assertEq(pendingA, 25 * 1e18);
        assertEq(pendingB, 75 * 1e18);
    }

    // ═══════════ Admin ═══════════

    function test_Add_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        chef.add(tokenA, tokenB, 500, 50);
    }

    function test_Add_RevertsIfPoolExists() public {
        vm.expectRevert(bytes("POOL_EXISTS"));
        chef.add(tokenA, tokenB, 3000, 50);
    }

    function test_Add_SortsTokens() public {
        // Pass tokens in reverse order — should still work
        address tX = makeAddr("tX");
        address tY = makeAddr("tY");
        if (tX < tY) (tX, tY) = (tY, tX); // ensure tX > tY
        chef.add(tX, tY, 500, 50);

        (address t0, address t1, , , , , ) = chef.poolInfo(1);
        assertLt(uint160(t0), uint160(t1)); // stored in sorted order
    }

    function test_Set_UpdatesAllocPoint() public {
        chef.set(0, 200);
        (, , , uint256 alloc, , , ) = chef.poolInfo(0);
        assertEq(alloc, 200);
        assertEq(chef.totalAllocPoint(), 200);
    }

    // ═══════════ PendingFblk edge cases ═══════════

    function test_PendingFblk_ZeroForNonExistentStake() public view {
        assertEq(chef.pendingFblk(9999), 0);
    }

    // ═══════════ Halving with active staking ═══════════

    function test_Halving_ReducesRewardsOverTime() public {
        vm.roll(startBlock);
        uint256 tokenId = _mintAndDeposit(alice, 1000);

        // Harvest BEFORE the halving boundary (still at 10 FBLK/block)
        vm.roll(startBlock + 5);
        vm.prank(alice);
        chef.harvest(tokenId);
        uint256 firstHarvest = fblkToken.balanceOf(alice);
        assertEq(firstHarvest, 5 * INITIAL_EMISSION); // 5 blocks × 10 FBLK

        // Roll past halving boundary — getFblkPerBlock now returns 5 FBLK
        // MasterChef uses point-in-time rate: the HALVING_PERIOD blocks since
        // last update are all valued at the current (post-halving) rate.
        vm.roll(startBlock + HALVING_PERIOD + 5);
        uint256 pendingAfterHalving = chef.pendingFblk(tokenId);
        assertEq(pendingAfterHalving, uint256(HALVING_PERIOD) * (INITIAL_EMISSION / 2));

        // Verify emission rate actually halved
        assertEq(chef.getFblkPerBlock(), INITIAL_EMISSION / 2);
    }
}
