// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// Sampled from
// https://github.com/odos-xyz/odos-router-v2/blob/7d23f6caf406a4751e70947b5f16f46d59d97125/contracts/OdosRouterV2.sol

interface IOdosRouterV2 {
    /// @dev Contains all information needed to describe the input and output for a swap
    struct SwapTokenInfo {
        address inputToken;
        uint256 inputAmount;
        address inputReceiver;
        address outputToken;
        uint256 outputQuote;
        uint256 outputMin;
        address outputReceiver;
    }

    /// @notice Externally facing interface for swapping two tokens
    /// @param tokenInfo All information about the tokens being swapped
    /// @param pathDefinition Encoded path definition for executor
    /// @param executor Address of contract that will execute the path
    /// @param referralCode referral code to specify the source of the swap
    function swap(
        SwapTokenInfo calldata tokenInfo,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable returns (uint256 amountOut);
}
