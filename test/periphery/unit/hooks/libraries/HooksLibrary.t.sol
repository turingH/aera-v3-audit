// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { HookCallType } from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";
import { HooksLibrary } from "src/periphery/libraries/HooksLibrary.sol";

contract HooksLibraryTest is Test {
    function test_isBeforeHook(uint8 hookCallType) public {
        vm.assume(hookCallType < 3);
        vm.mockCall(
            msg.sender, abi.encodeWithSelector(IBaseVault.getCurrentHookCallType.selector), abi.encode(hookCallType)
        );
        assertEq(HooksLibrary.isBeforeHook(), HookCallType(hookCallType) == HookCallType.BEFORE);
    }

    function test_isAfterHook(uint8 hookCallType) public {
        vm.assume(hookCallType < 3);
        vm.mockCall(
            msg.sender, abi.encodeWithSelector(IBaseVault.getCurrentHookCallType.selector), abi.encode(hookCallType)
        );
        assertEq(HooksLibrary.isAfterHook(), HookCallType(hookCallType) == HookCallType.AFTER);
    }
}
