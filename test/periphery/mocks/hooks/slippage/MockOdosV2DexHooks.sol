// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { OdosV2DexHooks } from "src/periphery/hooks/slippage/OdosV2DexHooks.sol";

contract MockOdosV2DexHooks is OdosV2DexHooks {
    constructor(address numeraire_) HasNumeraire(numeraire_) { }
}
