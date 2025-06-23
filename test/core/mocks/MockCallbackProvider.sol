// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ICallbackRecipient } from "test/core/mocks/ICallbackRecipient.sol";
import { MockDynamicReturnValueReturner } from "test/core/mocks/MockDynamicReturnValueReturner.sol";

contract MockCallbackProvider {
    uint256 public constant STATIC_FIXED_RETURN = 4_125_124_412;
    bytes public constant STATIC_VARIABLE_RETURN = "variable bytes";

    MockDynamicReturnValueReturner public dynamicReturnValueReturner;

    error InvalidReturnValue();

    constructor() {
        dynamicReturnValueReturner = new MockDynamicReturnValueReturner();
    }

    function triggerCallbackWithStaticFixedReturn(bytes memory userData) external {
        uint256 returnValue = ICallbackRecipient(msg.sender).callbackWithStaticFixedReturn(userData);
        require(returnValue == STATIC_FIXED_RETURN, InvalidReturnValue());
    }

    function triggerCallbackWithStaticFixedReturnMultipleValues(bytes memory userData) external {
        (uint256 returnValue1, bytes32 returnValue2) =
            ICallbackRecipient(msg.sender).callbackWithStaticFixedReturnMultipleValues(userData);
        require(
            returnValue1 == STATIC_FIXED_RETURN && returnValue2 == bytes32(STATIC_FIXED_RETURN), InvalidReturnValue()
        );
    }

    function triggerCallbackWithStaticVariableReturn(bytes memory userData) external {
        bytes memory returnValue = ICallbackRecipient(msg.sender).callbackWithStaticVariableReturn(userData);
        require(keccak256(returnValue) == keccak256(STATIC_VARIABLE_RETURN), InvalidReturnValue());
    }

    function triggerCallbackWithStaticReturnMixedValuesFixedFirst(bytes memory userData) external {
        (uint256 returnValue1, bytes memory returnValue2) =
            ICallbackRecipient(msg.sender).callbackWithStaticReturnMixedValuesFixedFirst(userData);
        require(returnValue1 == STATIC_FIXED_RETURN, InvalidReturnValue());
        require(keccak256(returnValue2) == keccak256(STATIC_VARIABLE_RETURN), InvalidReturnValue());
    }

    function triggerCallbackWithStaticReturnMixedValuesVariableFirst(bytes memory userData) external {
        (bytes memory returnValue1, uint256 returnValue2) =
            ICallbackRecipient(msg.sender).callbackWithStaticReturnMixedValuesVariableFirst(userData);
        require(keccak256(returnValue1) == keccak256(STATIC_VARIABLE_RETURN), InvalidReturnValue());
        require(returnValue2 == STATIC_FIXED_RETURN, InvalidReturnValue());
    }

    function triggerCallbackWithDynamicFixedReturn(uint256 expectedValue, bytes memory userData) external {
        uint256 actualValue = ICallbackRecipient(msg.sender).callbackWithDynamicFixedReturn(userData);
        require(actualValue == expectedValue, InvalidReturnValue());
    }

    function triggerCallbackWithDynamicFixedReturnMultipleValues(
        uint256 expectedValue1,
        uint256 expectedValue2,
        bytes memory userData
    ) external {
        (uint256 actualValue1, uint256 actualValue2) =
            ICallbackRecipient(msg.sender).callbackWithDynamicFixedReturnMultipleValues(userData);
        require(actualValue1 == expectedValue1, InvalidReturnValue());
        require(actualValue2 == expectedValue2, InvalidReturnValue());
    }

    function triggerCallbackWithDynamicVariableReturn(bytes memory expectedValue, bytes memory userData) external {
        bytes memory actualValue = ICallbackRecipient(msg.sender).callbackWithDynamicVariableReturn(userData);
        require(keccak256(actualValue) == keccak256(expectedValue), InvalidReturnValue());
    }

    function triggerCallbackWithNoReturnWithOperations(bytes memory userData) external {
        ICallbackRecipient(msg.sender).callbackWithNoReturnWithOperations(userData);
    }

    function triggerCallbackWithNoReturnWithoutOperations() external {
        ICallbackRecipient(msg.sender).callbackWithNoReturnWithoutOperations();
    }
}
