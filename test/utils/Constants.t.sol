// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

abstract contract Constants {
    uint40 internal constant _MAY_1_2024 = 1_714_521_600;

    uint256 internal constant ONE = 1e18;

    bytes32 internal constant RANDOM_BYTES32 = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    uint16 internal constant TVL_FEE = 100;
    uint16 internal constant PERFORMANCE_FEE = 1000;

    uint32 internal constant MAX_HEARTBEAT = 48 hours;
    uint256 internal constant ORACLE_UPDATE_DELAY = 21 days;
    uint256 internal constant SEQUENCER_GRACE_PERIOD = 1 hours;
    uint32 internal constant HEARTBEAT_CAP = 48 hours;
}
