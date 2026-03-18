// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin-v3/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-v3/contracts/drafts/ERC20Permit.sol";

contract FreeTheBlocksTestUSDC is ERC20, ERC20Permit {
    uint256 public constant MAX_MINT_PER_CALL = 100_000 * 10 ** 6;

    constructor()
        ERC20("FreeTheBlocks Test USDC", "tUSDC")
        ERC20Permit("FreeTheBlocks Test USDC")
    {
        _mint(msg.sender, 1_000_000 * 10 ** 6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        require(amount <= MAX_MINT_PER_CALL, "Max 100000 per mint");
        _mint(to, amount);
    }
}
