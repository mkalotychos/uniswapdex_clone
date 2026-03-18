// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

// ──────────── Mock WETH9 ────────────

contract MockWETH {
    string public name     = "Wrapped Ether";
    string public symbol   = "WETH";
    uint8  public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok);
        emit Transfer(msg.sender, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        require(allowance[from][msg.sender] >= amount);
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

// ──────────── Mock FBLK (with burn) ────────────

contract MockFBLK {
    string public name     = "FreeTheBlocks Token";
    string public symbol   = "FBLK";
    uint8  public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalBurned;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        totalBurned += amount;
        emit Transfer(msg.sender, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        require(allowance[from][msg.sender] >= amount);
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// ──────────── Mock ERC20 (for token-based buyback) ────────────

contract MockERC20 {
    string public name;
    string public symbol;
    uint8  public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

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
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        require(allowance[from][msg.sender] >= amount);
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// ──────────── Mock SwapRouter ────────────
// Simulates: consume tokenIn, mint fblk to recipient at a fixed rate

contract MockRouter {
    MockFBLK public fblkToken;
    MockWETH public wethToken;
    uint256  public rate; // fblk per 1e18 weth

    constructor(address _fblk, address payable _weth, uint256 _rate) {
        fblkToken = MockFBLK(_fblk);
        wethToken = MockWETH(_weth);
        rate = _rate;
    }

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
        external payable returns (uint256 amountOut)
    {
        // Pull tokenIn from caller
        MockFBLK(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Calculate output
        amountOut = params.amountIn * rate / 1e18;
        require(amountOut >= params.amountOutMinimum, "SLIPPAGE");

        // Mint FBLK to recipient
        fblkToken.mint(params.recipient, amountOut);
    }
}

// ──────────── Interface for 0.7.6 BuyAndBurn ────────────

interface IBuyAndBurn {
    function fblk() external view returns (address);
    function router() external view returns (address);
    function weth() external view returns (address);
    function owner() external view returns (address);
    function poolFee() external view returns (uint24);
    function minBuyAmount() external view returns (uint256);
    function totalFBLKBurned() external view returns (uint256);
    function totalETHSpent() external view returns (uint256);

    function buyAndBurn(uint256 amountIn, uint256 minFBLKOut) external;
    function buyAndBurnToken(address tokenIn, uint256 amountIn, uint24 swapFee, uint256 minFBLKOut) external;
    function setPoolFee(uint24 _fee) external;
    function setMinBuyAmount(uint256 _min) external;
    function rescueTokens(address token, uint256 amount) external;
    function getStats() external view returns (uint256 burned, uint256 spent, uint256 balance);
}

// ──────────── Tests ────────────

contract BuyAndBurnTest is Test {
    MockFBLK   fblkToken;
    MockWETH   wethToken;
    MockRouter mockRouter;
    MockERC20  tusdc;

    IBuyAndBurn bb;

    address deployer = address(this);
    address keeper   = address(0xBEEF);
    address alice    = address(0xA11CE);

    uint256 constant RATE = 2000 * 1e18; // 2000 FBLK per ETH

    function setUp() public {
        fblkToken  = new MockFBLK();
        wethToken  = new MockWETH();
        tusdc      = new MockERC20("Test USDC", "tUSDC", 6);
        mockRouter = new MockRouter(address(fblkToken), payable(address(wethToken)), RATE);

        bytes memory code = vm.getCode("BuyAndBurn.sol:BuyAndBurn");
        bytes memory initCode = abi.encodePacked(
            code,
            abi.encode(address(fblkToken), address(mockRouter), address(wethToken))
        );
        address bbAddr;
        assembly { bbAddr := create(0, add(initCode, 0x20), mload(initCode)) }
        require(bbAddr != address(0), "BuyAndBurn deploy failed");
        bb = IBuyAndBurn(bbAddr);

        // Fund the contract with ETH
        vm.deal(address(bb), 10 ether);
    }

    // ════════════════════════════════════════
    //  Receive ETH
    // ════════════════════════════════════════

    function test_receivesETH() public {
        uint256 balBefore = address(bb).balance;
        (bool ok,) = address(bb).call{value: 1 ether}("");
        assertTrue(ok, "Should accept ETH");
        assertEq(address(bb).balance, balBefore + 1 ether);
    }

    // ════════════════════════════════════════
    //  buyAndBurn
    // ════════════════════════════════════════

    function test_buyAndBurn() public {
        uint256 ethIn = 1 ether;
        uint256 expectedFBLK = ethIn * RATE / 1e18; // 2000e18

        vm.prank(keeper);
        bb.buyAndBurn(ethIn, 0);

        assertEq(bb.totalFBLKBurned(), expectedFBLK, "Should track burned amount");
        assertEq(bb.totalETHSpent(), ethIn, "Should track ETH spent");
        assertEq(fblkToken.balanceOf(address(bb)), 0, "All FBLK burned, none left");
    }

    function test_buyAndBurn_AnyoneCanCall() public {
        vm.deal(alice, 0);
        vm.prank(alice);
        bb.buyAndBurn(1 ether, 0);

        assertGt(bb.totalFBLKBurned(), 0);
    }

    // ════════════════════════════════════════
    //  Metrics
    // ════════════════════════════════════════

    function test_metricsUpdate() public {
        bb.buyAndBurn(1 ether, 0);
        bb.buyAndBurn(2 ether, 0);

        (uint256 burned, uint256 spent, uint256 balance) = bb.getStats();

        uint256 expectedBurned = (1 ether + 2 ether) * RATE / 1e18;
        assertEq(burned, expectedBurned);
        assertEq(spent, 3 ether);
        assertEq(balance, 7 ether); // started with 10, spent 3
    }

    // ════════════════════════════════════════
    //  buyAndBurnToken (ERC20)
    // ════════════════════════════════════════

    function test_buyAndBurnToken() public {
        uint256 usdcIn = 1000 * 1e6;
        tusdc.mint(keeper, usdcIn);

        vm.startPrank(keeper);
        tusdc.approve(address(bb), usdcIn);
        bb.buyAndBurnToken(address(tusdc), usdcIn, 500, 0);
        vm.stopPrank();

        assertGt(bb.totalFBLKBurned(), 0, "Should burn FBLK");
    }

    function test_buyAndBurnToken_CannotSwapFBLK() public {
        vm.prank(keeper);
        vm.expectRevert("CANNOT_SWAP_FBLK");
        bb.buyAndBurnToken(address(fblkToken), 100, 3000, 0);
    }

    // ════════════════════════════════════════
    //  Admin controls
    // ════════════════════════════════════════

    function test_onlyOwnerCanSetFee() public {
        vm.prank(alice);
        vm.expectRevert("NOT_OWNER");
        bb.setPoolFee(500);
    }

    function test_ownerCanSetFee() public {
        bb.setPoolFee(500);
        assertEq(bb.poolFee(), 500);
    }

    function test_onlyOwnerCanSetMinBuy() public {
        vm.prank(alice);
        vm.expectRevert("NOT_OWNER");
        bb.setMinBuyAmount(1 ether);
    }

    function test_ownerCanSetMinBuy() public {
        bb.setMinBuyAmount(0.5 ether);
        assertEq(bb.minBuyAmount(), 0.5 ether);
    }

    // ════════════════════════════════════════
    //  Min buy amount enforcement
    // ════════════════════════════════════════

    function test_minBuyAmountEnforced() public {
        bb.setMinBuyAmount(2 ether);

        vm.expectRevert("BELOW_MIN");
        bb.buyAndBurn(1 ether, 0);
    }

    function test_minBuyAmountPasses() public {
        bb.setMinBuyAmount(1 ether);
        bb.buyAndBurn(1 ether, 0);
        assertGt(bb.totalFBLKBurned(), 0);
    }

    // ════════════════════════════════════════
    //  Insufficient ETH
    // ════════════════════════════════════════

    function test_cannotBuyMoreThanBalance() public {
        vm.expectRevert("INSUFFICIENT_ETH");
        bb.buyAndBurn(100 ether, 0);
    }

    // ════════════════════════════════════════
    //  Rescue tokens
    // ════════════════════════════════════════

    function test_rescueTokens() public {
        tusdc.mint(address(bb), 5000 * 1e6);

        uint256 before = tusdc.balanceOf(deployer);
        bb.rescueTokens(address(tusdc), 5000 * 1e6);
        assertEq(tusdc.balanceOf(deployer), before + 5000 * 1e6);
    }

    function test_cannotRescueFBLK() public {
        vm.expectRevert("CANNOT_RESCUE_FBLK");
        bb.rescueTokens(address(fblkToken), 100);
    }

    function test_onlyOwnerCanRescue() public {
        vm.prank(alice);
        vm.expectRevert("NOT_OWNER");
        bb.rescueTokens(address(tusdc), 100);
    }
}
