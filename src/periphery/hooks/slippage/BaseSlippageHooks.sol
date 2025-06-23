// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IOracle } from "src/dependencies/oracles/IOracle.sol";

import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { VaultAuth } from "src/core/VaultAuth.sol";
import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

/// @title BaseSlippageHooks
/// @notice Base contract for hooks attached to operations which incur slippage (e.g., trades, bridges)
/// Maintains a daily cumulative loss limit and a per trade slippage limit set by each vault's owner in numeraire
/// asset terms
/// @dev Slippage hook implementers need to identify whether their swap action has an exact input (i.e., fixed amount of
/// input tokens) or exact output. For example, if the swap is a fixed input swap, the implementer needs to use
/// the _handleBeforeExactInputSingle and _handleAfterExactInputSingle in the before- and after- branches of their
/// custom hook. The base slippage hook will then handle all the logic automatically. Implementers may either provide
/// exact slippage or for asynchronous trades where exact slippage is not available at the time of trading, implementers
/// may apply the maximum possible slippage based on trade limits
abstract contract BaseSlippageHooks is IBaseSlippageHooks, HasNumeraire, VaultAuth {
    ////////////////////////////////////////////////////////////
    //                       Constants                        //
    ////////////////////////////////////////////////////////////

    /// @notice Maximum amount of basis points, used for slippage and daily loss calculations
    uint256 public constant MAX_BPS = 10_000; // 100%

    ////////////////////////////////////////////////////////////
    //                        Storage                         //
    ////////////////////////////////////////////////////////////

    mapping(address vault => State state) internal _vaultStates;

    ////////////////////////////////////////////////////////////
    //              External / Public Functions               //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IBaseSlippageHooks
    function setMaxDailyLoss(address vault, uint128 maxLoss) external requiresVaultAuth(vault) {
        // Effects: set the maximum daily loss in numeraire terms
        _vaultStates[vault].maxDailyLossInNumeraire = maxLoss;

        // Log that maximum daily loss is changed
        emit UpdateMaxDailyLoss(vault, maxLoss);
    }

    /// @inheritdoc IBaseSlippageHooks
    function setMaxSlippagePerTrade(address vault, uint16 newMaxSlippage) external requiresVaultAuth(vault) {
        // Requirements: check that the max slippage is within the allowed limits
        require(newMaxSlippage < MAX_BPS, AeraPeriphery__MaxSlippagePerTradeTooHigh(newMaxSlippage));

        // Effects: set the maximum slippage per trade
        _vaultStates[vault].maxSlippagePerTrade = newMaxSlippage;

        // Log that maximum per trade slippage is changed
        emit UpdateMaxSlippage(vault, newMaxSlippage);
    }

    /// @inheritdoc IBaseSlippageHooks
    function setOracleRegistry(address vault, address oracleRegistry) external requiresVaultAuth(vault) {
        // Requirements: check that the oracle registry address is not zero
        require(oracleRegistry != address(0), AeraPeriphery__ZeroAddressOracleRegistry());

        // Effects: set the oracle registry
        _vaultStates[vault].oracleRegistry = IOracleRegistry(oracleRegistry);

        // Log that the oracle registry is updated
        emit UpdateOracleRegistry(vault, oracleRegistry);
    }

    /// @inheritdoc IBaseSlippageHooks
    function vaultStates(address vault) external view returns (State memory state) {
        state = _vaultStates[vault];

        uint32 day = uint32(block.timestamp / 1 days);
        if (state.currentDay != day) {
            state.currentDay = day;
            state.cumulativeDailyLossInNumeraire = 0;
        }
    }

    ////////////////////////////////////////////////////////////
    //              Internal / Private Functions              //
    ////////////////////////////////////////////////////////////

    /// @notice Handle before swap logic for `exactInputSingle` type actions
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param recipient The address of the recipient
    /// @param amountIn The amount of input tokens
    /// @param amountOutMinimum The minimum amount of output tokens
    /// @return The parameters for verification
    function _handleBeforeExactInputSingle(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (address, address, address) {
        // Calculate amountIn value in numeraire terms
        uint256 amountInNumeraire = _convertToNumeraire(amountIn, tokenIn);

        // Calculate amountOutMinimum value in numeraire terms, taking maximum slippage into account
        uint256 amountOutMinimumNumeraire = _convertToNumeraire(amountOutMinimum, tokenOut);

        // Requirements and Effects: enforce trade slippage and daily loss
        _enforceSlippageLimitAndDailyLossLog(
            msg.sender, tokenIn, tokenOut, amountInNumeraire, amountOutMinimumNumeraire
        );

        // Effects: Return parameters for verification
        return (tokenIn, tokenOut, recipient);
    }

    /// @notice Handle before swap logic for `exactOutputSingle` type actions
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param recipient The address of the recipient
    /// @param amountOut The amount of output tokens
    /// @param amountInMaximum The maximum amount of input tokens
    /// @return The parameters for verification
    function _handleBeforeExactOutputSingle(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum
    ) internal returns (address, address, address) {
        // Calculate amountInMaximum value in numeraire terms, taking maximum slippage into account
        uint256 amountInMaximumNumeraire = _convertToNumeraire(amountInMaximum, tokenIn);

        // Calculate amountOut value in numeraire terms
        uint256 amountOutNumeraire = _convertToNumeraire(amountOut, tokenOut);

        // Requirements, and Effects: enforce trade slippage and daily loss
        _enforceSlippageLimitAndDailyLossLog(
            msg.sender, tokenIn, tokenOut, amountInMaximumNumeraire, amountOutNumeraire
        );

        // Return parameters for verification
        return (tokenIn, tokenOut, recipient);
    }

    /// @notice Enforces slippage limit and updates daily loss, emits a TradeSlippageChecked event
    /// @param vault The vault address
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param valueBefore The value before the swap
    /// @param valueAfter The value after the swap
    function _enforceSlippageLimitAndDailyLossLog(
        address vault,
        address tokenIn,
        address tokenOut,
        uint256 valueBefore,
        uint256 valueAfter
    ) internal {
        // If the valueBefore > valueAfter, it means a loss was incurred and we need to check if the slippage is within
        // the allowed limits. Otherwise, a gain is incurred, likely due to arbitrage, and we discard that scenario
        if (valueBefore <= valueAfter) {
            return;
        }

        // Requirements, and Effects: enforce trade slippage and daily loss
        uint128 cumulativeDailyLossNumeraire = _enforceSlippageLimitAndDailyLoss(valueBefore, valueAfter);

        // Log emit trade slippage checked event
        emit TradeSlippageChecked(vault, tokenIn, tokenOut, valueBefore, valueAfter, cumulativeDailyLossNumeraire);
    }

    /// @notice Accumulate slippage and fail if any slippage bounds are violated
    /// @param valueBefore The value before the swap
    /// @param valueAfter The value after the swap
    /// @return cumulativeDailyLossInNumeraire Total daily loss in numeraire
    function _enforceSlippageLimitAndDailyLoss(uint256 valueBefore, uint256 valueAfter)
        internal
        returns (uint128 cumulativeDailyLossInNumeraire)
    {
        State storage state = _vaultStates[msg.sender];

        uint256 loss;
        unchecked {
            loss = valueBefore - valueAfter;
        }

        // Requirements: enforce slippage
        _enforceSlippageLimit(state, loss, valueBefore);

        // Effects: increase cumulative daily loss
        cumulativeDailyLossInNumeraire = uint128(_enforceDailyLoss(state, loss));
        state.cumulativeDailyLossInNumeraire = cumulativeDailyLossInNumeraire;
    }

    /// @notice Get the new daily loss
    /// @param state The state of the vault
    /// @param loss The loss incurred in the swap
    /// @return newLoss The new daily loss
    function _enforceDailyLoss(State storage state, uint256 loss) internal returns (uint256 newLoss) {
        uint32 day = uint32(block.timestamp / 1 days);
        if (state.currentDay != day) {
            // Effects: reset the current day and daily metrics
            state.currentDay = day;
            state.cumulativeDailyLossInNumeraire = 0;
        }

        newLoss = state.cumulativeDailyLossInNumeraire + loss;

        // Check that the new daily loss is within the allowed limits
        require(
            newLoss <= state.maxDailyLossInNumeraire,
            AeraPeriphery__ExcessiveDailyLoss(newLoss, state.maxDailyLossInNumeraire)
        );
    }

    /// @notice Revert if slippage limit is exceeded for the trade
    /// @param state The state of the vault
    /// @param loss The loss incurred in the swap
    /// @param valueBefore The value before the swap
    function _enforceSlippageLimit(State storage state, uint256 loss, uint256 valueBefore) internal view {
        // Requirements: check that the slippage is within the allowed limits
        require(
            loss * MAX_BPS <= valueBefore * state.maxSlippagePerTrade,
            AeraPeriphery__ExcessiveSlippage(loss, valueBefore, state.maxSlippagePerTrade)
        );
    }

    /// @notice Convert an amount of tokens to numeraire
    /// @param amount The amount of tokens to convert
    /// @param token The address of the token to convert
    /// @return The amount in numeraire
    function _convertToNumeraire(uint256 amount, address token) internal view returns (uint256) {
        if (token == _getNumeraire()) {
            return amount;
        }

        IOracleRegistry oracleRegistry = _vaultStates[msg.sender].oracleRegistry;
        return IOracle(oracleRegistry).getQuote(amount, token, _getNumeraire());
    }
}
