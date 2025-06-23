// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { CallbackData, Clipboard, Operation, ReturnValueType } from "src/core/Types.sol";

/* solhint-disable */

/// @title Encoder Library
/// @notice Library for encoding Operation structs into compact calldata bytes
/// @notice For off-chain use
library Encoder {
    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    /// @notice Thrown when trying to access an operation index that doesn't exist
    error IndexOutOfBounds();
    /// @notice Thrown when a paste offset is too large to fit in 16 bits
    error PasteOffsetDoesntFitIn16Bits();
    /// @notice Thrown when trying to calculate paste offset for non-existent operation
    error OperationNotFound();

    /// @notice Mask for a bit indicating whether a hooks has before submit call
    uint256 internal constant BEFORE_HOOK_MASK = 1;

    /// @notice Mask for a bit indicating whether a hooks has after submit call
    uint256 internal constant AFTER_HOOK_MASK = 2;

    ////////////////////////////////////////////////////////////
    //              Private / Internal Functions              //
    ////////////////////////////////////////////////////////////

    /// @notice Encodes an array of Operation structs into a compact bytes format
    /// @param operations Array of Operation structs to encode
    /// @return Encoded bytes representing the operations
    /// @dev Packs operation data in the following format:
    //  [ operationsLength : 1 byte ]
    //  for each operation:
    //      [ target          : 20 bytes ]
    //      [ calldataLength : 2 bytes ]
    //      [ calldata        : *calldataLength* bytes ]
    //
    //      [ clipboardsLength : 1 byte ]
    //
    //      for each clipboard entry:
    //          [ resultIndex : 1 byte ]
    //          [ copyWord    : 1 byte ]
    //          [ pasteOffset : 2 bytes ]
    //
    //      [ isStaticCall  : 1 byte ]
    //
    //      if isStaticCall == 0:
    //          [ hasCallback  : 1 byte ]
    //
    //          if hasCallback == 1:
    //              [ callbackData  : 26 bytes]
    //              // structure:
    //              //   [ selector(4) + calldataOffset(2) + caller(20) ]
    //
    //          [ hookConfig   : 1 byte ]
    //          // structure:
    //          //   [ hasHook(1 bit) + configurableHooksOffsetsLength(7 bits) ]
    //
    //          if configurable_hooks_offsets_length > 0:
    //              [ configurable_hooks_offsets : 32 bytes ]
    //          if has_hook == 1:
    //              [ hook     : 20 bytes ]
    //
    //          [ proofLength  : 1 byte ]
    //          [ proof        : proofLength * 32 bytes ]
    //
    //          [ hasValue     : 1 byte ]
    //          if hasValue == 1:
    //              [ value     : 32 bytes ]
    function encodeOperations(Operation[] memory operations) internal pure returns (bytes memory) {
        return _encodeOperations(operations);
    }

    /// @notice Encodes an array of Operation structs into a compact bytes format
    /// @dev Callback operations are like regular operations, but with a return value
    /// @param operations Array of Operation structs to encode
    /// @param returnValueType The type of return value
    /// @param returnValue The return value
    /// @return Encoded bytes representing the operations
    function encodeCallbackOperations(
        Operation[] memory operations,
        ReturnValueType returnValueType,
        bytes memory returnValue
    ) internal pure returns (bytes memory) {
        bytes memory data = _encodeOperations(operations);

        data = encodeReturnValue(data, returnValueType, returnValue);

        return data;
    }

    function _encodeOperations(Operation[] memory operations) private pure returns (bytes memory) {
        bytes memory data = encodeOperationsLength(operations);
        for (uint256 i = 0; i < operations.length; ++i) {
            Operation memory operation = operations[i];
            data = encodeTarget(data, operation);

            data = encodeCalldata(data, operation);

            data = encodeClipboards(data, operation);

            bool isStaticCall;
            (data, isStaticCall) = encodeIsStaticCall(data, operation);

            if (isStaticCall) {
                continue;
            }

            data = encodeCallback(data, operation);

            data = encodeHooks(data, operation);

            data = encodeProof(data, operation);

            data = encodeValue(data, operation);
        }

        return data;
    }

    function encodeOperationsLength(Operation[] memory operations) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(operations.length));
    }

    function encodeTarget(bytes memory data, Operation memory operation) internal pure returns (bytes memory) {
        return abi.encodePacked(data, operation.target);
    }

    function encodeCalldata(bytes memory data, Operation memory operation) internal pure returns (bytes memory) {
        return abi.encodePacked(data, uint16(operation.data.length), operation.data);
    }

    function encodeClipboards(bytes memory data, Operation memory operation) internal pure returns (bytes memory) {
        data = abi.encodePacked(data, uint8(operation.clipboards.length));
        for (uint256 i = 0; i < operation.clipboards.length; ++i) {
            data = abi.encodePacked(
                data,
                operation.clipboards[i].resultIndex,
                operation.clipboards[i].copyWord,
                operation.clipboards[i].pasteOffset
            );
        }
        return data;
    }

    function encodeIsStaticCall(bytes memory data, Operation memory operation)
        internal
        pure
        returns (bytes memory, bool)
    {
        data = abi.encodePacked(data, operation.isStaticCall);
        return (data, operation.isStaticCall);
    }

    function encodeCallback(bytes memory data, Operation memory operation) internal pure returns (bytes memory) {
        if (operation.callbackData.caller != address(0)) {
            return abi.encodePacked(data, true, encodeCallbackData(operation.callbackData));
        }
        return abi.encodePacked(data, false);
    }

    /// @notice Encodes callback data into bytes
    /// @param callbackData The callback data struct to encode
    /// @return Encoded callback data bytes
    /// @dev Packs selector (4 bytes), offset (2 bytes), and caller address (20 bytes)
    function encodeCallbackData(CallbackData memory callbackData) internal pure returns (bytes memory) {
        return abi.encodePacked(callbackData.selector, callbackData.calldataOffset, callbackData.caller);
    }

    /// @notice Encodes extractor configuration for an operation
    /// @param data Bytes memory to encode into
    /// @param operation Operation struct to encode
    /// @return Encoded extractor configuration bytes
    /// @dev If using custom extractor, returns max uint8 + extractor address
    /// @dev Otherwise returns array length + offset array
    function encodeHooks(bytes memory data, Operation memory operation) internal pure returns (bytes memory) {
        uint16[] memory configurableHooksOffsets = operation.configurableHooksOffsets;
        address hooks = operation.hooks;

        require(
            configurableHooksOffsets.length == 0 || !_hasBeforeSubmitHooks(hooks),
            "No before submit hooks allowed with configurable hooks"
        );
        require(
            hooks == address(0) || _hasBeforeSubmitHooks(hooks) || _hasAfterSubmitHooks(hooks),
            "Hooks must be either before submit or after submit hooks"
        );

        require(configurableHooksOffsets.length < 17, "Too many configurable hooks offsets");

        uint8 hooksConfig = uint8(configurableHooksOffsets.length);
        if (hooks != address(0)) {
            hooksConfig |= 1 << 7;
        }

        data = abi.encodePacked(data, hooksConfig);

        if (configurableHooksOffsets.length > 0) {
            data = abi.encodePacked(data, packExtractionOffsets(configurableHooksOffsets));
        }

        if (hooks != address(0)) {
            data = abi.encodePacked(data, hooks);
        }

        return data;
    }

    function encodeProof(bytes memory data, Operation memory operation) internal pure returns (bytes memory) {
        data = abi.encodePacked(data, uint8(operation.proof.length));
        for (uint256 i = 0; i < operation.proof.length; ++i) {
            data = abi.encodePacked(data, operation.proof[i]);
        }
        return data;
    }

    function encodeValue(bytes memory data, Operation memory operation) internal pure returns (bytes memory) {
        if (operation.value != 0) {
            return abi.encodePacked(data, true, operation.value);
        }
        return abi.encodePacked(data, false);
    }

    function encodeReturnValue(bytes memory data, ReturnValueType returnValueType, bytes memory returnValue)
        internal
        pure
        returns (bytes memory)
    {
        if (returnValueType == ReturnValueType.STATIC_RETURN) {
            return abi.encodePacked(data, uint8(returnValueType), uint16(returnValue.length), returnValue);
        } else if (returnValueType == ReturnValueType.DYNAMIC_RETURN) {
            return abi.encodePacked(data, uint8(returnValueType));
        }
        return abi.encodePacked(data, uint8(ReturnValueType.NO_RETURN));
    }

    function _hasBeforeSubmitHooks(address hooks) internal pure returns (bool) {
        return uint160(hooks) & BEFORE_HOOK_MASK != 0;
    }

    function _hasAfterSubmitHooks(address hooks) internal pure returns (bool) {
        return uint160(hooks) & AFTER_HOOK_MASK != 0;
    }

    /// @notice Creates a Clipboard array with a single entry
    /// @param resultIndex Index of the operation result to copy from
    /// @param copyWord Word index to copy from the result
    /// @param pasteOffset Offset where to paste the copied word
    /// @return Single-element Clipboard array
    function makeClipboardArray(uint8 resultIndex, uint8 copyWord, uint16 pasteOffset)
        internal
        pure
        returns (Clipboard[] memory)
    {
        Clipboard[] memory clipboards = new Clipboard[](1);
        clipboards[0] = Clipboard({ resultIndex: resultIndex, copyWord: copyWord, pasteOffset: pasteOffset });
        return clipboards;
    }

    /// @notice Creates a Clipboard array with two entries
    /// @param resultIndex1 First operation result index
    /// @param copyWord1 First word index to copy
    /// @param pasteOffset1 First paste offset
    /// @param resultIndex2 Second operation result index
    /// @param copyWord2 Second word index to copy
    /// @param pasteOffset2 Second paste offset
    /// @return Two-element Clipboard array
    function makeClipboardArray(
        uint8 resultIndex1,
        uint8 copyWord1,
        uint16 pasteOffset1,
        uint8 resultIndex2,
        uint8 copyWord2,
        uint16 pasteOffset2
    ) internal pure returns (Clipboard[] memory) {
        Clipboard[] memory clipboards = new Clipboard[](2);
        clipboards[0] = Clipboard({ resultIndex: resultIndex1, copyWord: copyWord1, pasteOffset: pasteOffset1 });
        clipboards[1] = Clipboard({ resultIndex: resultIndex2, copyWord: copyWord2, pasteOffset: pasteOffset2 });
        return clipboards;
    }

    /// @notice Creates an empty CallbackData struct
    /// @return Empty CallbackData with zero values
    function emptyCallbackData() internal pure returns (CallbackData memory) {
        return CallbackData({ caller: address(0), selector: bytes4(0), calldataOffset: 0 });
    }

    /// @notice Creates an array with a single extract offset
    /// @param offset The offset value
    /// @return Single-element uint16 array
    function makeExtractOffsetsArray(uint16 offset) internal pure returns (uint16[] memory) {
        uint16[] memory offsets = new uint16[](1);
        offsets[0] = offset;
        return offsets;
    }

    /// @notice Creates an array with two extract offsets
    /// @param offset1 First offset value
    /// @param offset2 Second offset value
    /// @return Two-element uint16 array
    function makeExtractOffsetsArray(uint16 offset1, uint16 offset2) internal pure returns (uint16[] memory) {
        uint16[] memory offsets = new uint16[](2);
        offsets[0] = offset1;
        offsets[1] = offset2;
        return offsets;
    }

    /// @notice Creates an array with three extract offsets
    /// @param offset1 First offset value
    /// @param offset2 Second offset value
    /// @param offset3 Third offset value
    /// @return Three-element uint16 array
    function makeExtractOffsetsArray(uint16 offset1, uint16 offset2, uint16 offset3)
        internal
        pure
        returns (uint16[] memory)
    {
        uint16[] memory offsets = new uint16[](3);
        offsets[0] = offset1;
        offsets[1] = offset2;
        offsets[2] = offset3;
        return offsets;
    }

    /// @notice Creates an array with four extract offsets
    /// @param offset1 First offset value
    /// @param offset2 Second offset value
    /// @param offset3 Third offset value
    /// @param offset4 Fourth offset value
    /// @return Four-element uint16 array
    function makeExtractOffsetsArray(uint16 offset1, uint16 offset2, uint16 offset3, uint16 offset4)
        internal
        pure
        returns (uint16[] memory)
    {
        uint16[] memory offsets = new uint16[](4);
        offsets[0] = offset1;
        offsets[1] = offset2;
        offsets[2] = offset3;
        offsets[3] = offset4;
        return offsets;
    }

    /// @notice Creates an array with five extract offsets
    /// @param offset1 First offset value
    /// @param offset2 Second offset value
    /// @param offset3 Third offset value
    /// @param offset4 Fourth offset value
    /// @param offset5 Fifth offset value
    /// @return Five-element uint16 array
    function makeExtractOffsetsArray(uint16 offset1, uint16 offset2, uint16 offset3, uint16 offset4, uint16 offset5)
        internal
        pure
        returns (uint16[] memory)
    {
        uint16[] memory offsets = new uint16[](5);
        offsets[0] = offset1;
        offsets[1] = offset2;
        offsets[2] = offset3;
        offsets[3] = offset4;
        offsets[4] = offset5;
        return offsets;
    }

    /// @notice Creates an array with six extract offsets
    /// @param offset1 First offset value
    /// @param offset2 Second offset value
    /// @param offset3 Third offset value
    /// @param offset4 Fourth offset value
    /// @param offset5 Fifth offset value
    /// @param offset6 Sixth offset value
    /// @return Six-element uint16 array
    function makeExtractOffsetsArray(
        uint16 offset1,
        uint16 offset2,
        uint16 offset3,
        uint16 offset4,
        uint16 offset5,
        uint16 offset6
    ) internal pure returns (uint16[] memory) {
        uint16[] memory offsets = new uint16[](6);
        offsets[0] = offset1;
        offsets[1] = offset2;
        offsets[2] = offset3;
        offsets[3] = offset4;
        offsets[4] = offset5;
        offsets[5] = offset6;
        return offsets;
    }

    /// @notice Creates an array with seven extract offsets
    /// @param offset1 First offset value
    /// @param offset2 Second offset value
    /// @param offset3 Third offset value
    /// @param offset4 Fourth offset value
    /// @param offset5 Fifth offset value
    /// @param offset6 Sixth offset value
    /// @param offset7 Seventh offset value
    /// @return Seven-element uint16 array
    function makeExtractOffsetsArray(
        uint16 offset1,
        uint16 offset2,
        uint16 offset3,
        uint16 offset4,
        uint16 offset5,
        uint16 offset6,
        uint16 offset7
    ) internal pure returns (uint16[] memory) {
        uint16[] memory offsets = new uint16[](7);
        offsets[0] = offset1;
        offsets[1] = offset2;
        offsets[2] = offset3;
        offsets[3] = offset4;
        offsets[4] = offset5;
        offsets[5] = offset6;
        offsets[6] = offset7;
        return offsets;
    }

    /// @notice Calculates the paste offset for a specific word in an operation's calldata
    /// @param data The encoded operations bytes
    /// @param operationIndex Index of the operation to calculate offset for
    /// @param pasteWord The word index within the operation's calldata
    /// @return The calculated paste offset as a uint16
    /// @dev Traverses the encoded data to find the correct operation and calculates byte offset
    /// @dev Reverts if operation index is out of bounds or offset doesn't fit in uint16
    function calculatePasteOffset(bytes memory data, uint256 operationIndex, uint256 pasteWord)
        internal
        pure
        returns (uint16)
    {
        uint256 dataPtr;
        uint256 cursor;
        assembly ("memory-safe") {
            dataPtr := data
            cursor := add(dataPtr, 32)
        }

        uint256 operationsLength;
        assembly ("memory-safe") {
            operationsLength := shr(248, mload(cursor))
            cursor := add(cursor, 1)
        }

        require(operationIndex < operationsLength, IndexOutOfBounds());

        for (uint256 i = 0; i < operationsLength; ++i) {
            cursor += 20;

            uint256 callDataLength;
            assembly ("memory-safe") {
                callDataLength := shr(240, mload(cursor))
                cursor := add(cursor, 2)
            }

            if (i == operationIndex) {
                uint256 pasteOffset = cursor + 4 + pasteWord * 32 - dataPtr;
                bytes32 value;
                address valueBeforeWord;
                assembly ("memory-safe") {
                    value := mload(add(pasteOffset, dataPtr))
                    valueBeforeWord := mload(sub(add(pasteOffset, dataPtr), 32))
                }

                require(pasteOffset <= type(uint16).max, PasteOffsetDoesntFitIn16Bits());

                return uint16(pasteOffset);
            }

            cursor += callDataLength;

            bool isStaticCall;
            assembly ("memory-safe") {
                isStaticCall := shr(248, mload(cursor))
                cursor := add(cursor, 1)
            }
            if (isStaticCall) {
                continue;
            }

            cursor += 26;

            uint8 extractorType;
            assembly ("memory-safe") {
                extractorType := shr(248, mload(cursor))
                cursor := add(cursor, 1)
            }
            if (extractorType == type(uint8).max) {
                cursor += 20;
            } else if (extractorType > 0) {
                cursor += 2 * extractorType;
            }

            uint256 proofLength;
            assembly ("memory-safe") {
                proofLength := shr(248, mload(cursor))
                cursor := add(cursor, 1)
            }

            cursor += proofLength * 32;

            cursor += 20;

            cursor += 32;
        }

        revert OperationNotFound();
    }

    /// @notice Decodes bytes back into an array of Operation structs
    /// @param data The encoded bytes to decode
    /// @return operations Array of decoded Operation structs
    /// @dev Reverses the encoding process from encodeOperations
    function decodeOperations(bytes memory data) internal pure returns (Operation[] memory) {
        (Operation[] memory operations,) = _decodeOperations(data);
        return operations;
    }

    /// @notice Decodes the return value from the encoded data
    /// @param data The encoded bytes to decode
    /// @return returnValueType The type of return value
    /// @return returnValue The decoded return value
    function decodeReturnValue(bytes memory data)
        internal
        pure
        returns (ReturnValueType returnValueType, bytes memory returnValue)
    {
        // Use _decodeOperations to get the cursor at the end of operations
        (, uint256 cursor) = _decodeOperations(data);

        // Now we're at the return value type
        uint8 returnTypeFlag;
        assembly ("memory-safe") {
            returnTypeFlag := shr(248, mload(cursor))
            cursor := add(cursor, 1)
        }
        returnValueType = ReturnValueType(returnTypeFlag);

        // Read return value based on type
        if (returnValueType == ReturnValueType.STATIC_RETURN) {
            // Read the length prefix first (uint16)
            uint16 length;
            assembly ("memory-safe") {
                length := shr(240, mload(cursor))
                cursor := add(cursor, 2)
            }

            // Now read exactly 'length' bytes
            returnValue = new bytes(length);
            assembly ("memory-safe") {
                mcopy(add(returnValue, 32), cursor, length)
            }
        } else {
            // For other types, return empty bytes
            returnValue = new bytes(0);
        }

        return (returnValueType, returnValue);
    }

    function _decodeOperations(bytes memory data) internal pure returns (Operation[] memory, uint256) {
        uint256 cursor;
        assembly ("memory-safe") {
            cursor := add(data, 32)
        }

        // Read number of operations
        uint256 operationsLength;
        assembly ("memory-safe") {
            operationsLength := shr(248, mload(cursor))
            cursor := add(cursor, 1)
        }

        Operation[] memory operations = new Operation[](operationsLength);

        // Decode each operation
        for (uint256 i = 0; i < operationsLength; ++i) {
            (cursor, operations[i].target) = _decodeTarget(cursor);

            (cursor, operations[i].data) = _decodeCalldata(cursor);

            (cursor, operations[i].clipboards) = _decodeClipboards(cursor);

            (cursor, operations[i].isStaticCall) = _decodeIsStaticCall(cursor);

            if (operations[i].isStaticCall) {
                continue;
            }

            (cursor, operations[i].callbackData) = _parseCallbackData(cursor);

            // Read hooks config
            (cursor, operations[i].configurableHooksOffsets, operations[i].hooks) = _decodeHooks(cursor);

            // Read proof if present
            (cursor, operations[i].proof) = _decodeProof(cursor);

            // Read value if present
            (cursor, operations[i].value) = _decodeValue(cursor);
        }

        return (operations, cursor);
    }

    function _parseCallbackData(uint256 cursor) internal pure returns (uint256, CallbackData memory callbackData) {
        bool hasCallbackData;
        assembly ("memory-safe") {
            hasCallbackData := shr(248, mload(cursor))
            cursor := add(cursor, 1)
        }

        if (hasCallbackData) {
            bytes4 selector;
            uint16 calldataOffset;
            address callerAddress;
            uint256 callbackDataPacked;
            assembly ("memory-safe") {
                callbackDataPacked := shr(48, mload(cursor))
                cursor := add(cursor, 26)
                callerAddress := callbackDataPacked
                selector := shl(48, callbackDataPacked)
                calldataOffset := and(shr(160, callbackDataPacked), 0xFFFF)
            }
            callbackData = CallbackData({ selector: selector, calldataOffset: calldataOffset, caller: callerAddress });
        }

        return (cursor, callbackData);
    }

    /// @notice Packs an array of 2-byte offsets into a single uint256
    /// @param offsets Array of uint16 offsets to pack
    /// @return packed Single uint256 containing all packed offsets
    /// @dev Each offset takes 16 bits, starting from the most significant bits
    function packExtractionOffsets(uint16[] memory offsets) internal pure returns (uint256 packed) {
        for (uint256 i = 0; i < offsets.length; ++i) {
            packed |= uint256(offsets[i]) << (240 - i * 16);
        }
        return packed;
    }

    function _decodeTarget(uint256 cursor) internal pure returns (uint256 newCursor, address target) {
        assembly ("memory-safe") {
            target := shr(96, mload(cursor))
            newCursor := add(cursor, 20)
        }
    }

    function _decodeCalldata(uint256 cursor) internal pure returns (uint256, bytes memory data) {
        uint256 length;
        assembly ("memory-safe") {
            length := shr(240, mload(cursor))
            cursor := add(cursor, 2)
        }
        data = new bytes(length);
        assembly ("memory-safe") {
            mcopy(add(data, 32), cursor, length)
            cursor := add(cursor, length)
        }

        return (cursor, data);
    }

    function _decodeClipboards(uint256 cursor) internal pure returns (uint256, Clipboard[] memory clipboards) {
        uint256 length;
        assembly ("memory-safe") {
            length := shr(248, mload(cursor))
            cursor := add(cursor, 1)
        }

        clipboards = new Clipboard[](length);
        for (uint256 j = 0; j < length; ++j) {
            uint8 resultIndex;
            uint8 copyWord;
            uint16 pasteOffset;
            assembly ("memory-safe") {
                resultIndex := shr(248, mload(cursor))
                cursor := add(cursor, 1)
                copyWord := shr(248, mload(cursor))
                cursor := add(cursor, 1)
                pasteOffset := shr(240, mload(cursor))
                cursor := add(cursor, 2)
            }
            clipboards[j] = Clipboard({ resultIndex: resultIndex, copyWord: copyWord, pasteOffset: pasteOffset });
        }

        return (cursor, clipboards);
    }

    function _decodeIsStaticCall(uint256 cursor) internal pure returns (uint256 newCursor, bool isStaticCall) {
        assembly ("memory-safe") {
            isStaticCall := shr(248, mload(cursor))
            newCursor := add(cursor, 1)
        }
    }

    function _decodeValue(uint256 cursor) internal pure returns (uint256 newCursor, uint256 value) {
        bool hasValue;
        assembly ("memory-safe") {
            hasValue := shr(248, mload(cursor))
            cursor := add(cursor, 1)
        }

        if (hasValue) {
            assembly ("memory-safe") {
                value := mload(cursor)
                newCursor := add(cursor, 32)
            }
        }
    }

    function _decodeProof(uint256 cursor) internal pure returns (uint256, bytes32[] memory proof) {
        uint256 proofLength;
        assembly ("memory-safe") {
            proofLength := shr(248, mload(cursor))
            cursor := add(cursor, 1)
        }

        if (proofLength > 0) {
            proof = new bytes32[](proofLength);
            for (uint256 j = 0; j < proofLength; ++j) {
                assembly ("memory-safe") {
                    mstore(add(proof, add(32, mul(j, 32))), mload(cursor))
                    cursor := add(cursor, 32)
                }
            }
        }

        return (cursor, proof);
    }

    function _decodeHooks(uint256 cursor) internal pure returns (uint256, uint16[] memory offsets, address hooks) {
        uint8 hooksConfig;
        assembly ("memory-safe") {
            hooksConfig := shr(248, mload(cursor))
            cursor := add(cursor, 1)
        }

        bool hasHooks = (hooksConfig & (1 << 7)) != 0;
        uint8 numOffsets = hooksConfig & 0x7F;

        if (numOffsets > 0) {
            offsets = new uint16[](numOffsets);
            uint256 calldataOffsetsPacked;
            assembly ("memory-safe") {
                calldataOffsetsPacked := mload(cursor)
                cursor := add(cursor, 32)
            }
            for (uint256 j = 0; j < numOffsets; ++j) {
                offsets[j] = uint16(calldataOffsetsPacked >> (240 - j * 16));
            }
        }

        if (hasHooks) {
            assembly ("memory-safe") {
                hooks := shr(96, mload(cursor))
                cursor := add(cursor, 20)
            }
        }

        return (cursor, offsets, hooks);
    }
}
/* solhint-enable */
