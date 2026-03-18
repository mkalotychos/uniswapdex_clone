// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

interface IVesting {
    function token() external view returns (address);
    function beneficiary() external view returns (address);
    function owner() external view returns (address);
    function treasury() external view returns (address);
    function totalAllocation() external view returns (uint256);
    function claimed() external view returns (uint256);
    function startTime() external view returns (uint256);
    function cliffDuration() external view returns (uint256);
    function vestingDuration() external view returns (uint256);
    function cancelled() external view returns (bool);

    function vestedAmount() external view returns (uint256);
    function claimable() external view returns (uint256);
    function claim() external;
    function cancel() external;
    function setBeneficiary(address) external;
}

interface IMockERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

contract MockToken {
    string public name = "Mock";
    string public symbol = "MCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

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
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract VestingWalletTest is Test {
    IVesting vesting;
    MockToken mockToken;

    address deployer;
    address beneficiary;
    address treasuryAddr;
    address alice;

    uint256 constant ALLOCATION = 20_000_000 * 1e18;
    uint256 constant ONE_YEAR = 365 days;
    uint256 constant FOUR_YEARS = 4 * 365 days;

    uint256 startTime;

    function setUp() public {
        deployer = address(this);
        beneficiary = makeAddr("beneficiary");
        treasuryAddr = makeAddr("treasury");
        alice = makeAddr("alice");

        mockToken = new MockToken();
        mockToken.mint(deployer, ALLOCATION);

        startTime = block.timestamp;

        bytes memory vestingCode = vm.getCode("VestingWallet.sol:VestingWallet");
        bytes memory initCode = abi.encodePacked(
            vestingCode,
            abi.encode(
                address(mockToken),
                beneficiary,
                treasuryAddr,
                startTime,
                ONE_YEAR,
                FOUR_YEARS,
                ALLOCATION
            )
        );

        address vestingAddr;
        assembly {
            vestingAddr := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(vestingAddr != address(0), "vesting deploy failed");
        vesting = IVesting(vestingAddr);

        mockToken.transfer(vestingAddr, ALLOCATION);
    }

    // ──────────── Constructor / Initial State ────────────

    function test_InitialState() public view {
        assertEq(vesting.token(), address(mockToken));
        assertEq(vesting.beneficiary(), beneficiary);
        assertEq(vesting.owner(), deployer);
        assertEq(vesting.treasury(), treasuryAddr);
        assertEq(vesting.totalAllocation(), ALLOCATION);
        assertEq(vesting.claimed(), 0);
        assertEq(vesting.startTime(), startTime);
        assertEq(vesting.cliffDuration(), ONE_YEAR);
        assertEq(vesting.vestingDuration(), FOUR_YEARS);
        assertFalse(vesting.cancelled());
    }

    // ──────────── Before Cliff ────────────

    function test_BeforeCliff_ZeroVested() public view {
        assertEq(vesting.vestedAmount(), 0);
        assertEq(vesting.claimable(), 0);
    }

    function test_BeforeCliff_ClaimReverts() public {
        vm.prank(beneficiary);
        vm.expectRevert(bytes("NOTHING_TO_CLAIM"));
        vesting.claim();
    }

    function test_JustBeforeCliff_ZeroVested() public {
        vm.warp(startTime + ONE_YEAR - 1);
        assertEq(vesting.vestedAmount(), 0);
    }

    // ──────────── At Cliff ────────────

    function test_AtCliff_VestedIs25Percent() public {
        vm.warp(startTime + ONE_YEAR);
        uint256 expected = ALLOCATION * ONE_YEAR / FOUR_YEARS; // 25%
        assertEq(vesting.vestedAmount(), expected);
    }

    function test_AtCliff_CanClaim() public {
        vm.warp(startTime + ONE_YEAR);
        uint256 expected = ALLOCATION * ONE_YEAR / FOUR_YEARS;

        vm.prank(beneficiary);
        vesting.claim();

        assertEq(mockToken.balanceOf(beneficiary), expected);
        assertEq(vesting.claimed(), expected);
    }

    // ──────────── Linear Vesting ────────────

    function test_MidVesting_CorrectAmount() public {
        vm.warp(startTime + 2 * 365 days); // 2 years = 50%
        uint256 expected = ALLOCATION * 2 * 365 days / FOUR_YEARS;
        assertEq(vesting.vestedAmount(), expected);
    }

    function test_ThreeQuarters_CorrectAmount() public {
        vm.warp(startTime + 3 * 365 days); // 3 years = 75%
        uint256 expected = ALLOCATION * 3 * 365 days / FOUR_YEARS;
        assertEq(vesting.vestedAmount(), expected);
    }

    function test_FullyVested() public {
        vm.warp(startTime + FOUR_YEARS);
        assertEq(vesting.vestedAmount(), ALLOCATION);
    }

    function test_AfterFullVesting_CappedAtTotal() public {
        vm.warp(startTime + FOUR_YEARS + 365 days);
        assertEq(vesting.vestedAmount(), ALLOCATION);
    }

    // ──────────── Multiple Claims ────────────

    function test_MultipleClaims() public {
        vm.warp(startTime + ONE_YEAR);
        vm.prank(beneficiary);
        vesting.claim();
        uint256 firstClaim = mockToken.balanceOf(beneficiary);

        vm.warp(startTime + 2 * 365 days);
        vm.prank(beneficiary);
        vesting.claim();
        uint256 totalClaimed = mockToken.balanceOf(beneficiary);

        assertGt(totalClaimed, firstClaim);
        assertEq(vesting.claimed(), totalClaimed);

        uint256 expected2yr = ALLOCATION * 2 * 365 days / FOUR_YEARS;
        assertEq(totalClaimed, expected2yr);
    }

    function test_ClaimAll_AfterFullVesting() public {
        vm.warp(startTime + FOUR_YEARS);
        vm.prank(beneficiary);
        vesting.claim();

        assertEq(mockToken.balanceOf(beneficiary), ALLOCATION);
        assertEq(vesting.claimable(), 0);
    }

    function test_Claim_NothingExtra() public {
        vm.warp(startTime + FOUR_YEARS);
        vm.prank(beneficiary);
        vesting.claim();

        vm.prank(beneficiary);
        vm.expectRevert(bytes("NOTHING_TO_CLAIM"));
        vesting.claim();
    }

    // ──────────── Access Control ────────────

    function test_Claim_RevertsIfNotBeneficiary() public {
        vm.warp(startTime + ONE_YEAR);
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_BENEFICIARY"));
        vesting.claim();
    }

    // ──────────── Cancel ────────────

    function test_Cancel_BeforeCliff() public {
        vesting.cancel();

        assertTrue(vesting.cancelled());
        assertEq(mockToken.balanceOf(beneficiary), 0);
        assertEq(mockToken.balanceOf(treasuryAddr), ALLOCATION);
    }

    function test_Cancel_MidVesting() public {
        vm.warp(startTime + 2 * 365 days);

        vesting.cancel();

        uint256 vested = ALLOCATION * 2 * 365 days / FOUR_YEARS;
        uint256 unvested = ALLOCATION - vested;

        assertEq(mockToken.balanceOf(beneficiary), vested);
        assertEq(mockToken.balanceOf(treasuryAddr), unvested);
        assertTrue(vesting.cancelled());
    }

    function test_Cancel_AfterPartialClaim() public {
        vm.warp(startTime + ONE_YEAR);
        vm.prank(beneficiary);
        vesting.claim();
        uint256 alreadyClaimed = mockToken.balanceOf(beneficiary);

        vm.warp(startTime + 2 * 365 days);
        vesting.cancel();

        uint256 vestedAt2yr = ALLOCATION * 2 * 365 days / FOUR_YEARS;
        uint256 unvested = ALLOCATION - vestedAt2yr;

        assertEq(mockToken.balanceOf(beneficiary), vestedAt2yr);
        assertGt(mockToken.balanceOf(beneficiary), alreadyClaimed);
        assertEq(mockToken.balanceOf(treasuryAddr), unvested);
    }

    function test_Cancel_AfterFullVesting() public {
        vm.warp(startTime + FOUR_YEARS);
        vesting.cancel();

        assertEq(mockToken.balanceOf(beneficiary), ALLOCATION);
        assertEq(mockToken.balanceOf(treasuryAddr), 0);
    }

    function test_Cancel_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        vesting.cancel();
    }

    function test_Cancel_RevertsIfAlreadyCancelled() public {
        vesting.cancel();
        vm.expectRevert(bytes("ALREADY_CANCELLED"));
        vesting.cancel();
    }

    function test_Claim_RevertsAfterCancel() public {
        vm.warp(startTime + 2 * 365 days);
        vesting.cancel();

        vm.prank(beneficiary);
        vm.expectRevert(bytes("CANCELLED"));
        vesting.claim();
    }

    function test_Claimable_ZeroAfterCancel() public {
        vm.warp(startTime + 2 * 365 days);
        vesting.cancel();
        assertEq(vesting.claimable(), 0);
    }

    // ──────────── setBeneficiary ────────────

    function test_SetBeneficiary() public {
        vesting.setBeneficiary(alice);
        assertEq(vesting.beneficiary(), alice);
    }

    function test_SetBeneficiary_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        vesting.setBeneficiary(alice);
    }

    function test_SetBeneficiary_RevertsIfZero() public {
        vm.expectRevert(bytes("ZERO_ADDRESS"));
        vesting.setBeneficiary(address(0));
    }

    function test_SetBeneficiary_NewBeneficiaryClaims() public {
        vm.warp(startTime + ONE_YEAR);
        vesting.setBeneficiary(alice);

        vm.prank(alice);
        vesting.claim();

        assertGt(mockToken.balanceOf(alice), 0);
    }

    function test_SetBeneficiary_OldBeneficiaryCannotClaim() public {
        vm.warp(startTime + ONE_YEAR);
        vesting.setBeneficiary(alice);

        vm.prank(beneficiary);
        vm.expectRevert(bytes("NOT_BENEFICIARY"));
        vesting.claim();
    }
}
