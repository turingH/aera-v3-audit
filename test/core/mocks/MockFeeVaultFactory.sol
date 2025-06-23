// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { FeeVaultParameters } from "src/core/Types.sol";

import { MockBaseVaultFactory } from "test/core/mocks/MockBaseVaultFactory.sol";

contract MockFeeVaultFactory is MockBaseVaultFactory {
    FeeVaultParameters public feeVaultParameters;

    function setFeeVaultParameters(FeeVaultParameters memory params) internal {
        feeVaultParameters = params;
    }
}
