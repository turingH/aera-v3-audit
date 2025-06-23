// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";
import { SwapUtils } from "test/periphery/utils/SwapUtils.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

contract TestForkBaseHooks is BaseTest {
    function _getExpectedUsdcOutput(
        address oracleRegistry,
        address weth,
        address usdc,
        uint256 ethAmount,
        uint256 slippageBps
    ) internal view returns (uint256) {
        // Get oracle rate for ETH -> USDC
        uint256 currentRate = IOracleRegistry(oracleRegistry).getQuote(ethAmount, weth, usdc);

        // Apply slippage and convert to USDC decimals
        return SwapUtils.applyLossToAmount(currentRate, 0, slippageBps);
    }

    function _checkInnerHooksError(bytes memory err, bytes4 expectedSelector) internal pure {
        // Extract inner error selector
        // - skip first 4 bytes of outer error
        // - skip 32 bytes of operationIndex
        // - skip 32 bytes of result offset
        // - skip 32 bytes of result length
        bytes4 innerSelector;
        assembly {
            innerSelector := mload(add(add(err, 0x64), 0x20))
        }
        assertEq(innerSelector, expectedSelector, "Wrong inner error");
    }
}
