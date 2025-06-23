// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";
import { AbstractTransferHook } from "src/periphery/hooks/transfer/AbstractTransferHook.sol";
import { ITransferWhitelistHook } from "src/periphery/interfaces/hooks/transfer/ITransferWhitelistHook.sol";

/// @title TransferWhitelistHook
/// @notice Only allows users on a whitelist to transfer vault units in multi-depositor vaults
contract TransferWhitelistHook is AbstractTransferHook, ITransferWhitelistHook {
    ////////////////////////////////////////////////////////////
    //                        Storage                         //
    ////////////////////////////////////////////////////////////

    /// @notice Mapping of whitelisted addresses for each vault
    mapping(address vault => mapping(address addr => bool isWhitelisted)) public whitelist;

    ////////////////////////////////////////////////////////////
    //              Public / External Functions               //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc ITransferWhitelistHook
    function updateWhitelist(address vault, address[] calldata addresses, bool isWhitelisted)
        external
        requiresVaultAuth(vault)
    {
        uint256 length = addresses.length;
        address addr;

        for (uint256 i; i < length; i++) {
            addr = addresses[i];

            // Effects: whitelist addresses
            whitelist[vault][addr] = isWhitelisted;
        }

        // Log new whitelisted/removed addresses
        emit VaultWhitelistUpdated(vault, addresses, isWhitelisted);
    }

    /// @inheritdoc IBeforeTransferHook
    function beforeTransfer(address from, address to, address transferAgent)
        public
        view
        override(AbstractTransferHook, IBeforeTransferHook)
    {
        super.beforeTransfer(from, to, transferAgent);

        // Check that the `from` and `to` addresses are whitelisted
        require(
            from == address(0) || from == transferAgent || whitelist[msg.sender][from],
            AeraPeriphery__NotWhitelisted(from)
        );
        require(to == address(0) || to == transferAgent || whitelist[msg.sender][to], AeraPeriphery__NotWhitelisted(to));
    }
}
