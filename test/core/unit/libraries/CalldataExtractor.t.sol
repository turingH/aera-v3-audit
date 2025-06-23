// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { CalldataExtractor } from "src/core/libraries/CalldataExtractor.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { LibPRNG } from "test/core/utils/LibPRNG.sol";

contract CalldataExtractorTest is Test {
    using LibPRNG for LibPRNG.PRNG;
    using CalldataExtractor for bytes;

    ////////////////////////////////////////////////////////////
    //                        extract                         //
    ////////////////////////////////////////////////////////////

    function test_extract_success_oneInstruction() public {
        bytes memory callData =
            hex"00000000123456789abcdeffedcba9876543210effedcba987654321effedcba987654321effedcba9876543217654321eff7654321eff7654321eff";

        uint16[] memory configurableHooksOffsets = Encoder.makeExtractOffsetsArray(16);
        uint256 calldataOffsetsPacked = Encoder.packExtractionOffsets(configurableHooksOffsets);

        bytes memory expected = hex"ffedcba987654321effedcba987654321effedcba9876543217654321eff7654";

        vm.startSnapshotGas("extract - success - one instruction");
        bytes memory result = callData.extract(calldataOffsetsPacked, configurableHooksOffsets.length);
        vm.stopSnapshotGas();
        assertEq(result, expected);
    }

    function test_extract_success_threeInstructions() public {
        bytes memory callData =
            hex"00000000123456789abcdeff123456789abcdeff56789abcdeff56789abcdeff789abcdeff789abcdeff789abcdeff789abcdeff789abcdeffeff789abcdeff789abcdeff789abcdeff789abeff789abcdeff789abcdeff789abcdeff789ab";

        uint16[] memory configurableHooksOffsets = Encoder.makeExtractOffsetsArray(16, 10, 1);
        uint256 calldataOffsetsPacked = Encoder.packExtractionOffsets(configurableHooksOffsets);

        bytes memory expected =
            hex"56789abcdeff56789abcdeff789abcdeff789abcdeff789abcdeff789abcdeff56789abcdeff56789abcdeff56789abcdeff789abcdeff789abcdeff789abcde3456789abcdeff123456789abcdeff56789abcdeff56789abcdeff789abcdeff";

        vm.startSnapshotGas("extract - success - three instructions");
        bytes memory result = callData.extract(calldataOffsetsPacked, configurableHooksOffsets.length);
        vm.stopSnapshotGas();
        assertEq(result, expected);
    }

    function test_extract_success_tenInstructions() public {
        bytes memory callData =
            hex"00000000123456789abcdeffedcba9876543210effedcba987654321effedcba987654321effedcba9876543217654321eff7654321eff7654321eff123456789abcdeffedcba9876dcba987654321effedcba987687654321effedcba987654321effedcba9876543217654";
        uint16[] memory configurableHooksOffsets = new uint16[](10);
        for (uint256 i = 0; i < configurableHooksOffsets.length; ++i) {
            configurableHooksOffsets[i] = uint16(i);
        }
        uint256 calldataOffsetsPacked = Encoder.packExtractionOffsets(configurableHooksOffsets);
        bytes memory expected =
            hex"123456789abcdeffedcba9876543210effedcba987654321effedcba987654323456789abcdeffedcba9876543210effedcba987654321effedcba987654321e56789abcdeffedcba9876543210effedcba987654321effedcba987654321eff789abcdeffedcba9876543210effedcba987654321effedcba987654321effed9abcdeffedcba9876543210effedcba987654321effedcba987654321effedcbbcdeffedcba9876543210effedcba987654321effedcba987654321effedcba9deffedcba9876543210effedcba987654321effedcba987654321effedcba987ffedcba9876543210effedcba987654321effedcba987654321effedcba98765edcba9876543210effedcba987654321effedcba987654321effedcba9876543cba9876543210effedcba987654321effedcba987654321effedcba987654321";

        vm.startSnapshotGas("extract - success - ten instructions");
        bytes memory result = callData.extract(calldataOffsetsPacked, configurableHooksOffsets.length);
        vm.stopSnapshotGas();
        assertEq(result, expected);
    }

    function test_fuzz_extract_success_randomOffsets(
        bytes memory callData,
        uint256 calldataOffsetsPacked,
        uint8 calldataOffsetsCount
    ) public {
        CalldataExtractorTestHelper helper = new CalldataExtractorTestHelper();

        if (calldataOffsetsCount > 16) {
            vm.expectRevert(CalldataExtractor.Aera__ExtractionNumberTooLarge.selector);
            helper.extract(callData, calldataOffsetsPacked, calldataOffsetsCount);
            return;
        }
        if (callData.length < 36) {
            vm.expectRevert(CalldataExtractor.Aera__CalldataTooShort.selector);
            helper.extract(callData, calldataOffsetsPacked, calldataOffsetsCount);
            return;
        }

        for (uint256 i = 0; i < calldataOffsetsCount; ++i) {
            uint256 offset = (type(uint16).max & (calldataOffsetsPacked >> (240 - i * 16))) + 4;

            if (offset > callData.length - 32) {
                vm.expectRevert(CalldataExtractor.Aera__OffsetOutOfBounds.selector);
                helper.extract(callData, calldataOffsetsPacked, calldataOffsetsCount);
                return;
            }
        }

        bytes memory result = callData.extract(calldataOffsetsPacked, calldataOffsetsCount);
        _assertValidExtracts(callData, calldataOffsetsPacked, calldataOffsetsCount, result);
    }

    function test_fuzz_extract_success_onlyValidOffsets(bytes memory callData, uint256 seed) public pure {
        vm.assume(callData.length > 36);

        LibPRNG.PRNG memory prng;
        prng.seed(seed);

        (uint256 calldataOffsetsPacked, uint256 calldataOffsetsCount) = _randomizePackedOffsets(prng, callData);

        bytes memory result = callData.extract(calldataOffsetsPacked, calldataOffsetsCount);
        _assertValidExtracts(callData, calldataOffsetsPacked, calldataOffsetsCount, result);
    }

    function _randomizePackedOffsets(LibPRNG.PRNG memory prng, bytes memory callData)
        internal
        pure
        returns (uint256, uint256 calldataOffsetsCount)
    {
        uint256 maxOffset = callData.length - 36;

        uint256 maxInstructions = 16;

        calldataOffsetsCount = prng.next() % maxInstructions + 1;

        uint16[] memory offsets = new uint16[](calldataOffsetsCount);
        for (uint256 i = 0; i < calldataOffsetsCount; i++) {
            uint256 offset = prng.next() % maxOffset;
            offsets[i] = uint16(offset);
        }

        return (Encoder.packExtractionOffsets(offsets), calldataOffsetsCount);
    }

    function _assertValidExtracts(
        bytes memory callData,
        uint256 calldataOffsetsPacked,
        uint256 calldataOffsetsCount,
        bytes memory result
    ) internal pure {
        assertEq(result.length, calldataOffsetsCount * 32);

        uint256 resultPtr = 0;
        for (uint256 i = 0; i < calldataOffsetsCount; ++i) {
            uint256 offset = (type(uint16).max & (calldataOffsetsPacked >> (240 - i * 16))) + 4;

            bytes32 expectedValue;
            assembly ("memory-safe") {
                expectedValue := mload(add(add(callData, 0x20), offset))
            }
            bytes32 extractedValue;
            assembly ("memory-safe") {
                extractedValue := mload(add(add(result, 0x20), resultPtr))
            }
            assertEq(extractedValue, expectedValue);

            resultPtr += 32;
        }
    }
}

contract CalldataExtractorTestHelper {
    using CalldataExtractor for bytes;

    /// @dev Helper needed because library reverts in pure functions
    /// are considered internal calls. Testing framework can only detect
    /// reverts from external calls. This wrapper creates the necessary
    /// external call context to properly test library revert conditions
    // solhint-disable-next-line foundry-test-functions
    function extract(bytes memory callData, uint256 offsets, uint256 count) external pure returns (bytes memory) {
        return callData.extract(offsets, count);
    }
}
