// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";

/// @title IMultiDepositorVault
/// @notice Interface for vaults that can accept deposits from multiple addresses
interface IMultiDepositorVault {
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    event BeforeTransferHookSet(address indexed beforeTransferHook);
    event ProvisionerSet(address indexed provisioner);
    event Enter(
        address indexed sender,
        address indexed recipient,
        IERC20 indexed token,
        uint256 tokenAmount,
        uint256 unitsAmount
    );
    event Exit(
        address indexed sender,
        address indexed recipient,
        IERC20 indexed token,
        uint256 tokenAmount,
        uint256 unitsAmount
    );

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    error Aera__UnitsLocked();
    error Aera__ZeroAddressProvisioner();
    error Aera__CallerIsNotProvisioner();

    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Set the before transfer hooks
    /// @param hooks The before transfer hooks address
    function setBeforeTransferHook(IBeforeTransferHook hooks) external;

    /// @notice Deposit tokens into the vault and mint units
    /// @param sender The sender of the tokens
    /// @param token The token to deposit
    /// @param tokenAmount The amount of token to deposit
    /// @param unitsAmount The amount of units to mint
    /// @param recipient The recipient of the units
    function enter(address sender, IERC20 token, uint256 tokenAmount, uint256 unitsAmount, address recipient)
        external;

    /// @notice Withdraw tokens from the vault and burn units
    /// @param sender The sender of the units
    /// @param token The token to withdraw
    /// @param tokenAmount The amount of token to withdraw
    /// @param unitsAmount The amount of units to burn
    /// @param recipient The recipient of the tokens
    function exit(address sender, IERC20 token, uint256 tokenAmount, uint256 unitsAmount, address recipient) external;
}
