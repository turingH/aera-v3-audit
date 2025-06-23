// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IAggregationExecutor } from "src/dependencies/kyberswap/interfaces/IAggregationExecutor.sol";
import { IMetaAggregationRouterV2 } from "src/dependencies/kyberswap/interfaces/IMetaAggregationRouterV2.sol";

import { KYBERSWAP_ETH_ADDRESS } from "src/periphery/Constants.sol";
import { BaseSlippageHooks } from "src/periphery/hooks/slippage/BaseSlippageHooks.sol";
import { IKyberSwapDexHooks } from "src/periphery/interfaces/hooks/slippage/IKyberSwapDexHooks.sol";

/// @title KyberSwapDexHooks
/// @notice Implements custom hook logic for simple mode swapping on KyberSwap
abstract contract KyberSwapDexHooks is IKyberSwapDexHooks, BaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //              External / Public Functions               //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IKyberSwapDexHooks
    function swap(IMetaAggregationRouterV2.SwapExecutionParams calldata execution) external returns (bytes memory) {
        return _processSwapHooks(execution.desc, execution.callTarget);
    }

    /// @inheritdoc IKyberSwapDexHooks
    function swapSimpleMode(
        IAggregationExecutor caller,
        IMetaAggregationRouterV2.SwapDescriptionV2 calldata desc,
        bytes calldata, /* executorData */
        bytes calldata /* clientData */
    ) external returns (bytes memory) {
        return _processSwapHooks(desc, address(caller));
    }

    ////////////////////////////////////////////////////////////
    //              Private / Internal Functions              //
    ////////////////////////////////////////////////////////////

    /// @notice Internal function processing before and after swap hooks
    /// @param desc The parameters for the swap
    /// @param executor The address of the contract that will execute the swap
    /// @return returnData The encoded parameters for verification
    function _processSwapHooks(IMetaAggregationRouterV2.SwapDescriptionV2 calldata desc, address executor)
        internal
        returns (bytes memory returnData)
    {
        // Requirements: check that the input token is not ETH
        require(address(desc.srcToken) != KYBERSWAP_ETH_ADDRESS, AeraPeriphery__InputTokenIsETH());

        // Requirements: check that the output token is not ETH
        require(address(desc.dstToken) != KYBERSWAP_ETH_ADDRESS, AeraPeriphery__OutputTokenIsETH());

        // Requirements: check that there are no fee receivers
        require(desc.feeReceivers.length == 0, AeraPeriphery__FeeReceiversNotEmpty());

        (address tokenIn, address tokenOut, address receiver) = _handleBeforeExactInputSingle(
            address(desc.srcToken), address(desc.dstToken), desc.dstReceiver, desc.amount, desc.minReturnAmount
        );
        return abi.encode(tokenIn, tokenOut, receiver, executor);
    }
}
