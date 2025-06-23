// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { CCTPHooks } from "src/periphery/hooks/slippage/CCTPHooks.sol";

import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { KyberSwapDexHooks } from "src/periphery/hooks/slippage/KyberSwapDexHooks.sol";
import { OdosV2DexHooks } from "src/periphery/hooks/slippage/OdosV2DexHooks.sol";
import { UniswapV3DexHooks } from "src/periphery/hooks/slippage/UniswapV3DexHooks.sol";

contract StablecoinStrategyHooks is UniswapV3DexHooks, OdosV2DexHooks, KyberSwapDexHooks, CCTPHooks {
    constructor(address numeraire_) HasNumeraire(numeraire_) { }
}
