// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

interface ICallbackRecipient {
    function callbackWithStaticFixedReturn(bytes memory data) external returns (uint256);
    function callbackWithStaticFixedReturnMultipleValues(bytes memory data) external returns (uint256, bytes32);
    function callbackWithStaticVariableReturn(bytes memory data) external returns (bytes memory);
    function callbackWithStaticReturnMixedValuesVariableFirst(bytes memory data)
        external
        returns (bytes memory, uint256);
    function callbackWithStaticReturnMixedValuesFixedFirst(bytes memory data)
        external
        returns (uint256, bytes memory);

    function callbackWithDynamicFixedReturn(bytes memory data) external returns (uint256);
    function callbackWithDynamicFixedReturnMultipleValues(bytes memory data) external returns (uint256, uint256);
    function callbackWithDynamicVariableReturn(bytes memory data) external returns (bytes memory);
    function callbackWithNoReturnWithOperations(bytes memory data) external;
    function callbackWithNoReturnWithoutOperations() external;
}
