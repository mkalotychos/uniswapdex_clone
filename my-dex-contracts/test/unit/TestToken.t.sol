// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

interface IFTB {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function mint(address, uint256) external;
    function MAX_MINT_PER_CALL() external view returns (uint256);
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external;
    function nonces(address) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract TestToken is Test {
    IFTB ftb;
    IFTB tusdc;
    address deployer;
    address alice;
    address bob;

    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        bytes memory ftbCode = vm.getCode("FreeTheBlocksTestToken.sol:FreeTheBlocksTestToken");
        address ftbAddr;
        assembly { ftbAddr := create(0, add(ftbCode, 0x20), mload(ftbCode)) }
        ftb = IFTB(ftbAddr);

        bytes memory usdcCode = vm.getCode("FreeTheBlocksTestUSDC.sol:FreeTheBlocksTestUSDC");
        address usdcAddr;
        assembly { usdcAddr := create(0, add(usdcCode, 0x20), mload(usdcCode)) }
        tusdc = IFTB(usdcAddr);
    }

    // ──────────── FTB basic properties ────────────

    function test_FTB_Name() public view {
        assertEq(ftb.name(), "FreeTheBlocks Test Token");
    }

    function test_FTB_Symbol() public view {
        assertEq(ftb.symbol(), "FTB");
    }

    function test_FTB_Decimals() public view {
        assertEq(ftb.decimals(), 18);
    }

    function test_FTB_InitialSupply() public view {
        assertEq(ftb.totalSupply(), 1_000_000 * 1e18);
        assertEq(ftb.balanceOf(deployer), 1_000_000 * 1e18);
    }

    // ──────────── tUSDC basic properties ────────────

    function test_tUSDC_Name() public view {
        assertEq(tusdc.name(), "FreeTheBlocks Test USDC");
    }

    function test_tUSDC_Symbol() public view {
        assertEq(tusdc.symbol(), "tUSDC");
    }

    function test_tUSDC_Decimals() public view {
        assertEq(tusdc.decimals(), 6);
    }

    function test_tUSDC_InitialSupply() public view {
        assertEq(tusdc.totalSupply(), 1_000_000 * 1e6);
        assertEq(tusdc.balanceOf(deployer), 1_000_000 * 1e6);
    }

    // ──────────── Mint ────────────

    function test_FTB_Mint() public {
        ftb.mint(alice, 5_000 * 1e18);
        assertEq(ftb.balanceOf(alice), 5_000 * 1e18);
    }

    function test_FTB_MintMaxBoundary() public {
        ftb.mint(alice, 10_000 * 1e18);
        assertEq(ftb.balanceOf(alice), 10_000 * 1e18);
    }

    function test_FTB_MintExceedsMax_Reverts() public {
        vm.expectRevert("Max 10000 per mint");
        ftb.mint(alice, 10_001 * 1e18);
    }

    function test_tUSDC_Mint() public {
        tusdc.mint(alice, 50_000 * 1e6);
        assertEq(tusdc.balanceOf(alice), 50_000 * 1e6);
    }

    function test_tUSDC_MintMaxBoundary() public {
        tusdc.mint(alice, 100_000 * 1e6);
        assertEq(tusdc.balanceOf(alice), 100_000 * 1e6);
    }

    function test_tUSDC_MintExceedsMax_Reverts() public {
        vm.expectRevert("Max 100000 per mint");
        tusdc.mint(alice, 100_001 * 1e6);
    }

    function test_AnyoneCanMint() public {
        vm.prank(alice);
        ftb.mint(bob, 1_000 * 1e18);
        assertEq(ftb.balanceOf(bob), 1_000 * 1e18);
    }

    // ──────────── Transfer ────────────

    function test_Transfer() public {
        ftb.transfer(alice, 500 * 1e18);
        assertEq(ftb.balanceOf(alice), 500 * 1e18);
        assertEq(ftb.balanceOf(deployer), 1_000_000 * 1e18 - 500 * 1e18);
    }

    function test_TransferInsufficientBalance_Reverts() public {
        vm.prank(alice);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        ftb.transfer(bob, 1);
    }

    // ──────────── Approval & TransferFrom ────────────

    function test_Approve() public {
        ftb.approve(alice, 1_000 * 1e18);
        assertEq(ftb.allowance(deployer, alice), 1_000 * 1e18);
    }

    function test_TransferFrom() public {
        ftb.approve(alice, 1_000 * 1e18);

        vm.prank(alice);
        ftb.transferFrom(deployer, bob, 500 * 1e18);

        assertEq(ftb.balanceOf(bob), 500 * 1e18);
        assertEq(ftb.allowance(deployer, alice), 500 * 1e18);
    }

    function test_TransferFromExceedsAllowance_Reverts() public {
        ftb.approve(alice, 100 * 1e18);

        vm.prank(alice);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        ftb.transferFrom(deployer, bob, 200 * 1e18);
    }

    // ──────────── Permit (EIP-2612) ────────────

    function test_Permit() public {
        uint256 ownerKey = 0xA11CE;
        address owner = vm.addr(ownerKey);
        address spender = bob;
        uint256 value = 1_000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = ftb.nonces(owner);

        bytes32 domainSeparator = ftb.DOMAIN_SEPARATOR();

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        ftb.permit(owner, spender, value, deadline, v, r, s);

        assertEq(ftb.allowance(owner, spender), value);
        assertEq(ftb.nonces(owner), 1);
    }

    function test_PermitExpired_Reverts() public {
        uint256 ownerKey = 0xA11CE;
        address owner = vm.addr(ownerKey);
        uint256 deadline = block.timestamp - 1;

        bytes32 domainSeparator = ftb.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, bob, 100, ftb.nonces(owner), deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        vm.expectRevert("ERC20Permit: expired deadline");
        ftb.permit(owner, bob, 100, deadline, v, r, s);
    }

    function test_PermitInvalidSignature_Reverts() public {
        uint256 ownerKey = 0xA11CE;
        address owner = vm.addr(ownerKey);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 domainSeparator = ftb.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, bob, 1000, ftb.nonces(owner), deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        uint256 wrongKey = 0xBEEF;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);

        vm.expectRevert("ERC20Permit: invalid signature");
        ftb.permit(owner, bob, 1000, deadline, v, r, s);
    }
}
