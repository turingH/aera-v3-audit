// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library LibPRNG {
    struct PRNG {
        uint256 state;
    }

    function seed(PRNG memory prng, uint256 state) internal pure {
        assembly ("memory-safe") {
            mstore(prng, state)
        }
    }

    function next(PRNG memory prng) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            result := keccak256(prng, 0x20)
            mstore(prng, result)
        }
    }
}
