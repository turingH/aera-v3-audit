// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IAggregationExecutor {
    function callBytes(bytes calldata data) external payable;

    function swapSingleSequence(bytes calldata data) external;

    function finalTransactionProcessing(address tokenIn, address tokenOut, address to, bytes calldata destTokenFeeData)
        external;
}
