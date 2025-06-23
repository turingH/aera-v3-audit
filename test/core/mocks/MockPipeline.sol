// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Operation } from "src/core/Types.sol";

import { CalldataReader, CalldataReaderLib } from "src/core/libraries/CalldataReader.sol";
import { Pipeline } from "src/core/libraries/Pipeline.sol";

contract MockPipeline {
    using Pipeline for bytes;

    function pipe(bytes calldata operations, bytes[] memory results) external pure returns (bytes memory) {
        CalldataReader reader = CalldataReaderLib.from(operations);

        uint256 operationsLength;
        (reader, operationsLength) = reader.readU8();

        if (operationsLength != 1) revert("MockPipeline: operationsLength != 1");

        address target;
        (reader, target) = reader.readAddr();

        bytes memory callData;
        (reader, callData) = reader.readBytesToMemory();

        callData.pipe(reader, results);

        return callData;
    }
}
