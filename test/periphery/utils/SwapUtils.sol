// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Vm } from "forge-std/Vm.sol";

import { IOracle } from "src/dependencies/oracles/IOracle.sol";
import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";

library SwapUtils {
    function maxBps() internal pure returns (uint256) {
        return 10_000;
    }

    /// @notice Apply loss to an amount
    /// @param amount The amount to apply loss to (either token price or token amount)
    /// @param fee The fee to apply
    /// @param slippage The slippage to apply
    /// @return The amount after applying loss
    function applyLossToAmount(uint256 amount, uint24 fee, uint256 slippage) internal pure returns (uint256) {
        return amount * (maxBps() - (uint256(fee) + slippage)) / maxBps();
    }

    /// @notice Apply gain to an amount
    /// @param amount The amount to apply gain to (either token price or token amount)
    /// @param fee The fee to apply
    /// @param slippage The slippage to apply
    /// @return The amount after applying gain
    function applyGainToAmount(uint256 amount, uint24 fee, uint256 slippage) internal pure returns (uint256) {
        return amount * (maxBps() + uint256(fee) + slippage) / maxBps();
    }

    /// @notice Calculate the slippage during output swaps
    /// @param inputValue The value of the input token
    /// @param outputValue The value of the output token
    /// @return The slippage during output swaps
    function calculateInputSlippage(uint256 inputValue, uint256 outputValue) internal pure returns (uint256) {
        return ((inputValue - outputValue) * maxBps()) / outputValue;
    }

    /// @notice Calculate the slippage during output swaps
    /// @param inputValue The value of the input token
    /// @param outputValue The value of the output token
    /// @return The slippage during output swaps
    function calculateOutputSlippage(uint256 inputValue, uint256 outputValue) internal pure returns (uint256) {
        return ((outputValue - inputValue) * maxBps()) / inputValue;
    }

    /// @notice Calculate the callback offset for the uniswapV3SwapCallback function
    /// @return The callback offset for the uniswapV3SwapCallback function
    function callbackOffset_uniswapV3SwapCallback() internal pure returns (uint16) {
        // function uniswapV3SwapCallback(int256 amount0Delta,int256 amount1Delta,bytes calldata data)
        return 4 + 32 * 2;
    }

    /// @notice Encode a path for a multi-hop swap
    /// @param tokens The addresses of the tokens in the path
    /// @param fees The fees for each hop
    /// @return The encoded path
    function encodePath(address[] memory tokens, uint24[] memory fees) internal pure returns (bytes memory) {
        require(tokens.length >= 2 && tokens.length - 1 == fees.length, "Invalid path");

        bytes memory path = new bytes(0);
        for (uint256 i = 0; i < fees.length; i++) {
            path = bytes.concat(path, abi.encodePacked(tokens[i], fees[i]));
        }
        // Encode the final token without any fee
        path = bytes.concat(path, abi.encodePacked(tokens[tokens.length - 1]));

        return path;
    }

    /// @notice Encode a path for a single-hop swap
    /// @param tokenIn The address of the input token
    /// @param fee The fee for the hop
    /// @param tokenOut The address of the output token
    /// @return The encoded path
    function encodePath(address tokenIn, uint24 fee, address tokenOut) internal pure returns (bytes memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = tokenIn;
        tokens[1] = tokenOut;

        uint24[] memory fees = new uint24[](1);
        fees[0] = fee;

        return SwapUtils.encodePath(tokens, fees);
    }

    /// @notice Mock the OracleRegistry getQuote function
    /// @param registry The address of the OracleRegistry
    /// @param baseAmount The amount of the base token
    /// @param baseToken The address of the base token
    /// @param quoteToken The address of the quote token (numeraire)
    /// @param quoteAmount The amount of the quote token (numeraire)
    function mock_OracleRegistry_GetQuote(
        Vm vm,
        address registry,
        uint256 baseAmount,
        address baseToken,
        address quoteToken,
        uint256 quoteAmount
    ) internal {
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IOracle.getQuote.selector, baseAmount, baseToken, quoteToken),
            abi.encode(quoteAmount)
        );
    }

    function mock_OracleRegistry_GetQuoteForVault(
        Vm vm,
        address registry,
        uint256 baseAmount,
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        address vault
    ) internal {
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IOracleRegistry.getQuoteForUser.selector, baseAmount, baseToken, quoteToken, vault),
            abi.encode(quoteAmount)
        );
    }
}
