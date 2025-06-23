// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { MockERC20 } from "forge-std/mocks/MockERC20.sol";

contract ERC20Mock is MockERC20 {
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
