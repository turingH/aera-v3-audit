// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

contract MockDynamicReturnValueReturner {
    /// @notice Returns the static return values at the given indices
    /// @param returnValue The return value to return
    /// @return returnData The encoded return values
    function getFixedSizeReturnValue(uint256 returnValue) external pure returns (uint256) {
        return returnValue;
    }

    /// @notice Returns the static return values at the given indices
    /// @param returnValue1 The first return value to return
    /// @param returnValue2 The second return value to return
    /// @return returnData The encoded return values
    function getFixedSizeReturnValueMultipleValues(uint256 returnValue1, uint256 returnValue2)
        external
        pure
        returns (uint256, uint256)
    {
        return (returnValue1, returnValue2);
    }

    /// @notice Returns the static return values at the given indices
    /// @param returnData The encoded return values
    /// @return returnData The encoded return values
    function getVariableReturnValue(bytes memory returnData) external pure returns (bytes memory) {
        return returnData;
    }
}
