// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

contract MockForwarderTarget {
    uint256 public counter;
    bool public flag;

    error MockTarget__RevertFunction();

    function incrementCounter() external returns (uint256) {
        return ++counter;
    }

    function setFlag(bool _flag) external returns (bool) {
        flag = _flag;
        return flag;
    }

    function revertFunction() external pure {
        revert MockTarget__RevertFunction();
    }
}
