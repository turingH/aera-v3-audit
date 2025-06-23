// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { OperationPayable } from "src/core/Types.sol";

/// @notice A similar version of this interface was previously audited
/// @dev See: https://github.com/aera-finance/aera-contracts-public/blob/main/v2/periphery/interfaces/IExecutor.sol
interface IExecutor {
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    /// @notice Emitted when operations are executed
    event Executed(address indexed caller, OperationPayable operation);

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    /// @notice Error emitted when the execution of an operation fails
    error AeraPeriphery__ExecutionFailed(bytes result);

    ////////////////////////////////////////////////////////////
    //                   External Functions                   //
    ////////////////////////////////////////////////////////////

    /// @notice Execute arbitrary actions
    /// @param operations The operations to execute
    function execute(OperationPayable[] calldata operations) external;
}
