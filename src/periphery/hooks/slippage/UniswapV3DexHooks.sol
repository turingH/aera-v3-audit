// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { ISwapRouter } from "src/dependencies/uniswap/v3/interfaces/ISwapRouter.sol";

import { UNISWAP_PATH_ADDRESS_SIZE, UNISWAP_PATH_CHUNK_SIZE } from "src/periphery/Constants.sol";

import { BaseSlippageHooks } from "src/periphery/hooks/slippage/BaseSlippageHooks.sol";
import { IUniswapV3DexHooks } from "src/periphery/interfaces/hooks/slippage/IUniswapV3DexHooks.sol";

/// @title UniswapV3DexHooks
/// @notice Implements custom hook logic for swapping on Uniswap V3
abstract contract UniswapV3DexHooks is IUniswapV3DexHooks, BaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //              External / Public Functions               //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IUniswapV3DexHooks
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params) external returns (bytes memory) {
        // Requirements, Effects: perform slippage and daily loss checks
        (address tokenIn, address tokenOut, address receiver) = _handleBeforeExactInputSingle(
            params.tokenIn, params.tokenOut, params.recipient, params.amountIn, params.amountOutMinimum
        );
        return abi.encode(tokenIn, tokenOut, receiver);
    }

    /// @inheritdoc IUniswapV3DexHooks
    function exactInput(ISwapRouter.ExactInputParams calldata params) external returns (bytes memory) {
        uint256 pathLength = params.path.length;

        // Requirements: check that the path is properly formatted - there are at least 2 addresses and 1 fee
        require(pathLength % UNISWAP_PATH_CHUNK_SIZE == UNISWAP_PATH_ADDRESS_SIZE, AeraPeriphery__BadPathFormat());

        address tokenIn;
        address tokenOut;
        unchecked {
            tokenIn = address(bytes20(params.path[:20]));
            tokenOut = address(bytes20(params.path[pathLength - 20:]));
        }

        // Requirements, Effects: perform slippage and daily loss checks
        (address _tokenIn, address _tokenOut, address _receiver) =
            _handleBeforeExactInputSingle(tokenIn, tokenOut, params.recipient, params.amountIn, params.amountOutMinimum);
        return abi.encode(_tokenIn, _tokenOut, _receiver);
    }

    /// @inheritdoc IUniswapV3DexHooks
    function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata params) external returns (bytes memory) {
        // Requirements, Effects: perform slippage and daily loss checks
        (address tokenIn, address tokenOut, address receiver) = _handleBeforeExactOutputSingle(
            params.tokenIn, params.tokenOut, params.recipient, params.amountOut, params.amountInMaximum
        );
        return abi.encode(tokenIn, tokenOut, receiver);
    }

    /// @inheritdoc IUniswapV3DexHooks
    function exactOutput(ISwapRouter.ExactOutputParams calldata params) external returns (bytes memory) {
        uint256 pathLength = params.path.length;

        // Requirements: check that the path is properly formatted - there's at least 2 addresses and 1 fee in the path
        require(pathLength % UNISWAP_PATH_CHUNK_SIZE == UNISWAP_PATH_ADDRESS_SIZE, AeraPeriphery__BadPathFormat());

        address tokenIn;
        address tokenOut;
        unchecked {
            tokenIn = address(bytes20(params.path[:20]));
            tokenOut = address(bytes20(params.path[pathLength - 20:]));
        }

        // Requirements, Effects: perform slippage and daily loss checks
        (address _tokenIn, address _tokenOut, address _receiver) = _handleBeforeExactOutputSingle(
            tokenIn, tokenOut, params.recipient, params.amountOut, params.amountInMaximum
        );
        return abi.encode(_tokenIn, _tokenOut, _receiver);
    }
}
