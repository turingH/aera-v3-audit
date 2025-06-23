// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { CalldataReader, CalldataReaderLib } from "src/core/libraries/CalldataReader.sol";

contract CalldataReaderTest is Test {
    function test_fuzz_readU208_success(bytes calldata data, uint8 readerIncrement) public pure {
        CalldataReader reader = CalldataReader.wrap(CalldataReaderLib.from(data).offset() + readerIncrement);
        (CalldataReader updatedReader, uint208 value) = reader.readU208();

        uint208 expectedValue;
        assembly ("memory-safe") {
            expectedValue := shr(48, calldataload(add(data.offset, readerIncrement)))
        }
        assertEq(value, expectedValue, "value != expectedValue");
        assertEq(updatedReader.offset(), reader.offset() + 26, "reader not updated");
    }

    function test_fuzz_readOptionalU256_success(bytes calldata data, uint8 readerIncrement) public pure {
        CalldataReader reader = CalldataReader.wrap(CalldataReaderLib.from(data).offset() + readerIncrement);
        (CalldataReader updatedReader, uint256 value) = reader.readOptionalU256();

        bool hasU256;
        uint256 expectedValue;
        assembly ("memory-safe") {
            hasU256 := gt(byte(0, calldataload(add(data.offset, readerIncrement))), 0)
        }

        if (hasU256) {
            assembly ("memory-safe") {
                expectedValue := calldataload(add(add(data.offset, readerIncrement), 1))
            }
        }
        uint256 expectedOffset = reader.offset() + 1 + (hasU256 ? 32 : 0);

        assertEq(value, expectedValue, "value != expectedValue");
        assertEq(updatedReader.offset(), expectedOffset, "reader not updated");
    }

    function test_fuzz_readBytes32Array_success(bytes calldata data, uint8 readerIncrement) public pure {
        CalldataReader reader = CalldataReader.wrap(CalldataReaderLib.from(data).offset() + readerIncrement);
        (CalldataReader updatedReader, bytes32[] memory array) = reader.readBytes32Array();

        uint256 expectedLength;
        assembly ("memory-safe") {
            expectedLength := shr(248, calldataload(add(data.offset, readerIncrement)))
        }

        bytes32[] memory expectedArray = new bytes32[](expectedLength);
        assembly ("memory-safe") {
            calldatacopy(add(expectedArray, 32), add(add(data.offset, readerIncrement), 1), mul(expectedLength, 32))
        }

        assertEq(array, expectedArray, "array != expectedArray");
        assertEq(updatedReader.offset(), reader.offset() + 1 + expectedLength * 32, "reader not updated");
    }

    function test_fuzz_readBytesEnd_success(bytes calldata data) public pure {
        CalldataReader reader = CalldataReader.wrap(CalldataReaderLib.from(data).offset());
        CalldataReader end = reader.readBytesEnd();

        assertEq(end.offset(), reader.offset() + data.length, "incorrect end");
    }

    function test_fuzz_readBytesEndWithData_success(bytes calldata data) public pure {
        CalldataReader reader = CalldataReader.wrap(CalldataReaderLib.from(data).offset());
        CalldataReader end = reader.readBytesEnd(data);

        assertEq(end.offset(), reader.offset() + data.length, "incorrect end");
    }

    function test_fuzz_readBytesToMemory_success(bytes calldata data, uint8 readerIncrement) public pure {
        CalldataReader reader = CalldataReader.wrap(CalldataReaderLib.from(data).offset() + readerIncrement);
        (CalldataReader updatedReader, bytes memory dataBytes) = reader.readBytesToMemory();

        uint256 expectedLength;
        assembly ("memory-safe") {
            expectedLength := shr(240, calldataload(add(data.offset, readerIncrement)))
        }

        bytes memory expectedDataBytes = new bytes(expectedLength);
        assembly ("memory-safe") {
            calldatacopy(add(expectedDataBytes, 32), add(add(data.offset, readerIncrement), 2), expectedLength)
        }

        assertEq(dataBytes, expectedDataBytes, "dataBytes != expectedDataBytes");
        assertEq(updatedReader.offset(), reader.offset() + expectedLength + 2, "reader not updated");
    }

    function test_fuzz_readBytesToMemoryWithLength_success(bytes calldata data, uint8 readerIncrement, uint16 length)
        public
        pure
    {
        CalldataReader reader = CalldataReader.wrap(CalldataReaderLib.from(data).offset() + readerIncrement);
        (CalldataReader updatedReader, bytes memory dataBytes) = reader.readBytesToMemory(length);

        bytes memory expectedDataBytes = new bytes(length);
        assembly ("memory-safe") {
            calldatacopy(add(expectedDataBytes, 32), add(data.offset, readerIncrement), length)
        }

        assertEq(dataBytes, expectedDataBytes, "dataBytes != expectedDataBytes");
        assertEq(updatedReader.offset(), reader.offset() + length, "reader not updated");
    }
}
