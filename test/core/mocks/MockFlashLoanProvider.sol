// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { IFlashLoanRecipient } from "test/core/mocks/IFlashLoanRecipient.sol";

contract MockFlashLoanProvider {
    function makeFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, bytes memory userData) external {
        uint256 len = tokens.length;
        if (amounts.length != len) revert("Inconsistent lengths");
        uint256[] memory balances = new uint256[](len);

        for (uint256 i; i < len; ++i) {
            balances[i] = tokens[i].balanceOf(address(this));
            tokens[i].transfer(msg.sender, amounts[i]);
        }

        IFlashLoanRecipient(msg.sender).receiveFlashLoan(tokens, amounts, userData);

        // Pull-based repayment
        for (uint256 i; i < len; ++i) {
            tokens[i].transferFrom(msg.sender, address(this), amounts[i]);
            require(tokens[i].balanceOf(address(this)) == balances[i], "Not exact refund");
        }
    }

    function emptyCallback() external {
        IFlashLoanRecipient(msg.sender).emptyCallback();
    }
}
