// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IOracle } from "src/dependencies/oracles/IOracle.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

abstract contract BaseOracleRegistryTest is BaseTest {
    function _mockGetQuote(IOracle oracle, uint256 baseAmount, address base, address quote, uint256 quoteAmount)
        internal
    {
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IOracle.getQuote.selector, baseAmount, base, quote),
            abi.encode(quoteAmount)
        );
    }
}
