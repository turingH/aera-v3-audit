// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";

/// @title ITransferWhitelistHook
/// @notice Interface for transfer whitelist hooks
interface ITransferWhitelistHook is IBeforeTransferHook {
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    /// @notice Emitted when the permissioned vault's whitelisted addresses are set
    event VaultWhitelistUpdated(address indexed vault, address[] addresses, bool isWhitelisted);

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    error AeraPeriphery__NotWhitelisted(address address_);

    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Set the vault's whitelisted status
    /// @param vault The vault to set the whitelisted status for
    /// @param addresses The addresses to set the whitelisted status for
    /// @param isWhitelisted Whether the addresses are whitelisted
    function updateWhitelist(address vault, address[] calldata addresses, bool isWhitelisted) external;
}
