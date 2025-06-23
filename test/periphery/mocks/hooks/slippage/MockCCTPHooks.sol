// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { CCTPHooks } from "src/periphery/hooks/slippage/CCTPHooks.sol";

contract MockCCTPHooks is CCTPHooks {
    constructor(address numeraire_) HasNumeraire(numeraire_) { }
}
