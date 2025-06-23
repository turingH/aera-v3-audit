// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IOdosRouterV2 } from "src/dependencies/odos/interfaces/IOdosRouterV2.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

/// @title IOdosV2DexHooks
/// @notice Interface for Odos V2 swap hooks
interface IOdosV2DexHooks is IBaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Hook function matching OdosRouterV2 `swap` signature
    /// @dev Should only be used as a before hook
    /// @dev The executor is not used or validated, because in the end, the `outputMin` will be used to verify the swap
    ///      on the router itself
    /// @param tokenInfo The parameters for the swap
    /// @return The encoded parameters for verification
    function swap(IOdosRouterV2.SwapTokenInfo calldata tokenInfo, bytes calldata, address, uint32)
        external
        returns (bytes memory);
}
