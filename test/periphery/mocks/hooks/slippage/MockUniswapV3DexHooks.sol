// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { UniswapV3DexHooks } from "src/periphery/hooks/slippage/UniswapV3DexHooks.sol";

contract MockUniswapV3DexHooks is UniswapV3DexHooks {
    constructor(address numeraire_) HasNumeraire(numeraire_) { }
}
