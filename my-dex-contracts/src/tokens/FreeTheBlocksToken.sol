// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin-v3/contracts/token/ERC20/ERC20Snapshot.sol";
import "@openzeppelin-v3/contracts/drafts/ERC20Permit.sol";

/// @title FreeTheBlocks Governance Token
/// @notice Fixed-supply governance token with snapshot & permit support.
///         Snapshots enable trustless on-chain voting and dividend distribution.
contract FreeTheBlocksToken is ERC20Snapshot, ERC20Permit {
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18; // 100M hard cap

    address public snapshotAdmin;

    event SnapshotAdminChanged(address indexed oldAdmin, address indexed newAdmin);

    /// @param liquidityMining  40% — MasterChef emissions
    /// @param treasury         25% — DAO treasury / timelock
    /// @param teamVesting      20% — Team vesting contract
    /// @param investorVesting  10% — Investor vesting contract
    /// @param community         5% — Airdrop / community
    constructor(
        address liquidityMining,
        address treasury,
        address teamVesting,
        address investorVesting,
        address community
    )
        ERC20("FreeTheBlocks Token", "FBLK")
        ERC20Permit("FreeTheBlocks Token")
    {
        require(liquidityMining != address(0), "ZERO_LM");
        require(treasury != address(0), "ZERO_TREASURY");
        require(teamVesting != address(0), "ZERO_TEAM");
        require(investorVesting != address(0), "ZERO_INVESTOR");
        require(community != address(0), "ZERO_COMMUNITY");

        _mint(liquidityMining,  40_000_000 * 1e18); // 40%
        _mint(treasury,         25_000_000 * 1e18); // 25%
        _mint(teamVesting,      20_000_000 * 1e18); // 20%
        _mint(investorVesting,  10_000_000 * 1e18); // 10%
        _mint(community,         5_000_000 * 1e18); //  5%

        snapshotAdmin = msg.sender;
    }

    /// @notice Burns tokens from caller (used by BuyAndBurn mechanism)
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Creates a governance snapshot — returns the snapshot id
    function snapshot() external returns (uint256) {
        require(msg.sender == snapshotAdmin, "NOT_ADMIN");
        return _snapshot();
    }

    /// @notice Transfers snapshot-creation rights (e.g. to a timelock / governor)
    function setSnapshotAdmin(address _newAdmin) external {
        require(msg.sender == snapshotAdmin, "NOT_ADMIN");
        require(_newAdmin != address(0), "ZERO_ADDRESS");
        emit SnapshotAdminChanged(snapshotAdmin, _newAdmin);
        snapshotAdmin = _newAdmin;
    }

    // Resolve diamond: ERC20Snapshot needs _beforeTokenTransfer hook
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Snapshot) {
        super._beforeTokenTransfer(from, to, amount);
    }
}
