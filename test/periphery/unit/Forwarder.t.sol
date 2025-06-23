// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import { TargetCalldata } from "src/core/Types.sol";
import { Forwarder } from "src/periphery/Forwarder.sol";
import { IForwarder } from "src/periphery/interfaces/IForwarder.sol";
import { MockForwarderTarget } from "test/periphery/mocks/MockForwarderTarget.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract ForwarderTest is BaseTest {
    Forwarder public forwarder;
    MockForwarderTarget public mockTarget;

    bytes4 public constant INCREMENT_COUNTER_SELECTOR = MockForwarderTarget.incrementCounter.selector;
    bytes4 public constant SET_FLAG_SELECTOR = MockForwarderTarget.setFlag.selector;
    bytes4 public constant REVERT_FUNCTION_SELECTOR = MockForwarderTarget.revertFunction.selector;
    bytes4 public constant ADD_CALLER_CAPABILITY_SELECTOR = Forwarder.addCallerCapability.selector;
    bytes4 public constant REMOVE_CALLER_CAPABILITY_SELECTOR = Forwarder.removeCallerCapability.selector;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(users.owner);
        forwarder = new Forwarder(users.owner, Authority(address(0)));

        mockTarget = new MockForwarderTarget();
    }

    ////////////////////////////////////////////////////////////
    //                       Deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public {
        Forwarder _forwarder = new Forwarder(users.owner, Authority(address(0xabcd)));
        vm.snapshotGasLastCall("deployment - success");

        assertEq(_forwarder.owner(), users.owner);
        assertEq(address(_forwarder.authority()), address(0xabcd));
    }

    ////////////////////////////////////////////////////////////
    //                        execute                         //
    ////////////////////////////////////////////////////////////

    function test_execute_revertsWith_Unauthorized() public {
        TargetCalldata[] memory operations =
            _createOperation(address(mockTarget), abi.encodeWithSelector(INCREMENT_COUNTER_SELECTOR));

        vm.expectRevert(
            abi.encodeWithSelector(
                IForwarder.AeraPeriphery__Unauthorized.selector,
                users.stranger,
                address(mockTarget),
                INCREMENT_COUNTER_SELECTOR
            )
        );

        vm.prank(users.stranger);
        forwarder.execute(operations);
    }

    function test_execute_revertsWith_targetReverting() public {
        _setCallerCapability(users.stranger, address(mockTarget), REVERT_FUNCTION_SELECTOR, true);

        TargetCalldata[] memory operations =
            _createOperation(address(mockTarget), abi.encodeWithSelector(REVERT_FUNCTION_SELECTOR));

        vm.expectRevert(MockForwarderTarget.MockTarget__RevertFunction.selector);

        vm.prank(users.stranger);
        forwarder.execute(operations);
    }

    function test_execute_success_singleOperation() public {
        _setCallerCapability(users.stranger, address(mockTarget), INCREMENT_COUNTER_SELECTOR, true);

        TargetCalldata[] memory operations =
            _createOperation(address(mockTarget), abi.encodeWithSelector(INCREMENT_COUNTER_SELECTOR));

        vm.expectEmit({ emitter: address(forwarder) });
        emit IForwarder.Executed(users.stranger, operations);

        vm.prank(users.stranger);
        forwarder.execute(operations);
        vm.snapshotGasLastCall("execute - success - single operation");

        assertEq(mockTarget.counter(), 1);
    }

    function test_execute_success_multipleOperations() public {
        _setCallerCapability(users.stranger, address(mockTarget), INCREMENT_COUNTER_SELECTOR, true);
        _setCallerCapability(users.stranger, address(mockTarget), SET_FLAG_SELECTOR, true);

        address[] memory targets = new address[](2);
        targets[0] = address(mockTarget);
        targets[1] = address(mockTarget);

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSelector(INCREMENT_COUNTER_SELECTOR);
        datas[1] = abi.encodeWithSelector(SET_FLAG_SELECTOR, true);

        TargetCalldata[] memory operations = _createMultipleOperations(targets, datas);

        vm.expectEmit({ emitter: address(forwarder) });
        emit IForwarder.Executed(users.stranger, operations);

        vm.prank(users.stranger);
        forwarder.execute(operations);
        vm.snapshotGasLastCall("execute - success - multiple operations");

        assertEq(mockTarget.counter(), 1);
        assertTrue(mockTarget.flag());
    }

    ////////////////////////////////////////////////////////////
    //                 addCallerCapability                    //
    ////////////////////////////////////////////////////////////

    function test_addCallerCapability_revertsWith_Unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");

        vm.prank(users.stranger);
        forwarder.addCallerCapability(users.alice, address(mockTarget), INCREMENT_COUNTER_SELECTOR);
    }

    function test_addCallerCapability_success() public {
        vm.expectEmit({ emitter: address(forwarder) });
        emit IForwarder.CallerCapabilityAdded(users.alice, address(mockTarget), INCREMENT_COUNTER_SELECTOR);

        vm.prank(users.owner);
        forwarder.addCallerCapability(users.alice, address(mockTarget), INCREMENT_COUNTER_SELECTOR);
        vm.snapshotGasLastCall("addCallerCapability - success - enable");

        assertTrue(forwarder.canCall(users.alice, address(mockTarget), INCREMENT_COUNTER_SELECTOR));
    }

    ////////////////////////////////////////////////////////////
    //                removeCallerCapability                  //
    ////////////////////////////////////////////////////////////

    function test_removeCallerCapability_revertsWith_Unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");

        vm.prank(users.stranger);
        forwarder.removeCallerCapability(users.alice, address(mockTarget), INCREMENT_COUNTER_SELECTOR);
    }

    function test_removeCallerCapability_success() public {
        vm.expectEmit({ emitter: address(forwarder) });
        emit IForwarder.CallerCapabilityRemoved(users.alice, address(mockTarget), INCREMENT_COUNTER_SELECTOR);

        vm.prank(users.owner);
        forwarder.removeCallerCapability(users.alice, address(mockTarget), INCREMENT_COUNTER_SELECTOR);
        vm.snapshotGasLastCall("removeCallerCapability - success - enable");

        assertFalse(forwarder.canCall(users.alice, address(mockTarget), INCREMENT_COUNTER_SELECTOR));
    }

    ////////////////////////////////////////////////////////////
    //                   Utility Functions                    //
    ////////////////////////////////////////////////////////////

    function _createOperation(address target, bytes memory data)
        internal
        pure
        returns (TargetCalldata[] memory operations)
    {
        operations = new TargetCalldata[](1);
        operations[0] = TargetCalldata({ target: target, data: data });
    }

    function _createMultipleOperations(address[] memory targets, bytes[] memory datas)
        internal
        pure
        returns (TargetCalldata[] memory operations)
    {
        require(targets.length == datas.length, "Invalid input arrays");

        operations = new TargetCalldata[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            operations[i] = TargetCalldata({ target: targets[i], data: datas[i] });
        }
    }

    function _setCallerCapability(address caller, address target, bytes4 sig, bool enabled) internal {
        vm.prank(users.owner);

        if (enabled) {
            forwarder.addCallerCapability(caller, target, sig);
        } else {
            forwarder.removeCallerCapability(caller, target, sig);
        }
    }
}
