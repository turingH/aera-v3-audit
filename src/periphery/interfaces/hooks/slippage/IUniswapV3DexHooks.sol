// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { ISwapRouter } from "src/dependencies/uniswap/v3/interfaces/ISwapRouter.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

/// @title IUniswapV3DexHooks
/// @notice Interface for Uniswap V3 swap hooks
interface IUniswapV3DexHooks is IBaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    error AeraPeriphery__BadPathFormat();

    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Hook function matching Uniswap V3 Router `exactInputSingle` signature
    /// @dev Should only be used as a before hook
    /// @param params The parameters for the swap
    /// @return The encoded parameters for verification
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params) external returns (bytes memory);

    /// @notice Hook function matching Uniswap V3 Router `exactInput` signature
    /// @dev Should only be used as a before hook
    /// @param params The parameters for the swap
    /// @return The encoded parameters for verification
    function exactInput(ISwapRouter.ExactInputParams calldata params) external returns (bytes memory);

    /// @notice Hook function matching Uniswap V3 Router `exactOutputSingle` signature
    /// @dev Should only be used as a before hook
    /// @param params The parameters for the swap
    /// @return The encoded parameters for verification
    function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata params) external returns (bytes memory);

    /// @notice Hook function matching Uniswap V3 Router `exactOutput` signature
    /// @dev Should only be used as a before hook
    /// @param params The parameters for the swap
    /// @return The encoded parameters for verification
    function exactOutput(ISwapRouter.ExactOutputParams calldata params) external returns (bytes memory);
}
