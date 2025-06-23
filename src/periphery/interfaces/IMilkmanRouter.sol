// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";

interface IMilkmanRouter {
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    /// @notice Emitted when a sell is requested
    event SellRequested(
        uint256 sellAmount,
        IERC20 indexed sellToken,
        IERC20 indexed receiveToken,
        bytes32 appData,
        address priceChecker,
        bytes priceCheckerData
    );

    /// @notice Emitted when a sell is cancelled
    event SellCancelled(
        address indexed milkmanOrderContract,
        uint256 sellAmount,
        IERC20 indexed sellToken,
        IERC20 indexed receiveToken,
        bytes32 appData,
        address priceChecker,
        bytes priceCheckerData
    );

    /// @notice Emitted when tokens are claimed
    event Claimed(IERC20 indexed token, uint256 amount);

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    /// @notice Error emitted when the vault address is zero
    error AeraPeriphery__ZeroAddressVault();

    /// @notice Error emitted when the Milkman root address is zero
    error AeraPeriphery__ZeroAddressMilkmanRoot();

    /// @notice Error emitted when the caller is not the vault
    error AeraPeriphery__CallerIsNotVault();

    /// @notice Error emitted when the caller is not the vault owner
    error AeraPeriphery__CallerIsNotVaultOwner();

    /// @notice Error emitted when the sell amount is zero
    error AeraPeriphery__MilkmanRouter__SellAmountIsZero();

    /// @notice Error emitted when the Milkman root failed to spend all approved tokens
    error AeraPeriphery__MilkmanRequestSwapExactTokensForTokensFailed(IERC20 token);

    ////////////////////////////////////////////////////////////
    //                   External Functions                   //
    ////////////////////////////////////////////////////////////

    /// @notice Initiate a Milkman swap. This contract is effectively a very direct wrapper
    ///         The reason for it to exist at all is that creating the order from the router allows us to claim back
    /// received tokens in a submit call thus increasing the daily multiplier value of the vault
    /// @param sellAmount The amount of tokens to sell
    /// @param sellToken Token to sell
    /// @param receiveToken Token to receive
    /// @param appData The app data to be used in the CoW Protocol order
    /// @param priceChecker The address of the price checker contract
    /// @param priceCheckerData The data to pass to the price checker contract
    /// @dev    MUST revert if not called by vault
    function requestSell(
        uint256 sellAmount,
        IERC20 sellToken,
        IERC20 receiveToken,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external;

    /// @notice Cancel a Milkman swap at a specific Milkman order contract clone. Returns funds to vault
    ///         Arguments must match the ones used in the `requestSell` call
    /// @param milkmanOrderContract The address of the Milkman order contract clone
    /// @param sellAmount The amount of tokens to sell
    /// @param sellToken Token to sell
    /// @param receiveToken Token to receive
    /// @param appData The app data to be used in the CoW Protocol order
    /// @param priceChecker The address of the price checker contract
    /// @param priceCheckerData The data to pass to the price checker contract
    /// @dev    MUST revert if not called by vault
    function cancelSell(
        address milkmanOrderContract,
        uint256 sellAmount,
        IERC20 sellToken,
        IERC20 receiveToken,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external;

    /// @notice Claim tokens from a completed Milkman order
    /// @param token The token to claim
    /// @dev    MUST revert if not called by vault
    function claim(IERC20 token) external;
}
