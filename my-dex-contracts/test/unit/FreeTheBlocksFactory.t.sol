// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

interface IFactory {
    function owner() external view returns (address);
    function treasury() external view returns (address);
    function feeCollector() external view returns (address);
    function pendingOwner() external view returns (address);
    function feeAmountTickSpacing(uint24) external view returns (int24);
    function getPool(address, address, uint24) external view returns (address);

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function setOwner(address) external;
    function setTreasury(address) external;
    function setFeeCollector(address) external;
    function setPendingOwner(address) external;
    function acceptOwner() external;
    function enableFeeAmount(uint24, int24) external;
    function defaultProtocolFee() external view returns (uint8);
    function setDefaultProtocolFee(uint8) external;
}

interface IPool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function tickSpacing() external view returns (int24);
    function factory() external view returns (address);
    function initialize(uint160 sqrtPriceX96) external;
}

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

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}

contract FreeTheBlocksFactoryTest is Test {
    IFactory factory;
    address tokenA;
    address tokenB;
    address deployer;
    address alice;
    address bob;
    address treasury;
    address feeDistributor;

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);
    event TreasuryChanged(address indexed oldTreasury, address indexed newTreasury);
    event FeeCollectorChanged(address indexed oldCollector, address indexed newCollector);
    event PendingOwnerSet(address indexed pendingOwner);

    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        treasury = makeAddr("treasury");
        feeDistributor = makeAddr("feeDistributor");

        bytes memory factoryCode = vm.getCode("FreeTheBlocksFactory.sol:FreeTheBlocksFactory");
        address factoryAddr;
        assembly {
            factoryAddr := create(0, add(factoryCode, 0x20), mload(factoryCode))
        }
        require(factoryAddr != address(0), "Factory deployment failed");
        factory = IFactory(factoryAddr);

        MockERC20 mockA = new MockERC20("Token A", "TKNA");
        MockERC20 mockB = new MockERC20("Token B", "TKNB");
        tokenA = address(mockA);
        tokenB = address(mockB);

        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
    }

    // ──────────── Constructor / Initial State ────────────

    function test_OwnerSetOnDeploy() public view {
        assertEq(factory.owner(), deployer);
    }

    function test_TreasurySetToDeployerOnDeploy() public view {
        assertEq(factory.treasury(), deployer);
    }

    function test_FeeCollectorIsZeroOnDeploy() public view {
        assertEq(factory.feeCollector(), address(0));
    }

    function test_PendingOwnerIsZeroOnDeploy() public view {
        assertEq(factory.pendingOwner(), address(0));
    }

    function test_DefaultFeeTiers() public view {
        assertEq(factory.feeAmountTickSpacing(100), 1);
        assertEq(factory.feeAmountTickSpacing(500), 10);
        assertEq(factory.feeAmountTickSpacing(3000), 60);
        assertEq(factory.feeAmountTickSpacing(10000), 200);
    }

    function test_StablecoinFeeTierEnabled() public view {
        assertEq(factory.feeAmountTickSpacing(100), 1);
    }

    // ──────────── setTreasury ────────────

    function test_SetTreasury() public {
        factory.setTreasury(treasury);
        assertEq(factory.treasury(), treasury);
    }

    function test_SetTreasury_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit TreasuryChanged(deployer, treasury);
        factory.setTreasury(treasury);
    }

    function test_SetTreasury_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        factory.setTreasury(treasury);
    }

    function test_SetTreasury_RevertsIfZeroAddress() public {
        vm.expectRevert(bytes("ZERO_ADDRESS"));
        factory.setTreasury(address(0));
    }

    // ──────────── setFeeCollector ────────────

    function test_SetFeeCollector() public {
        factory.setFeeCollector(feeDistributor);
        assertEq(factory.feeCollector(), feeDistributor);
    }

    function test_SetFeeCollector_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit FeeCollectorChanged(address(0), feeDistributor);
        factory.setFeeCollector(feeDistributor);
    }

    function test_SetFeeCollector_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        factory.setFeeCollector(feeDistributor);
    }

    function test_SetFeeCollector_CanSetToZero() public {
        factory.setFeeCollector(feeDistributor);
        factory.setFeeCollector(address(0));
        assertEq(factory.feeCollector(), address(0));
    }

    // ──────────── 2-step ownership transfer ────────────

    function test_SetPendingOwner() public {
        factory.setPendingOwner(alice);
        assertEq(factory.pendingOwner(), alice);
    }

    function test_SetPendingOwner_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit PendingOwnerSet(alice);
        factory.setPendingOwner(alice);
    }

    function test_SetPendingOwner_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        factory.setPendingOwner(bob);
    }

    function test_AcceptOwner() public {
        factory.setPendingOwner(alice);

        vm.prank(alice);
        factory.acceptOwner();

        assertEq(factory.owner(), alice);
        assertEq(factory.pendingOwner(), address(0));
    }

    function test_AcceptOwner_EmitsEvent() public {
        factory.setPendingOwner(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit OwnerChanged(deployer, alice);
        factory.acceptOwner();
    }

    function test_AcceptOwner_RevertsIfNotPending() public {
        factory.setPendingOwner(alice);

        vm.prank(bob);
        vm.expectRevert(bytes("NOT_PENDING"));
        factory.acceptOwner();
    }

    function test_AcceptOwner_RevertsIfNoPendingOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_PENDING"));
        factory.acceptOwner();
    }

    function test_FullOwnershipTransfer_NewOwnerCanAct() public {
        factory.setPendingOwner(alice);
        vm.prank(alice);
        factory.acceptOwner();

        vm.prank(alice);
        factory.setTreasury(bob);
        assertEq(factory.treasury(), bob);
    }

    function test_FullOwnershipTransfer_OldOwnerCantAct() public {
        factory.setPendingOwner(alice);
        vm.prank(alice);
        factory.acceptOwner();

        vm.expectRevert(bytes("NOT_OWNER"));
        factory.setTreasury(bob);
    }

    // ──────────── legacy setOwner (direct) ────────────

    function test_SetOwner_Direct() public {
        factory.setOwner(alice);
        assertEq(factory.owner(), alice);
    }

    function test_SetOwner_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setOwner(bob);
    }

    // ──────────── createPool ────────────

    function test_CreatePool() public {
        address pool = factory.createPool(tokenA, tokenB, 3000);
        assertTrue(pool != address(0));
        assertEq(factory.getPool(tokenA, tokenB, 3000), pool);
        assertEq(factory.getPool(tokenB, tokenA, 3000), pool);
    }

    function test_CreatePool_PoolHasCorrectParams() public {
        address pool = factory.createPool(tokenA, tokenB, 3000);
        IPool p = IPool(pool);
        assertEq(p.token0(), tokenA);
        assertEq(p.token1(), tokenB);
        assertEq(p.fee(), 3000);
        assertEq(p.tickSpacing(), 60);
        assertEq(p.factory(), address(factory));
    }

    function test_CreatePool_AutoEnablesProtocolFeeOnInitialize() public {
        address pool = factory.createPool(tokenA, tokenB, 3000);
        IPool p = IPool(pool);

        // 1:1 price (sqrtPriceX96 = 2^96)
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        p.initialize(sqrtPriceX96);

        (, , , , , uint8 feeProtocol, ) = p.slot0();
        uint8 fee0 = feeProtocol % 16;
        uint8 fee1 = feeProtocol >> 4;
        assertEq(fee0, 6);
        assertEq(fee1, 6);
    }

    function test_DefaultProtocolFeeValue() public view {
        assertEq(factory.defaultProtocolFee(), 6 + (6 << 4));
    }

    function test_SetDefaultProtocolFee() public {
        factory.setDefaultProtocolFee(4 + (4 << 4));
        assertEq(factory.defaultProtocolFee(), 4 + (4 << 4));
    }

    function test_SetDefaultProtocolFee_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        factory.setDefaultProtocolFee(4 + (4 << 4));
    }

    function test_SetDefaultProtocolFee_RevertsIfInvalid() public {
        vm.expectRevert(bytes("INVALID_FEE"));
        factory.setDefaultProtocolFee(3 + (3 << 4));
    }

    function test_SetDefaultProtocolFee_CanDisable() public {
        factory.setDefaultProtocolFee(0);
        assertEq(factory.defaultProtocolFee(), 0);
    }

    function test_CreatePool_RevertsIfDuplicatePair() public {
        factory.createPool(tokenA, tokenB, 3000);
        vm.expectRevert();
        factory.createPool(tokenA, tokenB, 3000);
    }

    function test_CreatePool_RevertsIfSameToken() public {
        vm.expectRevert();
        factory.createPool(tokenA, tokenA, 3000);
    }

    function test_CreatePool_RevertsIfZeroToken() public {
        vm.expectRevert();
        factory.createPool(address(0), tokenB, 3000);
    }

    function test_CreatePool_RevertsIfInvalidFee() public {
        vm.expectRevert();
        factory.createPool(tokenA, tokenB, 999);
    }

    function test_CreatePool_StablecoinTier() public {
        address pool = factory.createPool(tokenA, tokenB, 100);
        IPool p = IPool(pool);
        assertEq(p.fee(), 100);
        assertEq(p.tickSpacing(), 1);
    }

    function test_CreatePool_ReversedOrder() public {
        address pool = factory.createPool(tokenB, tokenA, 3000);
        IPool p = IPool(pool);
        assertEq(p.token0(), tokenA);
        assertEq(p.token1(), tokenB);
    }

    function test_CreatePool_EmitsEvent() public {
        vm.expectEmit(true, true, true, false);
        emit PoolCreated(tokenA, tokenB, 3000, 60, address(0));
        factory.createPool(tokenA, tokenB, 3000);
    }

    // ──────────── enableFeeAmount ────────────

    function test_EnableFeeAmount() public {
        factory.enableFeeAmount(250, 5);
        assertEq(factory.feeAmountTickSpacing(250), 5);
    }

    function test_EnableFeeAmount_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.enableFeeAmount(250, 5);
    }

    function test_EnableFeeAmount_RevertsIfAlreadyEnabled() public {
        vm.expectRevert();
        factory.enableFeeAmount(3000, 60);
    }

    function test_EnableFeeAmount_RevertsIfFeeTooBig() public {
        vm.expectRevert();
        factory.enableFeeAmount(1000000, 10);
    }

    function test_EnableFeeAmount_RevertsIfTickSpacingZero() public {
        vm.expectRevert();
        factory.enableFeeAmount(250, 0);
    }

    function test_EnableFeeAmount_RevertsIfTickSpacingTooBig() public {
        vm.expectRevert();
        factory.enableFeeAmount(250, 16384);
    }
}
