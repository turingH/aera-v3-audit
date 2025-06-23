// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import { AggregatorV3Interface } from "src/dependencies/chainlink/interfaces/AggregatorV3Interface.sol";
import { IOracle } from "src/dependencies/oracles/IOracle.sol";

contract MockChainlink7726Adapter is IOracle {
    mapping(address => mapping(address => address)) public baseQuoteFeed;

    function setFeed(address base, address quote, address feed) external {
        baseQuoteFeed[base][quote] = feed;
    }

    function getQuote(uint256 baseAmount, address base, address quote) external view returns (uint256 quoteAmount) {
        // 2. Pull the latest Chainlink data
        (, int256 answer,,,) = AggregatorV3Interface(baseQuoteFeed[base][quote]).latestRoundData();

        uint8 feedDecimals = AggregatorV3Interface(baseQuoteFeed[base][quote]).decimals();
        uint8 baseDecimals = IERC20Metadata(base).decimals();
        uint8 quoteDecimals = IERC20Metadata(quote).decimals();

        uint256 price = uint256(answer);

        quoteAmount = baseAmount * price * (10 ** quoteDecimals) / (10 ** (feedDecimals + baseDecimals));
    }
}
