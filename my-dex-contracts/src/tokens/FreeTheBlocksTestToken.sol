// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin-v3/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-v3/contracts/drafts/ERC20Permit.sol";

contract FreeTheBlocksTestToken is ERC20, ERC20Permit {
    uint256 public constant MAX_MINT_PER_CALL = 10_000 * 10 ** 18;

    constructor()
        ERC20("FreeTheBlocks Test Token", "FTB")
        ERC20Permit("FreeTheBlocks Test Token")
    {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        require(amount <= MAX_MINT_PER_CALL, "Max 10000 per mint");
        _mint(to, amount);
    }
}
