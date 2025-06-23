// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BaseVault } from "src/core/BaseVault.sol";
import { NO_CALLBACK_DATA } from "src/core/Constants.sol";
import { Approval, CallbackData } from "src/core/Types.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

contract MockCallbackHandler is BaseVault {
    error SubOperationFailed(bytes data);

    function doubleAllowCallback(bytes32 root, uint256 packedCallbackData) external {
        _allowCallback(root, packedCallbackData);
        _allowCallback(root, packedCallbackData);
    }

    function allowCallbackAndGetAllowedCallback(bytes32 root, uint256 packedCallbackData)
        external
        returns (address caller, bytes4 selector, uint16 userDataOffset)
    {
        _allowCallback(root, packedCallbackData);
        (caller, selector, userDataOffset) = _getAllowedCallback();
    }

    function storeAndFetchCallbackApprovals(Approval[] memory _approvals, uint256 length)
        external
        returns (Approval[] memory approvals)
    {
        _storeCallbackApprovals(_approvals, length);
        approvals = _getCallbackApprovals();
    }

    function storeTwiceAndFetchCallbackApprovals(
        Approval[] memory _approvals1,
        uint256 length1,
        Approval[] memory _approvals2,
        uint256 length2
    ) external returns (Approval[] memory approvals) {
        _storeCallbackApprovals(_approvals1, length1);
        _storeCallbackApprovals(_approvals2, length2);
        approvals = _getCallbackApprovals();
    }

    function packCallbackData(address caller, bytes4 selector, uint16 userDataOffset) external pure returns (uint256) {
        bytes memory packedCallbackDataBytes = Encoder.encodeCallbackData(
            CallbackData({ caller: caller, selector: selector, calldataOffset: userDataOffset })
        );

        return uint256(bytes32(packedCallbackDataBytes)) >> 48;
    }
}
