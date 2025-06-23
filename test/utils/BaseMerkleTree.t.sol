// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Encoder } from "test/core/utils/Encoder.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

abstract contract BaseMerkleTree {
    bytes32[] internal leaves;
    bytes32 internal root;

    function _getSimpleLeaf(address target, bytes4 selector) internal pure returns (bytes32) {
        return MerkleHelper.getLeaf({
            target: target,
            selector: selector,
            hasValue: false,
            configurableHooksOffsets: new uint16[](0),
            hooks: address(0),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: ""
        });
    }
}
