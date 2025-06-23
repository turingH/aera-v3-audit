// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Address } from "@oz/utils/Address.sol";
import { ReentrancyGuard } from "@oz/utils/ReentrancyGuard.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

import { TargetCalldata } from "src/core/Types.sol";
import { IForwarder } from "src/periphery/interfaces/IForwarder.sol";

/// @title Forwarder
/// @notice Contract that allows authorized callers to execute multiple operations through fine-grained access control
contract Forwarder is IForwarder, Auth, ReentrancyGuard {
    using Address for address;

    ////////////////////////////////////////////////////////////
    //                        Storage                         //
    ////////////////////////////////////////////////////////////

    /// @notice Mapping that indicates if a caller has permission to execute a function on a specific target contract
    mapping(address caller => mapping(bytes32 targetAndSelector => bool enabled)) internal _canCall;

    ////////////////////////////////////////////////////////////
    //                      Constructor                       //
    ////////////////////////////////////////////////////////////

    constructor(address initialOwner, Authority initialAuthority) Auth(initialOwner, initialAuthority) { }

    ////////////////////////////////////////////////////////////
    //                   External Functions                   //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IForwarder
    function execute(TargetCalldata[] calldata operations) external nonReentrant {
        address target;
        bytes memory data;
        bytes32 targetAndSelector;
        mapping(bytes32 targetAndSelector => bool enabled) storage callerCapabilities = _canCall[msg.sender];

        uint256 length = operations.length;
        for (uint256 i; i < length; ++i) {
            target = operations[i].target;
            data = operations[i].data;
            targetAndSelector = _packTargetSig(target, bytes4(data));

            // Requirements: check if caller has permission to execute this operation
            require(
                callerCapabilities[targetAndSelector], AeraPeriphery__Unauthorized(msg.sender, target, bytes4(data))
            );

            // Interactions: execute the operation
            (bool success, bytes memory returnData) = target.call(data);
            Address.verifyCallResultFromTarget(target, success, returnData);
        }

        // Log that the operations were executed
        emit Executed(msg.sender, operations);
    }

    /// @inheritdoc IForwarder
    function addCallerCapability(address caller, address target, bytes4 sig) external requiresAuth {
        bytes32 targetAndSelector = _packTargetSig(target, sig);

        // Effects: add the caller capability
        _canCall[caller][targetAndSelector] = true;

        // Log the caller capability updated event
        emit CallerCapabilityAdded(caller, target, sig);
    }

    /// @inheritdoc IForwarder
    function removeCallerCapability(address caller, address target, bytes4 sig) external requiresAuth {
        bytes32 targetAndSelector = _packTargetSig(target, sig);

        // Effects: remove the caller capability
        _canCall[caller][targetAndSelector] = false;

        // Log the caller capability updated event
        emit CallerCapabilityRemoved(caller, target, sig);
    }

    /// @inheritdoc IForwarder
    function canCall(address caller, address target, bytes4 sig) external view returns (bool) {
        bytes32 targetAndSelector = _packTargetSig(target, sig);
        return _canCall[caller][targetAndSelector];
    }

    ////////////////////////////////////////////////////////////
    //              Private / Internal Functions              //
    ////////////////////////////////////////////////////////////

    /// @notice Combines target address and function selector into a single bytes32 value
    /// @param target The target contract address
    /// @param sig The function selector
    /// @return Combined bytes32 value
    function _packTargetSig(address target, bytes4 sig) internal pure returns (bytes32) {
        return bytes32(uint256(bytes32(sig)) | uint256(uint160(target)));
    }
}
