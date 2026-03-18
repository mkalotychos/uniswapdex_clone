// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

// ──────────── Interface to the 0.7.6 FeeDistributor ────────────

interface IFeeDistributor {
    function owner() external view returns (address);
    function veToken() external view returns (address);
    function factory() external view returns (address);
    function feeToken() external view returns (address);
    function router() external view returns (address);

    function currentEpoch() external view returns (uint256);
    function currentEpochFees() external view returns (uint256);

    function epochStartTime(uint256) external view returns (uint256);
    function epochTotalVeFblk(uint256) external view returns (uint256);
    function epochTotalFees(uint256) external view returns (uint256);
    function epochFinalized(uint256) external view returns (bool);
    function epochClaimed(uint256, address) external view returns (bool);

    function pools(uint256) external view returns (address);
    function isPool(address) external view returns (bool);
    function poolCount() external view returns (uint256);

    function addPool(address) external;
    function collectFromPool(address) external;
    function collectFromAllPools() external;
    function convertFees(address tokenIn, uint256 amountIn, uint24 poolFee, uint256 amountOutMin) external;
    function checkpointEpoch() external;
    function claimable(address user, uint256 epoch) external view returns (uint256);
    function claim(address user, uint256 epoch) external;
    function claimAll(address user) external;
}

// ──────────── Mock ERC20 ────────────

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

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
        if (msg.sender != from) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// ──────────── Mock Pool ────────────

contract MockPool {
    address public token0;
    address public token1;
    uint256 public fees0;
    uint256 public fees1;

    constructor(address _t0, address _t1) {
        if (uint160(_t0) < uint160(_t1)) {
            token0 = _t0;
            token1 = _t1;
        } else {
            token0 = _t1;
            token1 = _t0;
        }
    }

    function setFees(uint256 _f0, uint256 _f1) external {
        fees0 = _f0;
        fees1 = _f1;
    }

    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 c0, uint128 c1) {
        c0 = uint128(uint256(amount0Requested) > fees0 ? fees0 : uint256(amount0Requested));
        c1 = uint128(uint256(amount1Requested) > fees1 ? fees1 : uint256(amount1Requested));
        fees0 -= c0;
        fees1 -= c1;
        if (c0 > 0) MockERC20(token0).transfer(recipient, c0);
        if (c1 > 0) MockERC20(token1).transfer(recipient, c1);
    }
}

// ──────────── Mock Voting Escrow ────────────

contract MockVotingEscrow {
    mapping(bytes32 => uint256) private _bal;
    mapping(uint256 => uint256) private _supply;

    function setBalanceOfAt(address user, uint256 ts, uint256 amount) external {
        _bal[keccak256(abi.encode(user, ts))] = amount;
    }

    function setTotalSupplyAt(uint256 ts, uint256 amount) external {
        _supply[ts] = amount;
    }

    function balanceOfAt(address user, uint256 ts) external view returns (uint256) {
        return _bal[keccak256(abi.encode(user, ts))];
    }

    function totalSupplyAt(uint256 ts) external view returns (uint256) {
        return _supply[ts];
    }
}

// ──────────── Mock Router (1:1 swap) ────────────

contract MockRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata p)
        external payable returns (uint256)
    {
        MockERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        MockERC20(p.tokenOut).mint(p.recipient, p.amountIn); // 1:1 rate
        return p.amountIn;
    }
}

// ──────────── Tests ────────────

