// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";

import { IMilkmanPriceChecker } from "src/dependencies/milkman/interfaces/IMilkmanPriceChecker.sol";
import { BaseSlippageHooks } from "src/periphery/hooks/slippage/BaseSlippageHooks.sol";
import { IMilkmanHooks } from "src/periphery/interfaces/hooks/slippage/IMilkmanHooks.sol";

abstract contract MilkmanHooks is IMilkmanHooks, IMilkmanPriceChecker, BaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //              External / Public Functions               //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IMilkmanHooks
    function requestSell(
        uint256 sellAmount,
        IERC20 sellToken,
        IERC20 receiveToken,
        bytes32, /* appData */
        address priceChecker,
        bytes calldata priceCheckerData
    ) external returns (bytes memory returnData) {
        // Requirements: check that the price checker is this contract
        require(priceChecker == address(this), AeraPeriphery__InvalidPriceChecker(address(this), priceChecker));

        // Requirements: check that the vault sent to the price checker is the same as the vault calling the hooks
        address vault = abi.decode(priceCheckerData, (address));
        require(msg.sender == vault, AeraPeriphery__InvalidVaultInPriceCheckerData(msg.sender, vault));

        // Effects: update hooks state
        _handleMilkmanBeforeHook(address(sellToken), sellAmount, msg.sender);

        // Return the encoded parameters for verification - (tokenIn, tokenOut)
        returnData = abi.encode(address(sellToken), address(receiveToken));
    }

    /// @notice Serves as a price checker for Milkman swaps
    /// @param amountIn The amount of the input token to swap
    /// @param fromToken The address of the input token
    /// @param toToken The address of the output token
    /// @param minOut The minimum amount of the output token to receive
    /// @param data The data for the price checker (encodes `vault` address)
    function checkPrice(
        uint256 amountIn,
        address fromToken,
        address toToken,
        uint256, /* feeAmount */
        uint256 minOut,
        bytes calldata data
    ) external view returns (bool) {
        address vault = abi.decode(data, (address));
        State storage state = _vaultStates[vault];

        // Check the expected output amount, with the applied slippage, against provided minimum output amount
        uint256 expectedOut = state.oracleRegistry.getQuoteForUser(amountIn, fromToken, toToken, vault);
        uint256 slippageMultiplier;
        unchecked {
            slippageMultiplier = MAX_BPS - state.maxSlippagePerTrade;
        }
        return minOut > (expectedOut * slippageMultiplier / MAX_BPS);
    }

    ////////////////////////////////////////////////////////////
    //              Private / Internal Functions              //
    ////////////////////////////////////////////////////////////

    /// @dev Handles daily loss for Milkman swaps
    /// @param sellToken The address of the sell token
    /// @param sellAmount The amount of the sell token
    /// @param vault The address of the vault
    function _handleMilkmanBeforeHook(address sellToken, uint256 sellAmount, address vault) internal {
        State storage state = _vaultStates[vault];

        // Interactions: calculate the loss incurred in the swap, as if the maximum slippage has been applied
        uint256 loss = _convertToNumeraire(sellAmount * state.maxSlippagePerTrade / MAX_BPS, sellToken);

        // Requirements, Effects: enforce the daily loss limit and set the new cumulative daily loss
        state.cumulativeDailyLossInNumeraire = uint128(_enforceDailyLoss(state, loss));
    }
}
