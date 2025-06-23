// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { stdError } from "forge-std/StdError.sol";
import { Test } from "forge-std/Test.sol";

import { Clipboard, Operation } from "src/core/Types.sol";

import { Pipeline } from "src/core/libraries/Pipeline.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { MockPipeline } from "test/core/mocks/MockPipeline.sol";
import { LibPRNG } from "test/core/utils/LibPRNG.sol";

contract PipelineTest is Test {
    using LibPRNG for LibPRNG.PRNG;

    uint256 internal constant MASK_8_BIT = 0xff;
    uint256 internal constant RESULTS_OFFSET = 248;
    uint256 internal constant COPY_OFFSET = 240;
    uint256 internal constant PASTE_OFFSET = 232;
    uint256 internal constant LENGTH_OFFSET = 240;
    uint256 internal constant CLIPBOARD_SIZE = 24;
    uint256 internal constant WORD_SIZE = 32;
    uint256 internal constant SELECTOR_SIZE = 4;
    uint256 internal constant STATIC_CALL_FLAG_SIZE = 8;

    bytes4 internal constant FUNC_SELECTOR = bytes4(keccak256("someFunc(address,uint256)"));

    MockPipeline public pipeline;

    mapping(uint256 offset => bool used) public _usedPasteOffsets;

    function setUp() public {
        pipeline = new MockPipeline();
    }

    function test_fuzz_pipe_success(uint8 resultsNum) public {
        resultsNum = uint8(bound(resultsNum, 1, 50));

        LibPRNG.PRNG memory prng;
        prng.seed(uint256(resultsNum));

        bytes[] memory results = _randomizeResults(prng, resultsNum);
        bytes memory operationCalldata = _randomizeCalldata(prng);
        Clipboard[] memory clipboards = _randomizeClipboard(prng, operationCalldata, results);

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(0xabcd),
            data: operationCalldata,
            clipboards: clipboards,
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        bytes memory callData = pipeline.pipe(Encoder.encodeOperations(operations), results);
        vm.snapshotGasLastCall("pipe - success");

        _assertPipeline(results, operations[0].clipboards, operations[0].data, callData);
    }

    function test_pipe_revertsWith_ResultIndexOutOfBounds() public {
        uint8 resultsNum = 1;
        LibPRNG.PRNG memory prng;
        prng.seed(uint256(resultsNum));

        bytes[] memory results = _randomizeResults(prng, resultsNum);
        bytes memory operationCalldata = _randomizeCalldata(prng);

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(0xabcd),
            data: operationCalldata,
            clipboards: Encoder.makeClipboardArray(1, 0, 0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        vm.expectRevert(stdError.indexOOBError);
        pipeline.pipe(Encoder.encodeOperations(operations), results);
    }

    function test_pipe_revertsWith_CopyOffsetOutOfBounds() public {
        uint8 resultsNum = 1;
        LibPRNG.PRNG memory prng;
        prng.seed(uint256(resultsNum));

        bytes[] memory results = _randomizeResults(prng, resultsNum);
        bytes memory operationCalldata = _randomizeCalldata(prng);

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(0xabcd),
            data: operationCalldata,
            clipboards: Encoder.makeClipboardArray(0, uint8(results[0].length / 32 + 1), 0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        vm.expectRevert(Pipeline.Aera__CopyOffsetOutOfBounds.selector);
        pipeline.pipe(Encoder.encodeOperations(operations), results);
    }

    function test_pipe_revertsWith_PasteOffsetOutOfBounds() public {
        uint8 resultsNum = 1;
        LibPRNG.PRNG memory prng;
        prng.seed(uint256(resultsNum));

        bytes[] memory results = _randomizeResults(prng, resultsNum);
        bytes memory operationCalldata = _randomizeCalldata(prng);

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(0xabcd),
            data: operationCalldata,
            clipboards: Encoder.makeClipboardArray(0, 0, uint16(operationCalldata.length - 31)),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        vm.expectRevert(Pipeline.Aera__PasteOffsetOutOfBounds.selector);
        pipeline.pipe(Encoder.encodeOperations(operations), results);
    }

    function _assertPipeline(
        bytes[] memory results,
        Clipboard[] memory clipboards,
        bytes memory startCallData,
        bytes memory endCallData
    ) internal pure {
        uint256 clipboardCount = clipboards.length;

        for (uint256 i = 0; i < clipboardCount; ++i) {
            bytes32 copiedBytes = _slice(results[clipboards[i].resultIndex], clipboards[i].copyWord * WORD_SIZE);

            _paste(startCallData, clipboards[i].pasteOffset, copiedBytes);
        }

        assertEq(startCallData, endCallData);
    }

    function _paste(bytes memory callData, uint256 pasteOffset, bytes32 pastedBytes) internal pure {
        assembly ("memory-safe") {
            mstore(add(add(callData, 36), pasteOffset), pastedBytes)
        }
    }

    function _randomizeClipboard(LibPRNG.PRNG memory prng, bytes memory operationCalldata, bytes[] memory results)
        internal
        pure
        returns (Clipboard[] memory)
    {
        uint256 pipeNumber = prng.next() % 10 + 1;

        Clipboard[] memory clipboards = new Clipboard[](pipeNumber);

        for (uint256 i = 0; i < pipeNumber; ++i) {
            uint8 resultIndex = uint8(prng.next() % results.length);
            uint8 copyWord = uint8(prng.next() % (results[resultIndex].length / 32));
            uint16 pasteOffset = uint16(prng.next() % ((operationCalldata.length - SELECTOR_SIZE - 32)));

            clipboards[i] = Clipboard({ resultIndex: resultIndex, copyWord: copyWord, pasteOffset: pasteOffset });
        }

        return clipboards;
    }

    function _randomizeCalldata(LibPRNG.PRNG memory prng) internal pure returns (bytes memory) {
        uint256 operationCalldataLength = prng.next() % 1024;
        bytes memory data = new bytes(operationCalldataLength);
        for (uint256 i = 0; i < operationCalldataLength; ++i) {
            uint256 word = prng.next();
            assembly ("memory-safe") {
                mstore(add(add(data, 32), mul(i, 32)), word)
            }
        }

        return abi.encodePacked(FUNC_SELECTOR, data);
    }

    uint256 internal constant MAX_WORDS_IN_RESULT = 64;

    function _randomizeResults(LibPRNG.PRNG memory prng, uint8 resultsNum)
        internal
        pure
        returns (bytes[] memory results)
    {
        results = new bytes[](resultsNum);

        for (uint256 i = 0; i < resultsNum; ++i) {
            uint256 wordsInResults = prng.next() % 64 + 1;
            bytes memory result = new bytes(wordsInResults * 32);
            for (uint256 j = 0; j < wordsInResults; ++j) {
                uint256 word = prng.next();
                assembly ("memory-safe") {
                    mstore(add(add(result, 32), mul(j, 32)), word)
                }
            }

            results[i] = result;
        }
    }

    function _slice(bytes memory data, uint256 start) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            result := mload(add(add(data, 32), start))
        }
    }
}
