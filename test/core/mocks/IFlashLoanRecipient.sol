// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";

interface IFlashLoanRecipient {
    function receiveFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, bytes memory userData) external;
    function emptyCallback() external;
}
