// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin-v3/contracts/math/SafeMath.sol";
import "@openzeppelin-v3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-v3/contracts/token/ERC20/SafeERC20.sol";

/// @dev Minimal ERC721 interface — only the calls MasterChef needs.
interface IERC721Minimal {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

/// @dev Read V3 position data from the NonfungiblePositionManager.
interface INonfungiblePositionManager {
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint256 tokensOwed0,
            uint256 tokensOwed1
        );
}

/// @title FreeTheBlocks MasterChef — LP Staking Rewards
/// @notice Accepts Uniswap V3 LP NFTs and distributes FBLK governance tokens
///         to stakers proportional to their liquidity contribution.
contract MasterChef {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ──────────── Data Structures ────────────

    struct PoolInfo {
        address token0;
        address token1;
        uint24  fee;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accFblkPerLiquidity; // accumulated FBLK per unit of liquidity × ACC_PRECISION
        uint256 totalLiquidity;
    }

    struct StakeInfo {
        uint256 tokenId;
        uint128 liquidity;
        uint256 rewardDebt;
        address owner;
        uint256 poolId;
    }

    // ──────────── Immutables & State ────────────

    IERC20 public immutable fblk;
    address public immutable nftManager;
    address public owner;

    uint256 public constant INITIAL_EMISSION = 10 * 1e18;  // 10 FBLK / block
    uint256 public constant MINIMUM_EMISSION = 1 * 1e18;   //  1 FBLK / block floor
    uint256 public constant HALVING_PERIOD   = 2_628_000;   // ~1 year at 12 s blocks
    uint256 public constant ACC_PRECISION    = 1e12;

    uint256 public startBlock;
    uint256 public totalAllocPoint;

    PoolInfo[] public poolInfo;
    mapping(bytes32 => uint256) internal _poolIdPlusOne; // key → pid + 1 (0 = unset)
    mapping(uint256 => StakeInfo) public stakeInfo;      // tokenId → stake

    // ──────────── Events ────────────

    event PoolAdded(uint256 indexed pid, address token0, address token1, uint24 fee, uint256 allocPoint);
    event Deposit(address indexed user, uint256 indexed tokenId, uint256 liquidity);
    event Withdraw(address indexed user, uint256 indexed tokenId, uint256 liquidity);
    event Harvest(address indexed user, uint256 indexed tokenId, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed tokenId, uint256 liquidity);

    // ──────────── Constructor ────────────

    constructor(address _fblk, address _nftManager, uint256 _startBlock) {
        require(_fblk != address(0), "ZERO_FBLK");
        require(_nftManager != address(0), "ZERO_NFT");
        fblk = IERC20(_fblk);
        nftManager = _nftManager;
        owner = msg.sender;
        startBlock = _startBlock;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    // ──────────── View Functions ────────────

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Current FBLK emission rate, accounting for halvings.
    function getFblkPerBlock() public view returns (uint256) {
        if (block.number < startBlock) return 0;
        uint256 halvings = block.number.sub(startBlock).div(HALVING_PERIOD);
        if (halvings >= 10) return MINIMUM_EMISSION;
        uint256 emission = INITIAL_EMISSION >> halvings;
        return emission < MINIMUM_EMISSION ? MINIMUM_EMISSION : emission;
    }

    function getPoolKey(address token0, address token1, uint24 fee)
        public pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(token0, token1, fee));
    }

    function getPoolId(address token0, address token1, uint24 fee)
        public view returns (uint256)
    {
        bytes32 key = getPoolKey(token0, token1, fee);
        uint256 pp1 = _poolIdPlusOne[key];
        require(pp1 > 0, "POOL_NOT_FOUND");
        return pp1 - 1;
    }

    /// @notice Claimable FBLK for a staked position.
    function pendingFblk(uint256 tokenId) external view returns (uint256) {
        StakeInfo memory stake = stakeInfo[tokenId];
        if (stake.owner == address(0)) return 0;

        PoolInfo memory pool = poolInfo[stake.poolId];
        uint256 acc = pool.accFblkPerLiquidity;

        if (block.number > pool.lastRewardBlock && pool.totalLiquidity > 0) {
            uint256 blocks = block.number.sub(pool.lastRewardBlock);
            uint256 reward = blocks
                .mul(getFblkPerBlock())
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            acc = acc.add(reward.mul(ACC_PRECISION).div(pool.totalLiquidity));
        }

        return uint256(stake.liquidity).mul(acc).div(ACC_PRECISION).sub(stake.rewardDebt);
    }

    // ──────────── Admin ────────────

    /// @notice Register a new incentivised pool.
    function add(
        address token0,
        address token1,
        uint24 fee,
        uint256 allocPoint
    ) external onlyOwner {
        if (token0 > token1) (token0, token1) = (token1, token0);

        bytes32 key = getPoolKey(token0, token1, fee);
        require(_poolIdPlusOne[key] == 0, "POOL_EXISTS");

        massUpdatePools();

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(allocPoint);

        poolInfo.push(PoolInfo({
            token0: token0,
            token1: token1,
            fee: fee,
            allocPoint: allocPoint,
            lastRewardBlock: lastRewardBlock,
            accFblkPerLiquidity: 0,
            totalLiquidity: 0
        }));

        _poolIdPlusOne[key] = poolInfo.length; // pid + 1
        emit PoolAdded(poolInfo.length - 1, token0, token1, fee, allocPoint);
    }

    /// @notice Update allocPoint for an existing pool.
    function set(uint256 pid, uint256 allocPoint) external onlyOwner {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[pid].allocPoint).add(allocPoint);
        poolInfo[pid].allocPoint = allocPoint;
    }

    // ──────────── Pool Updates ────────────

    function massUpdatePools() public {
        uint256 len = poolInfo.length;
        for (uint256 i = 0; i < len; i++) {
            updatePool(i);
        }
    }

    function updatePool(uint256 pid) public {
        PoolInfo storage pool = poolInfo[pid];
        if (block.number <= pool.lastRewardBlock) return;

        if (pool.totalLiquidity == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 blocks = block.number.sub(pool.lastRewardBlock);
        uint256 reward = blocks
            .mul(getFblkPerBlock())
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        pool.accFblkPerLiquidity = pool.accFblkPerLiquidity.add(
            reward.mul(ACC_PRECISION).div(pool.totalLiquidity)
        );
        pool.lastRewardBlock = block.number;
    }

    // ──────────── User Actions ────────────

    /// @notice Stake a V3 LP NFT. Caller must have approved this contract.
    function deposit(uint256 tokenId) external {
        (
            , ,
            address token0,
            address token1,
            uint24 fee,
            , ,
            uint128 liquidity,
            , , ,
        ) = INonfungiblePositionManager(nftManager).positions(tokenId);

        require(liquidity > 0, "ZERO_LIQUIDITY");

        bytes32 key = getPoolKey(token0, token1, fee);
        uint256 pp1 = _poolIdPlusOne[key];
        require(pp1 > 0, "POOL_NOT_FOUND");
        uint256 pid = pp1 - 1;

        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];

        IERC721Minimal(nftManager).transferFrom(msg.sender, address(this), tokenId);

        pool.totalLiquidity = pool.totalLiquidity.add(uint256(liquidity));

        stakeInfo[tokenId] = StakeInfo({
            tokenId: tokenId,
            liquidity: liquidity,
            rewardDebt: uint256(liquidity).mul(pool.accFblkPerLiquidity).div(ACC_PRECISION),
            owner: msg.sender,
            poolId: pid
        });

        emit Deposit(msg.sender, tokenId, uint256(liquidity));
    }

    /// @notice Unstake NFT and claim pending rewards.
    function withdraw(uint256 tokenId) external {
        StakeInfo memory stake = stakeInfo[tokenId];
        require(stake.owner == msg.sender, "NOT_STAKE_OWNER");

        updatePool(stake.poolId);
        PoolInfo storage pool = poolInfo[stake.poolId];

        uint256 pending = uint256(stake.liquidity)
            .mul(pool.accFblkPerLiquidity)
            .div(ACC_PRECISION)
            .sub(stake.rewardDebt);

        if (pending > 0) {
            _safeFblkTransfer(msg.sender, pending);
            emit Harvest(msg.sender, tokenId, pending);
        }

        pool.totalLiquidity = pool.totalLiquidity.sub(uint256(stake.liquidity));
        delete stakeInfo[tokenId];

        IERC721Minimal(nftManager).safeTransferFrom(address(this), msg.sender, tokenId);
        emit Withdraw(msg.sender, tokenId, uint256(stake.liquidity));
    }

    /// @notice Claim pending FBLK rewards without unstaking.
    function harvest(uint256 tokenId) external {
        StakeInfo storage stake = stakeInfo[tokenId];
        require(stake.owner == msg.sender, "NOT_STAKE_OWNER");

        updatePool(stake.poolId);
        PoolInfo storage pool = poolInfo[stake.poolId];

        uint256 pending = uint256(stake.liquidity)
            .mul(pool.accFblkPerLiquidity)
            .div(ACC_PRECISION)
            .sub(stake.rewardDebt);

        require(pending > 0, "NOTHING_TO_HARVEST");

        stake.rewardDebt = uint256(stake.liquidity)
            .mul(pool.accFblkPerLiquidity)
            .div(ACC_PRECISION);

        _safeFblkTransfer(msg.sender, pending);
        emit Harvest(msg.sender, tokenId, pending);
    }

    /// @notice Emergency: return NFT with no reward calculation.
    function emergencyWithdraw(uint256 tokenId) external {
        StakeInfo memory stake = stakeInfo[tokenId];
        require(stake.owner == msg.sender, "NOT_STAKE_OWNER");

        PoolInfo storage pool = poolInfo[stake.poolId];
        pool.totalLiquidity = pool.totalLiquidity.sub(uint256(stake.liquidity));
        delete stakeInfo[tokenId];

        IERC721Minimal(nftManager).safeTransferFrom(address(this), msg.sender, tokenId);
        emit EmergencyWithdraw(msg.sender, tokenId, uint256(stake.liquidity));
    }

    // ──────────── Internal ────────────

    /// @dev Transfer FBLK, capped at contract balance (avoids revert if underfunded).
    function _safeFblkTransfer(address to, uint256 amount) internal {
        uint256 bal = fblk.balanceOf(address(this));
        fblk.safeTransfer(to, amount > bal ? bal : amount);
    }

    /// @dev Accept V3 LP NFTs sent via safeTransferFrom.
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}
