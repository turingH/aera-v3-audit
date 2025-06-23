// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { CallbackData, Clipboard, Operation, ReturnValueType } from "src/core/Types.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { LibPRNG } from "test/core/utils/LibPRNG.sol";

contract EncoderTest is Test {
    using LibPRNG for LibPRNG.PRNG;

    /// @notice Maximum number of operations to generate
    uint256 internal constant MAX_OPERATIONS = 20;
    /// @notice Maximum length of operation calldata in bytes
    uint256 internal constant MAX_CALLDATA_LENGTH = 1000;
    /// @notice Maximum number of clipboard entries per operation
    uint256 internal constant MAX_CLIPBOARDS = 20;
    /// @notice Maximum number of extract offsets per operation
    uint256 internal constant MAX_EXTRACT_OFFSETS = 16;
    /// @notice Maximum number of proof elements per operation
    uint256 internal constant MAX_PROOF_ELEMENTS = 20;

    function test_fuzz_decodeOperations_success(uint256 seed) public view {
        LibPRNG.PRNG memory prng;
        prng.seed(seed);

        Operation[] memory operations = new Operation[](prng.next() % MAX_OPERATIONS);
        for (uint256 i = 0; i < operations.length; i++) {
            operations[i] = _randomizeOperation(prng);
        }

        bytes memory encoded = Encoder.encodeOperations(operations);
        Operation[] memory decoded = Encoder.decodeOperations(encoded);
        assertEq(decoded.length, operations.length, "operations length mismatch");
        for (uint256 i = 0; i < operations.length; i++) {
            assertEq(decoded[i].target, operations[i].target, "Target mismatch");

            assertEq(decoded[i].data, operations[i].data, "Data mismatch");

            assertEq(decoded[i].clipboards.length, operations[i].clipboards.length, "Clipboards length mismatch");

            for (uint256 j = 0; j < operations[i].clipboards.length; j++) {
                assertEq(
                    decoded[i].clipboards[j].resultIndex,
                    operations[i].clipboards[j].resultIndex,
                    "Clipboard resultIndex mismatch"
                );
                assertEq(
                    decoded[i].clipboards[j].copyWord,
                    operations[i].clipboards[j].copyWord,
                    "Clipboard copyWord mismatch"
                );
                assertEq(
                    decoded[i].clipboards[j].pasteOffset,
                    operations[i].clipboards[j].pasteOffset,
                    "Clipboard pasteOffset mismatch"
                );
            }
            assertEq(decoded[i].isStaticCall, operations[i].isStaticCall, "isStaticCall mismatch");
            if (operations[i].isStaticCall) {
                continue;
            }

            assertEq(
                decoded[i].callbackData.selector, operations[i].callbackData.selector, "Callback selector mismatch"
            );
            assertEq(
                decoded[i].callbackData.calldataOffset,
                operations[i].callbackData.calldataOffset,
                "Callback offset mismatch"
            );
            assertEq(decoded[i].callbackData.caller, operations[i].callbackData.caller, "Callback caller mismatch");

            assertEq(
                decoded[i].configurableHooksOffsets.length,
                operations[i].configurableHooksOffsets.length,
                "Extract offsets length mismatch"
            );
            for (uint256 j = 0; j < operations[i].configurableHooksOffsets.length; j++) {
                assertEq(
                    decoded[i].configurableHooksOffsets[j],
                    operations[i].configurableHooksOffsets[j],
                    "Extract offset mismatch"
                );
            }
            assertEq(decoded[i].proof.length, operations[i].proof.length, "Proof length mismatch");
            for (uint256 j = 0; j < operations[i].proof.length; j++) {
                assertEq(decoded[i].proof[j], operations[i].proof[j], "Proof element mismatch");
            }
            assertEq(decoded[i].hooks, operations[i].hooks, "Hooks mismatch");
            assertEq(decoded[i].value, operations[i].value, "Value mismatch");
        }
    }

    function test_fuzz_decodeReturnValue_success(uint256 seed) public view {
        LibPRNG.PRNG memory prng;
        prng.seed(seed);

        uint256 maxOperations = 3;

        Operation[] memory operations = new Operation[](prng.next() % maxOperations);
        for (uint256 i = 0; i < operations.length; i++) {
            operations[i] = _randomizeOperation(prng);
        }

        ReturnValueType returnValueType = ReturnValueType(prng.next() % 3);
        bytes memory returnValue =
            returnValueType == ReturnValueType.STATIC_RETURN ? vm.randomBytes(prng.next() % 100) : bytes("");

        bytes memory encodedReturnValue = Encoder.encodeCallbackOperations(operations, returnValueType, returnValue);

        (ReturnValueType decodedReturnType, bytes memory decodedReturnValue) =
            Encoder.decodeReturnValue(encodedReturnValue);
        assertEq(uint8(decodedReturnType), uint8(returnValueType), "Return value type mismatch");
        assertEq(decodedReturnValue, returnValue, "Return value mismatch");
    }

    function _randomizeOperation(LibPRNG.PRNG memory prng) internal view returns (Operation memory operation) {
        operation.target = address(uint160(prng.next()));
        operation.data = vm.randomBytes(prng.next() % MAX_CALLDATA_LENGTH);

        uint256 clipboardsNum = prng.next() % MAX_CLIPBOARDS;
        operation.clipboards = new Clipboard[](clipboardsNum);
        for (uint256 i = 0; i < clipboardsNum; i++) {
            operation.clipboards[i] = Clipboard({
                resultIndex: uint8(prng.next()),
                copyWord: uint8(prng.next()),
                pasteOffset: uint16(prng.next())
            });
        }
        operation.isStaticCall = prng.next() % 2 == 0;

        if (operation.isStaticCall) {
            return operation;
        }

        operation.callbackData = CallbackData({
            selector: bytes4(uint32(prng.next())),
            calldataOffset: uint16(prng.next()),
            caller: address(uint160(prng.next()))
        });

        if (prng.next() % 2 == 0) {
            operation.configurableHooksOffsets = new uint16[](0);
        } else {
            uint256 extractOffsetsNum = prng.next() % MAX_EXTRACT_OFFSETS;
            operation.configurableHooksOffsets = new uint16[](extractOffsetsNum);
            for (uint256 i = 0; i < extractOffsetsNum; i++) {
                operation.configurableHooksOffsets[i] = uint16(prng.next());
            }
        }

        uint256 proofNum = prng.next() % MAX_PROOF_ELEMENTS;
        operation.proof = new bytes32[](proofNum);
        for (uint256 i = 0; i < proofNum; i++) {
            operation.proof[i] = bytes32(prng.next());
        }

        operation.hooks = address(uint160(prng.next()));
        if (operation.configurableHooksOffsets.length > 0) {
            operation.hooks = address((uint160(operation.hooks) >> 1) << 1);
        }
        if (!_hasBeforeHooks(operation.hooks) && !_hasAfterHooks(operation.hooks)) {
            operation.hooks = address(uint160(operation.hooks) | 2);
        }
        operation.value = prng.next();

        return operation;
    }

    function _hasBeforeHooks(address hooks_) internal pure returns (bool) {
        return uint160(hooks_) & 1 == 1;
    }

    function _hasAfterHooks(address hooks_) internal pure returns (bool) {
        return uint160(hooks_) & 2 == 2;
    }
}
