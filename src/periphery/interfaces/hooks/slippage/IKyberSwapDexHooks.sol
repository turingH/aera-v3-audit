// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IAggregationExecutor } from "src/dependencies/kyberswap/interfaces/IAggregationExecutor.sol";
import { IMetaAggregationRouterV2 } from "src/dependencies/kyberswap/interfaces/IMetaAggregationRouterV2.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

/// @title IKyberSwapDexHooks
/// @notice Interface for KyberSwap swap hooks
interface IKyberSwapDexHooks is IBaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    error AeraPeriphery__FeeReceiversNotEmpty();

    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Hook function matching MetaAggregationRouterV2 `swap` signature
    /// @dev Should only be used as a before hook
    /// @param execution The parameters for executing the swap
    /// @return The encoded parameters for verification
    function swap(IMetaAggregationRouterV2.SwapExecutionParams calldata execution) external returns (bytes memory);

    /// @notice Hook function for simple swap using MetaAggregationRouterV2
    /// @dev Should only be used as a before hook
    /// @param caller The address of the executor that will perform the swap
    /// @param desc The parameters for the swap
    /// @return The encoded parameters for verification
    function swapSimpleMode(
        IAggregationExecutor caller,
        IMetaAggregationRouterV2.SwapDescriptionV2 calldata desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (bytes memory);
}
