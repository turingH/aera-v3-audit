// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

contract MockRevertableBeforeAfterHooks {
    bool public isAfterHook;

    mapping(bytes4 => bytes) public result;

    function setResult(bytes4 selector, bytes memory data) public {
        result[selector] = data;
    }

    // solhint-disable-next-line ordering
    fallback(bytes calldata) external returns (bytes memory) {
        if (isAfterHook) {
            revert("REASON");
        }

        isAfterHook = true;
        return abi.encode(result[msg.sig]);
    }
}
