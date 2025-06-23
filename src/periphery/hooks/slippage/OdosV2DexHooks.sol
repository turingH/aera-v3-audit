// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IOdosRouterV2 } from "src/dependencies/odos/interfaces/IOdosRouterV2.sol";

import { ODOS_ROUTER_V2_ETH_ADDRESS } from "src/periphery/Constants.sol";
import { BaseSlippageHooks } from "src/periphery/hooks/slippage/BaseSlippageHooks.sol";
import { IOdosV2DexHooks } from "src/periphery/interfaces/hooks/slippage/IOdosV2DexHooks.sol";

/// @title OdosV2DexHooks
/// @notice Implements custom hook logic for swapping using Odos V2
abstract contract OdosV2DexHooks is IOdosV2DexHooks, BaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //              External / Public Functions               //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IOdosV2DexHooks
    function swap(
        IOdosRouterV2.SwapTokenInfo calldata tokenInfo,
        bytes calldata, /* pathDefinition */
        address, /* executor */
        uint32 /* referralCode */
    ) external returns (bytes memory returnData) {
        // Requirements: check that the input amount is not zero
        require(tokenInfo.inputAmount != 0, AeraPeriphery__InputAmountIsZero());

        // Requirements: check that the input token is not ETH
        require(tokenInfo.inputToken != ODOS_ROUTER_V2_ETH_ADDRESS, AeraPeriphery__InputTokenIsETH());

        // Requirements: check that the output token is not ETH
        require(tokenInfo.outputToken != ODOS_ROUTER_V2_ETH_ADDRESS, AeraPeriphery__OutputTokenIsETH());

        // Requirements, Effects: perform slippage and daily loss checks
        (address tokenIn, address tokenOut, address receiver) = _handleBeforeExactInputSingle(
            tokenInfo.inputToken,
            tokenInfo.outputToken,
            tokenInfo.outputReceiver,
            tokenInfo.inputAmount,
            tokenInfo.outputMin
        );
        return abi.encode(tokenIn, tokenOut, receiver);
    }
}
