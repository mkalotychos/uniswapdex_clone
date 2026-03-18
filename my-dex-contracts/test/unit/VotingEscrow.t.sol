// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

// ──────────── Mock ERC20 for testing ────────────

contract MockFBLK {
    string public name = "FreeTheBlocks Token";
    string public symbol = "FBLK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "INSUFFICIENT");
        require(allowance[from][msg.sender] >= amount, "ALLOWANCE");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// ──────────── Interface for 0.7.6 VotingEscrow ────────────

interface IVotingEscrow {
    function fblk() external view returns (address);
    function MAX_LOCK() external view returns (uint256);
    function MIN_LOCK() external view returns (uint256);
    function WEEK() external view returns (uint256);
    function locked(address) external view returns (uint128 amount, uint256 end);
    function userPoint(address) external view returns (int128 bias, int128 slope, uint256 ts);
    function totalLockedFBLK() external view returns (uint256);
    function lockerCount() external view returns (uint256);

    function createLock(uint256 amount, uint256 duration) external;
    function increaseLockAmount(uint256 additionalAmount) external;
    function extendLock(uint256 newDuration) external;
    function withdraw() external;

    function balanceOf(address user) external view returns (uint256);
    function balanceOfAt(address user, uint256 timestamp) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalSupplyAt(uint256 timestamp) external view returns (uint256);
}

// ──────────── Tests ────────────

contract VotingEscrowTest is Test {
    MockFBLK fblk;
    IVotingEscrow ve;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    uint256 constant ONE_WEEK   = 7 * 86400;
    uint256 constant ONE_YEAR   = 365 * 86400;
    uint256 constant FOUR_YEARS = 4 * 365 * 86400;

    function setUp() public {
        // Set a clean starting timestamp (avoids week-rounding edge cases at t=0)
        vm.warp(1_700_000_000);

        fblk = new MockFBLK();

        bytes memory code = vm.getCode("VotingEscrow.sol:VotingEscrow");
        bytes memory initCode = abi.encodePacked(code, abi.encode(address(fblk)));
        address veAddr;
        assembly { veAddr := create(0, add(initCode, 0x20), mload(initCode)) }
        require(veAddr != address(0), "VE deploy failed");
        ve = IVotingEscrow(veAddr);

        fblk.mint(alice, 100_000 * 1e18);
        fblk.mint(bob,   100_000 * 1e18);

        vm.prank(alice);
        fblk.approve(veAddr, type(uint256).max);
        vm.prank(bob);
        fblk.approve(veAddr, type(uint256).max);
    }

    // ════════════════════════════════════════
    //  Core lock flow
    // ════════════════════════════════════════

    function test_createLock() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        ve.createLock(amount, ONE_YEAR);

        (uint128 lockedAmt, uint256 lockEnd) = ve.locked(alice);
        assertEq(uint256(lockedAmt), amount);
        assertGt(lockEnd, block.timestamp);

        uint256 bal = ve.balanceOf(alice);
        assertGt(bal, 0, "veFBLK must be > 0");
        assertLt(bal, amount, "1yr lock gives < full veFBLK");

        assertEq(ve.totalLockedFBLK(), amount);
        assertEq(ve.lockerCount(), 1);
    }

    function test_balanceDecays() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        ve.createLock(amount, ONE_YEAR);

        uint256 balStart = ve.balanceOf(alice);

        vm.warp(block.timestamp + ONE_YEAR / 2);
        uint256 balMid = ve.balanceOf(alice);

        assertLt(balMid, balStart, "Balance should decrease over time");
        assertGt(balMid, 0, "Should still be positive mid-lock");
    }

    function test_cannotWithdrawEarly() public {
        vm.prank(alice);
        ve.createLock(1000 * 1e18, ONE_YEAR);

        vm.prank(alice);
        vm.expectRevert("LOCK_NOT_EXPIRED");
        ve.withdraw();
    }

    function test_withdrawAfterExpiry() public {
        uint256 amount = 1000 * 1e18;
        uint256 balBefore = fblk.balanceOf(alice);

        vm.prank(alice);
        ve.createLock(amount, ONE_YEAR);
        assertEq(fblk.balanceOf(alice), balBefore - amount);

        (, uint256 lockEnd) = ve.locked(alice);
        vm.warp(lockEnd + 1);

        assertEq(ve.balanceOf(alice), 0, "veFBLK = 0 after expiry");

        vm.prank(alice);
        ve.withdraw();

        assertEq(fblk.balanceOf(alice), balBefore, "All FBLK returned");
        assertEq(ve.totalLockedFBLK(), 0);
    }

    function test_extendLock() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        ve.createLock(amount, ONE_YEAR);

        uint256 balBefore = ve.balanceOf(alice);
        (, uint256 oldEnd) = ve.locked(alice);

        vm.prank(alice);
        ve.extendLock(3 * ONE_YEAR);

        uint256 balAfter = ve.balanceOf(alice);
        (, uint256 newEnd) = ve.locked(alice);

        assertGt(newEnd, oldEnd, "Lock end extended");
        assertGt(balAfter, balBefore, "veFBLK increased");
    }

    function test_increaseLockAmount() public {
        uint256 amount = 1000 * 1e18;
        uint256 extra  = 500 * 1e18;

        vm.prank(alice);
        ve.createLock(amount, ONE_YEAR);

        uint256 balBefore = ve.balanceOf(alice);

        vm.prank(alice);
        ve.increaseLockAmount(extra);

        uint256 balAfter = ve.balanceOf(alice);
        (uint128 lockedAmt,) = ve.locked(alice);

        assertGt(balAfter, balBefore, "More FBLK = more veFBLK");
        assertEq(uint256(lockedAmt), amount + extra);
        assertEq(ve.totalLockedFBLK(), amount + extra);
    }

    // ════════════════════════════════════════
    //  Balance calculations
    // ════════════════════════════════════════

    function test_maxLock_GivesFullVeFBLK() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        ve.createLock(amount, FOUR_YEARS);

        uint256 bal = ve.balanceOf(alice);
        // Max lock ≈ full amount (within rounding from integer division & week alignment)
        uint256 tolerance = amount / 100; // 1%
        assertGt(bal, amount - tolerance, "Max lock ~ full veFBLK");
    }

    function test_balanceOfAt_PastTimestamp() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        ve.createLock(amount, ONE_YEAR);

        uint256 tLock = block.timestamp;
        uint256 balAtLock = ve.balanceOfAt(alice, tLock);

        vm.warp(block.timestamp + ONE_YEAR / 4);
        uint256 balAtQuarter = ve.balanceOfAt(alice, tLock + ONE_YEAR / 4);

        assertGt(balAtLock, balAtQuarter, "Earlier ts = higher balance");
    }

    function test_balanceOfAt_BeforeLock_ReturnsZero() public {
        uint256 t0 = block.timestamp;

        vm.warp(block.timestamp + ONE_WEEK);

        vm.prank(alice);
        ve.createLock(1000 * 1e18, ONE_YEAR);

        assertEq(ve.balanceOfAt(alice, t0), 0, "No balance before lock created");
    }

    function test_zeroBalanceAfterExpiry() public {
        vm.prank(alice);
        ve.createLock(1000 * 1e18, ONE_WEEK);

        (, uint256 lockEnd) = ve.locked(alice);
        vm.warp(lockEnd + 1);

        assertEq(ve.balanceOf(alice), 0);
        assertEq(ve.totalSupply(), 0);
    }

    // ════════════════════════════════════════
    //  totalSupply with multiple users
    // ════════════════════════════════════════

    function test_totalSupply_MultipleUsers() public {
        vm.prank(alice);
        ve.createLock(1000 * 1e18, ONE_YEAR);

        vm.prank(bob);
        ve.createLock(2000 * 1e18, ONE_YEAR);

        uint256 aliceBal = ve.balanceOf(alice);
        uint256 bobBal   = ve.balanceOf(bob);
        uint256 total    = ve.totalSupply();

        assertEq(total, aliceBal + bobBal, "totalSupply = sum of balances");
    }

    function test_totalSupplyAt() public {
        vm.prank(alice);
        ve.createLock(1000 * 1e18, ONE_YEAR);

        uint256 t0 = block.timestamp;

        vm.warp(block.timestamp + ONE_YEAR / 2);

        uint256 supplyNow  = ve.totalSupply();
        uint256 supplyThen = ve.totalSupplyAt(t0);

        assertGt(supplyThen, supplyNow, "Past supply > current (decay)");
    }

    // ════════════════════════════════════════
    //  Reverts / edge cases
    // ════════════════════════════════════════

    function test_cannotCreateDuplicateLock() public {
        vm.startPrank(alice);
        ve.createLock(1000 * 1e18, ONE_YEAR);

        vm.expectRevert("EXISTING_LOCK");
        ve.createLock(1000 * 1e18, ONE_YEAR);
        vm.stopPrank();
    }

    function test_cannotLockZero() public {
        vm.prank(alice);
        vm.expectRevert("ZERO_AMOUNT");
        ve.createLock(0, ONE_YEAR);
    }

    function test_cannotLockTooShort() public {
        vm.prank(alice);
        vm.expectRevert("LOCK_TOO_SHORT");
        ve.createLock(1000 * 1e18, 1 days);
    }

    function test_cannotLockTooLong() public {
        vm.prank(alice);
        vm.expectRevert("LOCK_TOO_LONG");
        ve.createLock(1000 * 1e18, FOUR_YEARS + ONE_WEEK);
    }

    function test_cannotIncreaseLockWithoutExisting() public {
        vm.prank(alice);
        vm.expectRevert("NO_LOCK");
        ve.increaseLockAmount(1000 * 1e18);
    }

    function test_cannotExtendExpiredLock() public {
        vm.prank(alice);
        ve.createLock(1000 * 1e18, ONE_WEEK);

        (, uint256 lockEnd) = ve.locked(alice);
        vm.warp(lockEnd + 1);

        vm.prank(alice);
        vm.expectRevert("LOCK_EXPIRED");
        ve.extendLock(ONE_YEAR);
    }

    function test_cannotExtendToShorterDuration() public {
        vm.prank(alice);
        ve.createLock(1000 * 1e18, 2 * ONE_YEAR);

        // Try to "extend" to just 1 week from now (shorter than current end)
        vm.prank(alice);
        vm.expectRevert("MUST_EXTEND");
        ve.extendLock(ONE_WEEK);
    }

    function test_cannotWithdrawWithNoLock() public {
        vm.prank(alice);
        vm.expectRevert("NO_LOCK");
        ve.withdraw();
    }

    // ════════════════════════════════════════
    //  Proportional veFBLK
    // ════════════════════════════════════════

    function test_longerLock_MoreVeFBLK() public {
        vm.prank(alice);
        ve.createLock(1000 * 1e18, ONE_YEAR);

        vm.prank(bob);
        ve.createLock(1000 * 1e18, FOUR_YEARS);

        uint256 aliceBal = ve.balanceOf(alice);
        uint256 bobBal   = ve.balanceOf(bob);

        assertGt(bobBal, aliceBal, "4yr lock > 1yr lock for same amount");
        // Bob's balance should be roughly 4× Alice's
        assertGt(bobBal, aliceBal * 3, "~4x more veFBLK for 4x longer lock");
    }
}
