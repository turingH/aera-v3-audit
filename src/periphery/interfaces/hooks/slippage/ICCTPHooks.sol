// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

/// @title ICCTPHooks
/// @notice Interface for CCTPv2 hooks
interface ICCTPHooks is IBaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    error AeraPeriphery__DestinationCallerNotZero();

    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Hook function matching ITokenMessengerV2 `depositForBurn` signature
    /// @dev Should only be used as a before hook
    /// @param amount Amount of tokens to burn
    /// @param destinationDomain Domain ID of the destination chain
    /// @param mintRecipient Recipient address on the destination chain
    /// @param burnToken Token to burn on the source chain
    /// @param destinationCaller Authorized caller on the destination chain
    /// @param maxFee Max fee to pay on the destination chain, in burnToken units
    /// @param minFinalityThreshold Minimum finality required before the burn message is attested
    /// @return The encoded parameters for verification
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external returns (bytes memory);
}
