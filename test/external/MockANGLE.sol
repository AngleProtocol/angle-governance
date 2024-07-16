// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20 } from "oz-v5/token/ERC20/ERC20.sol";

contract MockANGLE is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
