// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { MilkmanHooks } from "src/periphery/hooks/slippage/MilkmanHooks.sol";

contract MockMilkmanHooks is MilkmanHooks {
    constructor(address numeraire_) HasNumeraire(numeraire_) { }
}
