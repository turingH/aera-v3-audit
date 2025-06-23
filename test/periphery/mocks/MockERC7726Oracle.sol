// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IOracle } from "src/dependencies/oracles/IOracle.sol";

contract MockERC7726Oracle is IOracle {
    mapping(address => mapping(address => uint256)) public priceRatios;
    mapping(address => mapping(address => bool)) public supportedPairs;

    error OracleUnsupportedPair(address base, address quote);
    error OracleUntrustedData(address base, address quote);

    function setQuoteRatio(address base, address quote, uint256 ratio) external {
        priceRatios[base][quote] = ratio;
        supportedPairs[base][quote] = true;
    }

    function removePairSupport(address base, address quote) external {
        supportedPairs[base][quote] = false;
    }

    function getQuote(uint256 baseAmount, address base, address quote) external view returns (uint256 quoteAmount) {
        require(supportedPairs[base][quote], OracleUnsupportedPair(base, quote));

        uint256 ratio = priceRatios[base][quote];
        require(ratio != 0, OracleUntrustedData(base, quote));

        return baseAmount * ratio;
    }
}
