// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin-v3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-v3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin-v3/contracts/math/SafeMath.sol";

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

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IFBLK {
    function burn(uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

/// @title BuyAndBurn — buys FBLK with protocol fees and burns it
contract BuyAndBurn {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IFBLK       public immutable fblk;
    ISwapRouter public immutable router;
    IWETH9      public immutable weth;

    address public owner;
    uint24  public poolFee      = 3000;
    uint256 public minBuyAmount = 0;
    uint256 public totalFBLKBurned;
    uint256 public totalETHSpent;

    event BuyAndBurned(uint256 ethSpent, uint256 fblkBurned, uint256 timestamp);
    event MinBuyAmountUpdated(uint256 newMin);
    event PoolFeeUpdated(uint24 newFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    constructor(address _fblk, address _router, address _weth) {
        require(_fblk   != address(0), "ZERO_FBLK");
        require(_router != address(0), "ZERO_ROUTER");
        require(_weth   != address(0), "ZERO_WETH");
        fblk   = IFBLK(_fblk);
        router = ISwapRouter(_router);
        weth   = IWETH9(_weth);
        owner  = msg.sender;
    }

    receive() external payable {}

    // ──────────── Core: buy FBLK with ETH and burn ────────────

    function buyAndBurn(uint256 amountIn, uint256 minFBLKOut) external {
        require(amountIn <= address(this).balance, "INSUFFICIENT_ETH");
        require(amountIn >= minBuyAmount, "BELOW_MIN");

        weth.deposit{value: amountIn}();
        weth.approve(address(router), amountIn);

        uint256 fblkBefore = fblk.balanceOf(address(this));

        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn:           address(weth),
                tokenOut:          address(fblk),
                fee:               poolFee,
                recipient:         address(this),
                deadline:          block.timestamp + 300,
                amountIn:          amountIn,
                amountOutMinimum:  minFBLKOut,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 fblkReceived = fblk.balanceOf(address(this)).sub(fblkBefore);
        require(fblkReceived > 0, "NO_FBLK_RECEIVED");

        fblk.burn(fblkReceived);

        totalFBLKBurned = totalFBLKBurned.add(fblkReceived);
        totalETHSpent   = totalETHSpent.add(amountIn);

        emit BuyAndBurned(amountIn, fblkReceived, block.timestamp);
    }

    // ──────────── Buy FBLK with any ERC20 token ────────────

    function buyAndBurnToken(
        address tokenIn,
        uint256 amountIn,
        uint24  swapFee,
        uint256 minFBLKOut
    ) external {
        require(amountIn > 0, "ZERO_AMOUNT");
        require(tokenIn != address(fblk), "CANNOT_SWAP_FBLK");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // OZ v3 safeApprove requires resetting to 0 first
        IERC20(tokenIn).safeApprove(address(router), 0);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        uint256 fblkBefore = fblk.balanceOf(address(this));

        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn:           tokenIn,
                tokenOut:          address(fblk),
                fee:               swapFee,
                recipient:         address(this),
                deadline:          block.timestamp + 300,
                amountIn:          amountIn,
                amountOutMinimum:  minFBLKOut,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 fblkReceived = fblk.balanceOf(address(this)).sub(fblkBefore);
        require(fblkReceived > 0, "NO_FBLK_RECEIVED");

        fblk.burn(fblkReceived);

        totalFBLKBurned = totalFBLKBurned.add(fblkReceived);

        emit BuyAndBurned(0, fblkReceived, block.timestamp);
    }

    // ──────────── Admin ────────────

    function setPoolFee(uint24 _fee) external onlyOwner {
        poolFee = _fee;
        emit PoolFeeUpdated(_fee);
    }

    function setMinBuyAmount(uint256 _min) external onlyOwner {
        minBuyAmount = _min;
        emit MinBuyAmountUpdated(_min);
    }

    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(fblk), "CANNOT_RESCUE_FBLK");
        IERC20(token).safeTransfer(owner, amount);
    }

    // ──────────── View ────────────

    function getStats()
        external
        view
        returns (uint256 burned, uint256 spent, uint256 balance)
    {
        burned  = totalFBLKBurned;
        spent   = totalETHSpent;
        balance = address(this).balance;
    }
}
