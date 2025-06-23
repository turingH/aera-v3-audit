// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";

import { MarketParams } from "test/dependencies/interfaces/morpho/IMorpho.sol";
import { IOracle } from "test/dependencies/interfaces/morpho/IOracle.sol";

contract HelperCalculator {
    function calculateBorrowAmount(MarketParams memory marketParams, uint256 totalCollateralAmount, address priceOracle)
        external
        view
        returns (uint256)
    {
        // Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36
        // It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
        // 10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
        // decimals of precision
        uint256 price = IOracle(priceOracle).price();

        uint256 maxBorrow = totalCollateralAmount * price / 1e36;

        // Scale by LLTV (91.5% for WBTC/WETH) + safety margin (95% of max to avoid liquidation)
        return (maxBorrow * marketParams.lltv * 95) / (1e18 * 100);
    }

    function calculateFlashAmount(uint256 wethAmount, address priceOracle) external view returns (uint256) {
        uint256 price = IOracle(priceOracle).price();

        // If price is 25e36 (25 WETH/BTC)
        // and wethAmount = 20e18 WETH
        // Then for 2x leverage we need: (2 * 20e18 * 1e36) / 25e36 = 1.6e8 WBTC

        return (wethAmount * 1e36 * 2) / price;
    }
}
