// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseSlippageHooks } from "src/periphery/hooks/slippage/BaseSlippageHooks.sol";
import { ICCTPHooks } from "src/periphery/interfaces/hooks/slippage/ICCTPHooks.sol";

/// @title CCTPHooks
/// @notice Implements custom hook logic for CCTPv2 bridging. Adds safety checks for slippage, daily loss limits, and
/// ensures destination caller is unset before allowing a cross-chain token transfer
abstract contract CCTPHooks is ICCTPHooks, BaseSlippageHooks {
    ////////////////////////////////////////////////////////////
    //              External / Public Functions               //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc ICCTPHooks
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 /* minFinalityThreshold */
    ) external returns (bytes memory returnData) {
        // Requirements: check that destinationCaller is not set
        require(destinationCaller == bytes32(0), AeraPeriphery__DestinationCallerNotZero());

        if (maxFee > 0) {
            // Interactions: call oracle registry to calculate source amount in numeraire
            uint256 sourceAmountInNumeraire = _convertToNumeraire(amount, burnToken);

            // Interactions: call oracle registry to calculate destination amount in numeraire
            uint256 destinationAmountInNumeraire = _convertToNumeraire(amount - maxFee, burnToken);

            // Requirements: enforce bridge slippage and daily loss
            _enforceSlippageLimitAndDailyLossLog(
                msg.sender, burnToken, burnToken, sourceAmountInNumeraire, destinationAmountInNumeraire
            );
        }

        returnData = abi.encode(destinationDomain, address(uint160(uint256(mintRecipient))), burnToken);
    }
}
