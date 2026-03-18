// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin-v3/contracts/math/SafeMath.sol";
import "@openzeppelin-v3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-v3/contracts/token/ERC20/SafeERC20.sol";

// ──────────── Minimal Interfaces ────────────

interface IVotingEscrow {
    /// @notice veFBLK balance of `user` at a specific `timestamp`.
    function balanceOfAt(address user, uint256 timestamp) external view returns (uint256);
    /// @notice Total veFBLK supply at a specific `timestamp`.
    function totalSupplyAt(uint256 timestamp) external view returns (uint256);
}

interface IFeePool {
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface ISwapRouter {
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
    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut);
}

// ──────────────────────────────────────────────

/// @title FreeTheBlocks Fee Distributor
/// @notice Collects protocol fees from all DEX pools, converts to a single
///         fee token (e.g. WETH), and distributes weekly to veFBLK holders
///         proportional to their voting-escrow balance at each epoch's start.
contract FeeDistributor {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ──────────── Immutables ────────────

    IVotingEscrow public immutable veToken;
    address       public immutable factory;
    IERC20        public immutable feeToken;  // all fees converted to this (e.g. WETH)
    ISwapRouter   public immutable router;

    // ──────────── State ────────────

    address public owner;

    uint256 public constant EPOCH_DURATION = 7 days;

    uint256 public currentEpoch;
    uint256 public currentEpochFees; // feeToken accumulated for the open epoch

    // Per-epoch data (separate mappings because structs can't hold mappings)
    mapping(uint256 => uint256) public epochStartTime;
    mapping(uint256 => uint256) public epochTotalVeFblk;
    mapping(uint256 => uint256) public epochTotalFees;
    mapping(uint256 => bool)    public epochFinalized;
    mapping(uint256 => mapping(address => bool)) public epochClaimed;

    // Registered pools
    address[] public pools;
    mapping(address => bool) public isPool;

    // ──────────── Events ────────────

    event FeesCollected(address indexed pool, uint256 amount0, uint256 amount1);
    event FeesConverted(address indexed tokenIn, uint256 amountIn, uint256 amountOut);
    event EpochCheckpointed(uint256 indexed epoch, uint256 totalVeFblk, uint256 totalFees);
    event FeesClaimed(address indexed user, uint256 indexed epoch, uint256 amount);
    event PoolAdded(address indexed pool);

    // ──────────── Constructor ────────────

    constructor(
        address _veToken,
        address _factory,
        address _feeToken,
        address _router
    ) {
        require(_veToken  != address(0), "ZERO_VE");
        require(_factory  != address(0), "ZERO_FACTORY");
        require(_feeToken != address(0), "ZERO_FEE_TOKEN");
        require(_router   != address(0), "ZERO_ROUTER");

        veToken  = IVotingEscrow(_veToken);
        factory  = _factory;
        feeToken = IERC20(_feeToken);
        router   = ISwapRouter(_router);
        owner    = msg.sender;

        epochStartTime[0] = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    // ──────────── Pool Management ────────────

    function addPool(address pool) external onlyOwner {
        require(!isPool[pool], "ALREADY_ADDED");
        pools.push(pool);
        isPool[pool] = true;
        emit PoolAdded(pool);
    }

    function poolCount() external view returns (uint256) {
        return pools.length;
    }

    // ──────────── Fee Collection (permissionless) ────────────

    /// @notice Pull protocol fees from a single pool.
    ///         Fees denominated in the feeToken are added to the current
    ///         epoch bucket immediately; other tokens stay in the contract
    ///         until someone calls `convertFees`.
    function collectFromPool(address pool) public {
        require(isPool[pool], "NOT_REGISTERED");

        IFeePool fp = IFeePool(pool);
        (uint128 a0, uint128 a1) = fp.collectProtocol(
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        address t0 = fp.token0();
        address t1 = fp.token1();

        if (t0 == address(feeToken)) {
            currentEpochFees = currentEpochFees.add(uint256(a0));
        }
        if (t1 == address(feeToken)) {
            currentEpochFees = currentEpochFees.add(uint256(a1));
        }

        emit FeesCollected(pool, uint256(a0), uint256(a1));
    }

    /// @notice Collect from every registered pool. Gas-heavy — keeper bots.
    function collectFromAllPools() external {
        uint256 len = pools.length;
        for (uint256 i = 0; i < len; i++) {
            collectFromPool(pools[i]);
        }
    }

    // ──────────── Fee Conversion (permissionless) ────────────

    /// @notice Swap a non-feeToken balance into feeToken via the DEX router.
    ///         Proceeds are added to the current epoch's fee bucket.
    function convertFees(
        address tokenIn,
        uint256 amountIn,
        uint24  poolFee,
        uint256 amountOutMinimum
    ) external {
        require(tokenIn != address(feeToken), "ALREADY_FEE_TOKEN");
        require(amountIn > 0, "ZERO_AMOUNT");

        IERC20(tokenIn).safeApprove(address(router), 0);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        uint256 amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn:           tokenIn,
                tokenOut:          address(feeToken),
                fee:               poolFee,
                recipient:         address(this),
                deadline:          block.timestamp,
                amountIn:          amountIn,
                amountOutMinimum:  amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );

        currentEpochFees = currentEpochFees.add(amountOut);
        emit FeesConverted(tokenIn, amountIn, amountOut);
    }

    // ──────────── Epoch Management (permissionless) ────────────

    /// @notice Close the current epoch and open the next one.
    ///         Can only be called once EPOCH_DURATION has elapsed.
    function checkpointEpoch() external {
        uint256 epoch = currentEpoch;
        uint256 start = epochStartTime[epoch];
        require(block.timestamp >= start.add(EPOCH_DURATION), "EPOCH_NOT_ENDED");

        uint256 totalVe = veToken.totalSupplyAt(start);

        epochTotalVeFblk[epoch] = totalVe;
        epochTotalFees[epoch]   = currentEpochFees;
        epochFinalized[epoch]   = true;

        emit EpochCheckpointed(epoch, totalVe, currentEpochFees);

        uint256 next = epoch.add(1);
        currentEpoch        = next;
        currentEpochFees    = 0;
        epochStartTime[next] = block.timestamp;
    }

    // ──────────── Claims ────────────

    /// @notice Calculate a user's unclaimed share for a finalized epoch.
    function claimable(address user, uint256 epoch) public view returns (uint256) {
        if (!epochFinalized[epoch])       return 0;
        if (epochClaimed[epoch][user])    return 0;

        uint256 totalVe = epochTotalVeFblk[epoch];
        if (totalVe == 0) return 0;

        uint256 userVe = veToken.balanceOfAt(user, epochStartTime[epoch]);
        if (userVe == 0) return 0;

        return epochTotalFees[epoch].mul(userVe).div(totalVe);
    }

    /// @notice Claim fee-token share for a single epoch.
    function claim(address user, uint256 epoch) public {
        require(epochFinalized[epoch],        "NOT_FINALIZED");
        require(!epochClaimed[epoch][user],   "ALREADY_CLAIMED");

        uint256 amount = claimable(user, epoch);
        epochClaimed[epoch][user] = true;

        if (amount > 0) {
            feeToken.safeTransfer(user, amount);
            emit FeesClaimed(user, epoch, amount);
        }
    }

    /// @notice Claim all finalized, unclaimed epochs in one call.
    function claimAll(address user) external {
        uint256 epoch = currentEpoch;
        for (uint256 i = 0; i < epoch; i++) {
            if (epochFinalized[i] && !epochClaimed[i][user]) {
                claim(user, i);
            }
        }
    }
}
