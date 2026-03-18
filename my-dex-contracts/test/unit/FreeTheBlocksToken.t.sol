// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

interface IFBLK {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);

    function MAX_SUPPLY() external view returns (uint256);
    function snapshotAdmin() external view returns (address);

    function burn(uint256) external;
    function snapshot() external returns (uint256);
    function setSnapshotAdmin(address) external;

    function balanceOfAt(address, uint256) external view returns (uint256);
    function totalSupplyAt(uint256) external view returns (uint256);

    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external;
    function nonces(address) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract FreeTheBlocksTokenTest is Test {
    IFBLK token;

    address deployer;
    address liquidityMining;
    address treasury;
    address teamVesting;
    address investorVesting;
    address community;
    address alice;
    address bob;

    uint256 constant MAX_SUPPLY = 100_000_000 * 1e18;

    function setUp() public {
        deployer = address(this);
        liquidityMining = makeAddr("liquidityMining");
        treasury = makeAddr("treasury");
        teamVesting = makeAddr("teamVesting");
        investorVesting = makeAddr("investorVesting");
        community = makeAddr("community");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        bytes memory creationCode = vm.getCode("FreeTheBlocksToken.sol:FreeTheBlocksToken");
        bytes memory initCode = abi.encodePacked(
            creationCode,
            abi.encode(liquidityMining, treasury, teamVesting, investorVesting, community)
        );

        address tokenAddr;
        assembly {
            tokenAddr := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(tokenAddr != address(0), "token deploy failed");
        token = IFBLK(tokenAddr);
    }

    // ──────────── Metadata ────────────

    function test_Name() public view {
        assertEq(token.name(), "FreeTheBlocks Token");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "FBLK");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_MaxSupply() public view {
        assertEq(token.MAX_SUPPLY(), MAX_SUPPLY);
    }

    // ──────────── Allocation ────────────

    function test_TotalSupply() public view {
        assertEq(token.totalSupply(), MAX_SUPPLY);
    }

    function test_LiquidityMiningAllocation() public view {
        assertEq(token.balanceOf(liquidityMining), 40_000_000 * 1e18);
    }

    function test_TreasuryAllocation() public view {
        assertEq(token.balanceOf(treasury), 25_000_000 * 1e18);
    }

    function test_TeamVestingAllocation() public view {
        assertEq(token.balanceOf(teamVesting), 20_000_000 * 1e18);
    }

    function test_InvestorVestingAllocation() public view {
        assertEq(token.balanceOf(investorVesting), 10_000_000 * 1e18);
    }

    function test_CommunityAllocation() public view {
        assertEq(token.balanceOf(community), 5_000_000 * 1e18);
    }

    function test_AllocationsAddUp() public view {
        uint256 total = token.balanceOf(liquidityMining)
            + token.balanceOf(treasury)
            + token.balanceOf(teamVesting)
            + token.balanceOf(investorVesting)
            + token.balanceOf(community);
        assertEq(total, MAX_SUPPLY);
    }

    // ──────────── Fixed Supply (no mint) ────────────

    function test_NoMintFunction() public view {
        assertEq(token.totalSupply(), MAX_SUPPLY);
    }

    // ──────────── Burn ────────────

    function test_Burn() public {
        uint256 burnAmount = 1000 * 1e18;
        vm.prank(community);
        token.burn(burnAmount);

        assertEq(token.balanceOf(community), 5_000_000 * 1e18 - burnAmount);
        assertEq(token.totalSupply(), MAX_SUPPLY - burnAmount);
    }

    function test_Burn_ReducesTotalSupply() public {
        vm.prank(treasury);
        token.burn(1_000_000 * 1e18);
        assertEq(token.totalSupply(), MAX_SUPPLY - 1_000_000 * 1e18);
    }

    function test_Burn_RevertsIfExceedsBalance() public {
        vm.prank(community);
        vm.expectRevert();
        token.burn(5_000_001 * 1e18);
    }

    // ──────────── Transfers ────────────

    function test_Transfer() public {
        vm.prank(community);
        token.transfer(alice, 100 * 1e18);
        assertEq(token.balanceOf(alice), 100 * 1e18);
    }

    function test_Approve_And_TransferFrom() public {
        vm.prank(community);
        token.approve(alice, 500 * 1e18);

        vm.prank(alice);
        token.transferFrom(community, bob, 500 * 1e18);
        assertEq(token.balanceOf(bob), 500 * 1e18);
    }

    // ──────────── Snapshot ────────────

    function test_SnapshotAdminIsDeployer() public view {
        assertEq(token.snapshotAdmin(), deployer);
    }

    function test_Snapshot_CreatesId() public {
        uint256 snapId = token.snapshot();
        assertEq(snapId, 1);
    }

    function test_Snapshot_RecordsBalance() public {
        uint256 snapId = token.snapshot();

        vm.prank(community);
        token.transfer(alice, 1000 * 1e18);

        assertEq(token.balanceOfAt(community, snapId), 5_000_000 * 1e18);
        assertEq(token.balanceOfAt(alice, snapId), 0);

        assertEq(token.balanceOf(community), 5_000_000 * 1e18 - 1000 * 1e18);
        assertEq(token.balanceOf(alice), 1000 * 1e18);
    }

    function test_Snapshot_RecordsTotalSupply() public {
        uint256 snapId = token.snapshot();

        vm.prank(community);
        token.burn(1000 * 1e18);

        assertEq(token.totalSupplyAt(snapId), MAX_SUPPLY);
        assertEq(token.totalSupply(), MAX_SUPPLY - 1000 * 1e18);
    }

    function test_Snapshot_MultipleSnapshots() public {
        uint256 snap1 = token.snapshot();

        vm.prank(community);
        token.transfer(alice, 1000 * 1e18);

        uint256 snap2 = token.snapshot();

        vm.prank(alice);
        token.transfer(bob, 500 * 1e18);

        assertEq(token.balanceOfAt(alice, snap1), 0);
        assertEq(token.balanceOfAt(alice, snap2), 1000 * 1e18);
        assertEq(token.balanceOf(alice), 500 * 1e18);
    }

    function test_Snapshot_RevertsIfNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_ADMIN"));
        token.snapshot();
    }

    // ──────────── setSnapshotAdmin ────────────

    function test_SetSnapshotAdmin() public {
        token.setSnapshotAdmin(alice);
        assertEq(token.snapshotAdmin(), alice);
    }

    function test_SetSnapshotAdmin_RevertsIfNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_ADMIN"));
        token.setSnapshotAdmin(bob);
    }

    function test_SetSnapshotAdmin_RevertsIfZero() public {
        vm.expectRevert(bytes("ZERO_ADDRESS"));
        token.setSnapshotAdmin(address(0));
    }

    function test_SetSnapshotAdmin_NewAdminCanSnapshot() public {
        token.setSnapshotAdmin(alice);

        vm.prank(alice);
        uint256 snapId = token.snapshot();
        assertEq(snapId, 1);
    }

    function test_SetSnapshotAdmin_OldAdminCantSnapshot() public {
        token.setSnapshotAdmin(alice);

        vm.expectRevert(bytes("NOT_ADMIN"));
        token.snapshot();
    }

    // ──────────── Permit (EIP-2612) ────────────

    function test_Permit() public {
        uint256 pk = 0xBEEF;
        address signer = vm.addr(pk);

        vm.prank(community);
        token.transfer(signer, 1000 * 1e18);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, alice, 500 * 1e18, 0, deadline)
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        token.permit(signer, alice, 500 * 1e18, deadline, v, r, s);
        assertEq(token.allowance(signer, alice), 500 * 1e18);
        assertEq(token.nonces(signer), 1);
    }

    function test_Permit_RevertsIfExpired() public {
        uint256 pk = 0xBEEF;
        address signer = vm.addr(pk);

        uint256 deadline = block.timestamp - 1;
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, alice, 100 * 1e18, 0, deadline)
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        vm.expectRevert();
        token.permit(signer, alice, 100 * 1e18, deadline, v, r, s);
    }
}
