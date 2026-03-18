// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin-v3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-v3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin-v3/contracts/math/SafeMath.sol";

/// @title VotingEscrow — lock FBLK to receive veFBLK (linearly decaying voting power)
contract VotingEscrow {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable fblk;

    uint256 public constant MAX_LOCK = 4 * 365 * 86400; // 4 years
    uint256 public constant MIN_LOCK = 7 * 86400;       // 1 week
    uint256 public constant WEEK     = 7 * 86400;

    struct LockedBalance {
        uint128 amount;
        uint256 end;
    }

    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
    }

    mapping(address => LockedBalance) public locked;
    mapping(address => Point)         public userPoint;
    uint256 public totalLockedFBLK;

    address[] public lockers;
    mapping(address => bool) private _isLocker;

    event Deposit(address indexed user, uint256 amount, uint256 lockEnd);
    event Withdraw(address indexed user, uint256 amount);
    event LockExtended(address indexed user, uint256 newEnd);

    constructor(address _fblk) {
        require(_fblk != address(0), "ZERO_ADDR");
        fblk = IERC20(_fblk);
    }

    // ──────────── Lock management ────────────

    function createLock(uint256 amount, uint256 duration) external {
        require(amount > 0, "ZERO_AMOUNT");
        require(duration >= MIN_LOCK, "LOCK_TOO_SHORT");
        require(duration <= MAX_LOCK, "LOCK_TOO_LONG");
        require(locked[msg.sender].amount == 0, "EXISTING_LOCK");

        uint256 unlockTime = ((block.timestamp + duration) / WEEK) * WEEK;

        fblk.safeTransferFrom(msg.sender, address(this), amount);

        locked[msg.sender] = LockedBalance({
            amount: uint128(amount),
            end: unlockTime
        });

        _updateUserPoint(msg.sender, amount, unlockTime);
        totalLockedFBLK = totalLockedFBLK.add(amount);

        if (!_isLocker[msg.sender]) {
            lockers.push(msg.sender);
            _isLocker[msg.sender] = true;
        }

        emit Deposit(msg.sender, amount, unlockTime);
    }

    function increaseLockAmount(uint256 additionalAmount) external {
        LockedBalance storage lock = locked[msg.sender];
        require(lock.amount > 0, "NO_LOCK");
        require(lock.end > block.timestamp, "LOCK_EXPIRED");
        require(additionalAmount > 0, "ZERO_AMOUNT");

        fblk.safeTransferFrom(msg.sender, address(this), additionalAmount);

        uint256 newAmount = uint256(lock.amount).add(additionalAmount);
        lock.amount = uint128(newAmount);

        _updateUserPoint(msg.sender, newAmount, lock.end);
        totalLockedFBLK = totalLockedFBLK.add(additionalAmount);

        emit Deposit(msg.sender, additionalAmount, lock.end);
    }

    function extendLock(uint256 newDuration) external {
        LockedBalance storage lock = locked[msg.sender];
        require(lock.amount > 0, "NO_LOCK");
        require(lock.end > block.timestamp, "LOCK_EXPIRED");

        uint256 newEnd = ((block.timestamp + newDuration) / WEEK) * WEEK;
        require(newEnd > lock.end, "MUST_EXTEND");
        require(newEnd <= block.timestamp + MAX_LOCK, "MAX_LOCK_EXCEEDED");

        lock.end = newEnd;
        _updateUserPoint(msg.sender, uint256(lock.amount), newEnd);

        emit LockExtended(msg.sender, newEnd);
    }

    function withdraw() external {
        LockedBalance storage lock = locked[msg.sender];
        require(lock.end <= block.timestamp, "LOCK_NOT_EXPIRED");
        require(lock.amount > 0, "NO_LOCK");

        uint256 amount = uint256(lock.amount);

        lock.amount = 0;
        lock.end = 0;
        userPoint[msg.sender] = Point(0, 0, block.timestamp);
        totalLockedFBLK = totalLockedFBLK.sub(amount);

        fblk.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    // ──────────── View functions ────────────

    function balanceOf(address user) external view returns (uint256) {
        return _balanceOfAt(user, block.timestamp);
    }

    function balanceOfAt(address user, uint256 timestamp) external view returns (uint256) {
        return _balanceOfAt(user, timestamp);
    }

    /// @notice Testnet-simple: iterates all lockers. Production would use global checkpoints.
    function totalSupply() external view returns (uint256) {
        uint256 total;
        for (uint256 i = 0; i < lockers.length; i++) {
            total = total.add(_balanceOfAt(lockers[i], block.timestamp));
        }
        return total;
    }

    /// @notice Testnet-simple: iterates all lockers.
    function totalSupplyAt(uint256 timestamp) external view returns (uint256) {
        uint256 total;
        for (uint256 i = 0; i < lockers.length; i++) {
            total = total.add(_balanceOfAt(lockers[i], timestamp));
        }
        return total;
    }

    function lockerCount() external view returns (uint256) {
        return lockers.length;
    }

    // ──────────── Internal ────────────

    function _updateUserPoint(address user, uint256 amount, uint256 unlockTime) internal {
        int128 slope = int128(amount / MAX_LOCK);
        int128 bias  = slope * int128(unlockTime - block.timestamp);

        userPoint[user] = Point({bias: bias, slope: slope, ts: block.timestamp});
    }

    function _balanceOfAt(address user, uint256 timestamp) internal view returns (uint256) {
        Point memory pt = userPoint[user];
        if (pt.bias == 0) return 0;
        if (locked[user].end <= timestamp) return 0;
        if (timestamp < pt.ts) return 0;

        int128 elapsed = int128(timestamp - pt.ts);
        int128 current = pt.bias - pt.slope * elapsed;

        return current > 0 ? uint256(current) : 0;
    }
}
