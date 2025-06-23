// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import { Sweepable } from "src/core/Sweepable.sol";

contract SweepableMock is Sweepable {
    constructor(address owner_) Sweepable(owner_, Authority(address(0))) { }
}