contract FeeDistributorTest is Test {
    IFeeDistributor dist;
    MockERC20 weth;       // feeToken
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockPool poolAB;
    MockVotingEscrow ve;
    MockRouter routerMock;

    address alice;
    address bob;
    address factoryAddr;

    uint256 constant EPOCH = 7 days;
    uint256 epoch0Start;

    function setUp() public {
        alice = makeAddr("alice");
        bob   = makeAddr("bob");
        factoryAddr = makeAddr("factory");

        weth   = new MockERC20("Wrapped ETH", "WETH");
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");

        ve         = new MockVotingEscrow();
        routerMock = new MockRouter();

        // Pool: token0=weth (or tokenA), token1=the other
        poolAB = new MockPool(address(weth), address(tokenA));

        epoch0Start = block.timestamp;

        bytes memory code = vm.getCode("FeeDistributor.sol:FeeDistributor");
        bytes memory init = abi.encodePacked(
            code,
            abi.encode(address(ve), factoryAddr, address(weth), address(routerMock))
        );
        address distAddr;
        assembly { distAddr := create(0, add(init, 0x20), mload(init)) }
        require(distAddr != address(0), "dist deploy failed");
        dist = IFeeDistributor(distAddr);

        dist.addPool(address(poolAB));

        // Set veFBLK balances for epoch 0
        ve.setTotalSupplyAt(epoch0Start, 4000 * 1e18);
        ve.setBalanceOfAt(alice, epoch0Start, 3000 * 1e18);
        ve.setBalanceOfAt(bob,   epoch0Start, 1000 * 1e18);
    }

    // ═══════════ Helpers ═══════════

    function _fundPoolFees(uint256 wethAmount, uint256 tokenAAmount) internal {
        weth.mint(address(poolAB), wethAmount);
        tokenA.mint(address(poolAB), tokenAAmount);
        poolAB.setFees(
            poolAB.token0() == address(weth) ? wethAmount : tokenAAmount,
            poolAB.token1() == address(weth) ? wethAmount : tokenAAmount
        );
    }

    function _fundPoolFeesSimple(uint256 wethFees) internal {
        weth.mint(address(poolAB), wethFees);
        if (poolAB.token0() == address(weth)) {
            poolAB.setFees(wethFees, 0);
        } else {
            poolAB.setFees(0, wethFees);
        }
    }

    // ═══════════ Initial State ═══════════

    function test_InitialState() public view {
        assertEq(dist.currentEpoch(), 0);
        assertEq(dist.currentEpochFees(), 0);
        assertEq(dist.epochStartTime(0), epoch0Start);
        assertEq(dist.poolCount(), 1);
        assertTrue(dist.isPool(address(poolAB)));
    }

    // ═══════════ Pool Management ═══════════

    function test_AddPool() public {
        MockPool p2 = new MockPool(address(weth), address(tokenB));
        dist.addPool(address(p2));
        assertEq(dist.poolCount(), 2);
        assertTrue(dist.isPool(address(p2)));
    }

    function test_AddPool_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        dist.addPool(address(1));
    }

    function test_AddPool_RevertsIfDuplicate() public {
        vm.expectRevert(bytes("ALREADY_ADDED"));
        dist.addPool(address(poolAB));
    }

    // ═══════════ Fee Collection ═══════════

    function test_CollectFromPool_FeeToken() public {
        _fundPoolFeesSimple(100 * 1e18);

        dist.collectFromPool(address(poolAB));

        assertEq(dist.currentEpochFees(), 100 * 1e18);
        assertEq(weth.balanceOf(address(dist)), 100 * 1e18);
    }

    function test_CollectFromPool_NonFeeTokenHeld() public {
        // Both WETH and tokenA as fees
        uint256 wethFees  = 80 * 1e18;
        uint256 tokenAFees = 50 * 1e18;

        weth.mint(address(poolAB), wethFees);
        tokenA.mint(address(poolAB), tokenAFees);

        if (poolAB.token0() == address(weth)) {
            poolAB.setFees(wethFees, tokenAFees);
        } else {
            poolAB.setFees(tokenAFees, wethFees);
        }

        dist.collectFromPool(address(poolAB));

        // Only WETH counted in epoch fees
        assertEq(dist.currentEpochFees(), wethFees);
        // tokenA held in contract (not yet converted)
        assertEq(tokenA.balanceOf(address(dist)), tokenAFees);
    }

    function test_CollectFromPool_RevertsIfNotRegistered() public {
        vm.expectRevert(bytes("NOT_REGISTERED"));
        dist.collectFromPool(address(0xdead));
    }

    function test_CollectFromAllPools() public {
        MockPool p2 = new MockPool(address(weth), address(tokenB));
        dist.addPool(address(p2));

        // Fund both pools
        _fundPoolFeesSimple(60 * 1e18);
        weth.mint(address(p2), 40 * 1e18);
        if (p2.token0() == address(weth)) {
            p2.setFees(40 * 1e18, 0);
        } else {
            p2.setFees(0, 40 * 1e18);
        }

        dist.collectFromAllPools();

        assertEq(dist.currentEpochFees(), 100 * 1e18);
    }

    // ═══════════ Fee Conversion ═══════════

    function test_ConvertFees() public {
        // Simulate: pool gave us 50 tokenA (non-feeToken)
        tokenA.mint(address(dist), 50 * 1e18);

        dist.convertFees(address(tokenA), 50 * 1e18, 3000, 0);

        // Mock router does 1:1 → 50 WETH added to epoch
        assertEq(dist.currentEpochFees(), 50 * 1e18);
        assertEq(weth.balanceOf(address(dist)), 50 * 1e18);
    }

    function test_ConvertFees_RevertsIfFeeToken() public {
        vm.expectRevert(bytes("ALREADY_FEE_TOKEN"));
        dist.convertFees(address(weth), 10 * 1e18, 3000, 0);
    }

    function test_ConvertFees_RevertsIfZero() public {
        vm.expectRevert(bytes("ZERO_AMOUNT"));
        dist.convertFees(address(tokenA), 0, 3000, 0);
    }

    // ═══════════ Epoch Management ═══════════

    function test_CheckpointEpoch() public {
        _fundPoolFeesSimple(200 * 1e18);
        dist.collectFromPool(address(poolAB));

        vm.warp(epoch0Start + EPOCH);
        dist.checkpointEpoch();

        assertTrue(dist.epochFinalized(0));
        assertEq(dist.epochTotalFees(0), 200 * 1e18);
        assertEq(dist.epochTotalVeFblk(0), 4000 * 1e18);
        assertEq(dist.currentEpoch(), 1);
        assertEq(dist.currentEpochFees(), 0);
    }

    function test_CheckpointEpoch_RevertsIfTooEarly() public {
        vm.warp(epoch0Start + EPOCH - 1);
        vm.expectRevert(bytes("EPOCH_NOT_ENDED"));
        dist.checkpointEpoch();
    }

    // ═══════════ Claims — Proportional ═══════════

    function test_ClaimProportional() public {
        _fundPoolFeesSimple(400 * 1e18);
        dist.collectFromPool(address(poolAB));

        vm.warp(epoch0Start + EPOCH);
        dist.checkpointEpoch();

        // Alice: 3000/4000 × 400 = 300 WETH
        // Bob:   1000/4000 × 400 = 100 WETH
        uint256 aliceExpected = 300 * 1e18;
        uint256 bobExpected   = 100 * 1e18;

        assertEq(dist.claimable(alice, 0), aliceExpected);
        assertEq(dist.claimable(bob,   0), bobExpected);

        dist.claim(alice, 0);
        dist.claim(bob,   0);

        assertEq(weth.balanceOf(alice), aliceExpected);
        assertEq(weth.balanceOf(bob),   bobExpected);
    }

    function test_CannotClaimTwice() public {
        _fundPoolFeesSimple(100 * 1e18);
        dist.collectFromPool(address(poolAB));

        vm.warp(epoch0Start + EPOCH);
        dist.checkpointEpoch();

        dist.claim(alice, 0);

        vm.expectRevert(bytes("ALREADY_CLAIMED"));
        dist.claim(alice, 0);
    }

    function test_CannotClaimBeforeFinalize() public {
        vm.expectRevert(bytes("NOT_FINALIZED"));
        dist.claim(alice, 0);
    }

    function test_ClaimableZeroAfterClaim() public {
        _fundPoolFeesSimple(100 * 1e18);
        dist.collectFromPool(address(poolAB));

        vm.warp(epoch0Start + EPOCH);
        dist.checkpointEpoch();

        dist.claim(alice, 0);
        assertEq(dist.claimable(alice, 0), 0);
    }

    // ═══════════ User locked AFTER epoch start ═══════════

    function test_LockedAfterEpochStart_GetsNothing() public {
        address charlie = makeAddr("charlie");
        // charlie has 0 veFBLK at epoch0Start (not set → defaults to 0)

        _fundPoolFeesSimple(100 * 1e18);
        dist.collectFromPool(address(poolAB));

        vm.warp(epoch0Start + EPOCH);
        dist.checkpointEpoch();

        assertEq(dist.claimable(charlie, 0), 0);
    }

    // ═══════════ ClaimAll — Multiple Epochs ═══════════

    function test_ClaimAll() public {
        // ── Epoch 0 ──
        _fundPoolFeesSimple(100 * 1e18);
        dist.collectFromPool(address(poolAB));

        uint256 epoch1Start = epoch0Start + EPOCH;
        vm.warp(epoch1Start);
        dist.checkpointEpoch();

        // ── Epoch 1 ──
        ve.setTotalSupplyAt(epoch1Start, 4000 * 1e18);
        ve.setBalanceOfAt(alice, epoch1Start, 3000 * 1e18);
        ve.setBalanceOfAt(bob,   epoch1Start, 1000 * 1e18);

        _fundPoolFeesSimple(200 * 1e18);
        dist.collectFromPool(address(poolAB));

        uint256 epoch2Start = epoch1Start + EPOCH;
        vm.warp(epoch2Start);
        dist.checkpointEpoch();

        // Alice claims both at once
        dist.claimAll(alice);

        // Epoch 0: 3000/4000 × 100 = 75
        // Epoch 1: 3000/4000 × 200 = 150
        assertEq(weth.balanceOf(alice), 225 * 1e18);

        assertTrue(dist.epochClaimed(0, alice));
        assertTrue(dist.epochClaimed(1, alice));
    }

    // ═══════════ Zero veFBLK supply ═══════════

    function test_ZeroVeSupply_NoClaims() public {
        // Override: no veFBLK at epoch start
        ve.setTotalSupplyAt(epoch0Start, 0);

        _fundPoolFeesSimple(100 * 1e18);
        dist.collectFromPool(address(poolAB));

        vm.warp(epoch0Start + EPOCH);
        dist.checkpointEpoch();

        assertEq(dist.claimable(alice, 0), 0);
    }

    // ═══════════ End-to-end: collect + convert + claim ═══════════

    function test_FullFlow_CollectConvertClaim() public {
        // Pool has 80 WETH + 50 tokenA as fees
        weth.mint(address(poolAB), 80 * 1e18);
        tokenA.mint(address(poolAB), 50 * 1e18);
        if (poolAB.token0() == address(weth)) {
            poolAB.setFees(80 * 1e18, 50 * 1e18);
        } else {
            poolAB.setFees(50 * 1e18, 80 * 1e18);
        }

        dist.collectFromPool(address(poolAB));
        assertEq(dist.currentEpochFees(), 80 * 1e18);

        // Convert 50 tokenA → 50 WETH (1:1 mock)
        dist.convertFees(address(tokenA), 50 * 1e18, 3000, 0);
        assertEq(dist.currentEpochFees(), 130 * 1e18);

        vm.warp(epoch0Start + EPOCH);
        dist.checkpointEpoch();

        // Alice: 3000/4000 × 130 = 97.5
        uint256 aliceClaim = dist.claimable(alice, 0);
        assertEq(aliceClaim, 3000 * 130 * 1e18 / 4000);

        dist.claim(alice, 0);
        assertEq(weth.balanceOf(alice), aliceClaim);
    }
}
