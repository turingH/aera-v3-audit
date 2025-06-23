// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";

import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

/// @title IMilkmanHooks
/// @notice Interface for Milkman hooks
interface IMilkmanHooks is IBaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    error AeraPeriphery__InvalidPriceChecker(address validPriceChecker, address invalidPriceChecker);
    error AeraPeriphery__InvalidVaultInPriceCheckerData(address vault, address priceCheckerDataVault);

    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Hook function matching MilkmanRouter `requestSell` signature
    /// @dev Should only be used as a before hook
    /// @param sellAmount The amount of the sell token to swap
    /// @param sellToken The address of the sell token
    /// @param receiveToken The address of the receive token
    /// @param priceChecker The address of the price checker
    /// @param priceCheckerData The data for the price checker - (address vault)
    /// @return The encoded parameters for verification - (tokenIn, tokenOut)
    function requestSell(
        uint256 sellAmount,
        IERC20 sellToken,
        IERC20 receiveToken,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external returns (bytes memory);
}
