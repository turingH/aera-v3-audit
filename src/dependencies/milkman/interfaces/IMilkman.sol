// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";

interface IMilkman {
    function requestSwapExactTokensForTokens(
        uint256 amountIn,
        IERC20 fromToken,
        IERC20 toToken,
        address to,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external;

    function cancelSwap(
        uint256 amountIn,
        IERC20 fromToken,
        IERC20 toToken,
        address to,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external;
}
