// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { HookCallType } from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";

/// @title HooksLibrary
/// @notice Library to be used when building custom operation hooks
library HooksLibrary {
    ////////////////////////////////////////////////////////////
    //              Private / Internal Functions              //
    ////////////////////////////////////////////////////////////

    /// @notice Check if the current hook call is a before hook call
    /// @return True if the current hook call is a before hook call, false otherwise
    function isBeforeHook() internal view returns (bool) {
        return IBaseVault(msg.sender).getCurrentHookCallType() == HookCallType.BEFORE;
    }

    /// @notice Check if the current hook call is an after hook call
    /// @return True if the current hook call is an after hook call, false otherwise
    function isAfterHook() internal view returns (bool) {
        return IBaseVault(msg.sender).getCurrentHookCallType() == HookCallType.AFTER;
    }
}
