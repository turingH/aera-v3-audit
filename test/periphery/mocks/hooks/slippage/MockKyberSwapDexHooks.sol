// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { KyberSwapDexHooks } from "src/periphery/hooks/slippage/KyberSwapDexHooks.sol";

contract MockKyberSwapDexHooks is KyberSwapDexHooks {
    constructor(address numeraire_) HasNumeraire(numeraire_) { }
}
