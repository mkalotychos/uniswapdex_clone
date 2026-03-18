// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin-v3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-v3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin-v3/contracts/math/SafeMath.sol";

/// @title VestingWallet — Linear token vesting with cliff
/// @notice Holds tokens for team / investors with a 1-year cliff followed
///         by 3 additional years of linear release (4 years total).
///         Owner (DAO / multisig) can cancel — unvested tokens return to treasury.
contract VestingWallet {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public beneficiary;
    address public owner;
    address public treasury;

    uint256 public totalAllocation;
    uint256 public claimed;
    uint256 public startTime;
    uint256 public cliffDuration;
    uint256 public vestingDuration;
    bool public cancelled;

    event VestingStarted(address indexed beneficiary, uint256 amount, uint256 startTime);
    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event VestingCancelled(uint256 unvestedReturned, uint256 vestedReleased);
    event BeneficiaryChanged(address indexed oldBeneficiary, address indexed newBeneficiary);

    /// @param _token            ERC20 token being vested
    /// @param _beneficiary      Address that receives vested tokens
    /// @param _treasury         Address that receives unvested tokens on cancellation
    /// @param _startTime        Unix timestamp when vesting clock begins
    /// @param _cliffDuration    Seconds before any tokens vest (e.g. 365 days)
    /// @param _vestingDuration  Total vesting period in seconds (e.g. 4 * 365 days)
    /// @param _totalAllocation  Total tokens to be vested
    constructor(
        address _token,
        address _beneficiary,
        address _treasury,
        uint256 _startTime,
        uint256 _cliffDuration,
        uint256 _vestingDuration,
        uint256 _totalAllocation
    ) {
        require(_token != address(0), "ZERO_TOKEN");
        require(_beneficiary != address(0), "ZERO_BENEFICIARY");
        require(_treasury != address(0), "ZERO_TREASURY");
        require(_vestingDuration > _cliffDuration, "CLIFF_GTE_DURATION");
        require(_totalAllocation > 0, "ZERO_ALLOCATION");

        token = IERC20(_token);
        beneficiary = _beneficiary;
        owner = msg.sender;
        treasury = _treasury;
        startTime = _startTime;
        cliffDuration = _cliffDuration;
        vestingDuration = _vestingDuration;
        totalAllocation = _totalAllocation;

        emit VestingStarted(_beneficiary, _totalAllocation, _startTime);
    }

    /// @notice Total tokens vested so far (includes already-claimed tokens)
    function vestedAmount() public view returns (uint256) {
        if (block.timestamp < startTime.add(cliffDuration)) {
            return 0;
        }
        if (block.timestamp >= startTime.add(vestingDuration)) {
            return totalAllocation;
        }
        uint256 elapsed = block.timestamp.sub(startTime);
        return totalAllocation.mul(elapsed).div(vestingDuration);
    }

    /// @notice Tokens currently available to claim
    function claimable() public view returns (uint256) {
        if (cancelled) return 0;
        return vestedAmount().sub(claimed);
    }

    /// @notice Beneficiary claims all currently vested (unclaimed) tokens
    function claim() external {
        require(msg.sender == beneficiary, "NOT_BENEFICIARY");
        require(!cancelled, "CANCELLED");

        uint256 amount = vestedAmount().sub(claimed);
        require(amount > 0, "NOTHING_TO_CLAIM");

        claimed = claimed.add(amount);
        token.safeTransfer(beneficiary, amount);

        emit TokensClaimed(beneficiary, amount);
    }

    /// @notice Owner cancels vesting. Vested-but-unclaimed tokens go to
    ///         beneficiary; unvested tokens return to treasury.
    function cancel() external {
        require(msg.sender == owner, "NOT_OWNER");
        require(!cancelled, "ALREADY_CANCELLED");

        cancelled = true;

        uint256 vested = vestedAmount();
        uint256 unvested = totalAllocation.sub(vested);

        uint256 unclaimed = vested.sub(claimed);
        if (unclaimed > 0) {
            claimed = claimed.add(unclaimed);
            token.safeTransfer(beneficiary, unclaimed);
        }

        if (unvested > 0) {
            token.safeTransfer(treasury, unvested);
        }

        emit VestingCancelled(unvested, unclaimed);
    }

    /// @notice Owner can reassign the beneficiary (e.g. key rotation)
    function setBeneficiary(address _newBeneficiary) external {
        require(msg.sender == owner, "NOT_OWNER");
        require(_newBeneficiary != address(0), "ZERO_ADDRESS");
        emit BeneficiaryChanged(beneficiary, _newBeneficiary);
        beneficiary = _newBeneficiary;
    }
}
