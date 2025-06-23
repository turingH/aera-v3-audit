// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import { BaseVault } from "src/core/BaseVault.sol";
import { HookCallType } from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";

contract MockBaseVault is BaseVault {
    function setAndGetCurrentHookCallType(HookCallType hookCallType) external returns (HookCallType) {
        _setHookCallType(hookCallType);

        (bool success, bytes memory returnData) =
            address(this).delegatecall(abi.encodeWithSelector(IBaseVault.getCurrentHookCallType.selector));
        require(success, "Failed to get current hook call type");
        return HookCallType(abi.decode(returnData, (uint8)));
    }
}
