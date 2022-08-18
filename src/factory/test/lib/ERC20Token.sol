// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "solmate/tokens/ERC20.sol";

contract ERC20Token is ERC20 {
    constructor() ERC20("", "", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
