// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20 } from "@oz/token/ERC20/ERC20.sol";

contract WrappedNativeTokenMock is ERC20 {
    error TransferFailed();

    constructor() ERC20("Wrapped Native", "WETH") { }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        (bool success,) = msg.sender.call{ value: amount }("");

        require(success, TransferFailed());
    }
}
