// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { TargetCalldata } from "src/core/Types.sol";

/// @notice A similar version of this interface was previously audited
/// @dev See: https://github.com/aera-finance/aera-contracts-public/blob/main/v2/periphery/interfaces/IExecutor.sol
interface IForwarder {
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    /// @notice Emitted when operations are executed
    event Executed(address indexed caller, TargetCalldata[] operations);

    /// @notice Emitted when a caller's capability has been added
    event CallerCapabilityAdded(address indexed caller, address indexed target, bytes4 indexed selector);

    /// @notice Emitted when a caller's capability has been removed
    event CallerCapabilityRemoved(address indexed caller, address indexed target, bytes4 indexed selector);

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    /// @notice Error emitted when the caller is not authorized to execute the operation
    error AeraPeriphery__Unauthorized(address caller, address target, bytes4 selector);

    ////////////////////////////////////////////////////////////
    //                   External Functions                   //
    ////////////////////////////////////////////////////////////

    /// @notice Execute arbitrary actions
    /// @param operations The operations to execute
    function execute(TargetCalldata[] calldata operations) external;

    /// @notice Adds caller's capability to the forwarder
    /// @param caller The caller to be authorized
    /// @param target The target contract
    /// @param sig The function selector to be callable
    function addCallerCapability(address caller, address target, bytes4 sig) external;

    /// @notice Removes caller's capability from the forwarder
    /// @param caller The caller to be removed
    /// @param target The target contract
    /// @param sig The function selector to be uncallable
    function removeCallerCapability(address caller, address target, bytes4 sig) external;

    /// @notice Checks if a caller has capability to call a function on a target contract
    /// @param caller The caller to check
    /// @param target The target contract
    /// @param sig The function selector to check
    /// @return True if the caller has capability, false otherwise
    function canCall(address caller, address target, bytes4 sig) external view returns (bool);
}
