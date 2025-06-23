// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BaseSlippageHooks } from "src/periphery/hooks/slippage/BaseSlippageHooks.sol";

import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { HooksLibrary } from "src/periphery/libraries/HooksLibrary.sol";

contract MockBaseSlippageHooks is BaseSlippageHooks {
    constructor(address _numeraire) HasNumeraire(_numeraire) { }

    function setVaultState(address vault, State memory state) public {
        _vaultStates[vault] = state;
    }
}
