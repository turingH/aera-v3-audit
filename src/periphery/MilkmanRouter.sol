// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { SafeERC20 } from "@oz/token/ERC20/utils/SafeERC20.sol";

import { OperationPayable } from "src/core/Types.sol";
import { IMilkman } from "src/dependencies/milkman/interfaces/IMilkman.sol";

import { VaultAuth } from "src/core/VaultAuth.sol";
import { Executor } from "src/periphery/Executor.sol";
import { IMilkmanRouter } from "src/periphery/interfaces/IMilkmanRouter.sol";

/// @title MilkmanRouter
/// @notice Router for executing operations on the Milkman contract
contract MilkmanRouter is IMilkmanRouter, Executor, VaultAuth {
    using SafeERC20 for IERC20;

    ////////////////////////////////////////////////////////////
    //                       Immutables                       //
    ////////////////////////////////////////////////////////////

    /// @notice The address of the AeraVaultV2
    // solhint-disable-next-line immutable-vars-naming
    address public immutable vault;

    /// @notice The address of the Milkman root contract
    // solhint-disable-next-line immutable-vars-naming
    IMilkman public immutable milkmanRoot;

    ////////////////////////////////////////////////////////////
    //                       Modifiers                        //
    ////////////////////////////////////////////////////////////

    /// @notice Modifier to check that the caller is the vault
    modifier onlyVault() {
        // Requirements: check that the caller is the vault
        require(msg.sender == vault, AeraPeriphery__CallerIsNotVault());
        _;
    }

    ////////////////////////////////////////////////////////////
    //                      Constructor                       //
    ////////////////////////////////////////////////////////////

    /// @notice Constructor for the MilkmanRouter contract
    /// @param vault_ The address of the AeraVaultV2
    /// @param milkmanRoot_ The address of the Milkman root contract
    constructor(address vault_, address milkmanRoot_) {
        // Requirements: check that the vault address is not zero
        require(vault_ != address(0), AeraPeriphery__ZeroAddressVault());
        // Requirements: check that the Milkman root address is not zero
        require(milkmanRoot_ != address(0), AeraPeriphery__ZeroAddressMilkmanRoot());

        // Effects: set the vault and Milkman root addresses
        vault = vault_;
        milkmanRoot = IMilkman(milkmanRoot_);
    }

    ////////////////////////////////////////////////////////////
    //                   External Functions                   //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IMilkmanRouter
    function requestSell(
        uint256 sellAmount,
        IERC20 sellToken,
        IERC20 receiveToken,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external onlyVault nonReentrant {
        // Requirements: check that the sellAmount is not zero
        require(sellAmount > 0, AeraPeriphery__MilkmanRouter__SellAmountIsZero());

        // Interactions: transfer sellToken from AeraVault to MilkmanRouter
        sellToken.safeTransferFrom(msg.sender, address(this), sellAmount);

        // Interactions: approve the Milkman root to spend the sellToken
        sellToken.safeIncreaseAllowance(address(milkmanRoot), sellAmount);

        // Interactions: forward swap request to Milkman root
        milkmanRoot.requestSwapExactTokensForTokens(
            sellAmount, sellToken, receiveToken, address(this), appData, priceChecker, priceCheckerData
        );

        // Invariants: validate the Milkman root approval
        // We expect Milkman to spend all approved tokens
        require(
            sellToken.allowance(address(this), address(milkmanRoot)) == 0,
            AeraPeriphery__MilkmanRequestSwapExactTokensForTokensFailed(sellToken)
        );

        // Log that the swap was requested
        emit SellRequested(sellAmount, sellToken, receiveToken, appData, priceChecker, priceCheckerData);
    }

    /// @inheritdoc IMilkmanRouter
    function cancelSell(
        address milkmanOrderContract,
        uint256 sellAmount,
        IERC20 sellToken,
        IERC20 receiveToken,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external onlyVault nonReentrant {
        // Interactions: forward swap cancellation to Milkman
        IMilkman(milkmanOrderContract).cancelSwap(
            sellAmount, sellToken, receiveToken, address(this), appData, priceChecker, priceCheckerData
        );

        // Interactions: transfer tokens back to the Vault
        sellToken.safeTransfer(vault, sellAmount);

        // Log that the swap was cancelled
        emit SellCancelled(
            milkmanOrderContract, sellAmount, sellToken, receiveToken, appData, priceChecker, priceCheckerData
        );
    }

    /// @inheritdoc IMilkmanRouter
    function claim(IERC20 token) external onlyVault nonReentrant {
        uint256 balance = token.balanceOf(address(this));

        // Requirements: check that the balance is not zero
        // slither-disable-next-line incorrect-equality
        if (balance == 0) return;

        // Interactions: transfer tokens to the Vault
        token.safeTransfer(vault, balance);

        // Log that the tokens were claimed
        emit Claimed(token, balance);
    }

    ////////////////////////////////////////////////////////////
    //                   Internal Functions                   //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc Executor
    // solhint-disable-next-line no-empty-blocks
    function _checkOperations(OperationPayable[] calldata operations) internal view override requiresVaultAuth(vault) { }

    /// @inheritdoc Executor
    // solhint-disable-next-line no-empty-blocks
    function _checkOperation(OperationPayable calldata operation) internal view override { }
}
