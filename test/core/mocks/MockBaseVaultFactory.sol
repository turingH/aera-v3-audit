// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BaseVaultParameters } from "src/core/Types.sol";

import { Test } from "forge-std/Test.sol";
import { IBaseVaultFactory } from "src/core/interfaces/IBaseVaultFactory.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

contract MockBaseVaultFactory is Test {
    BaseVaultParameters public parameters;
    address public guardian;

    function baseVaultParameters() public view returns (BaseVaultParameters memory) {
        return parameters;
    }

    function setGuardian(address guardian_) public {
        guardian = guardian_;
    }

    function setBaseVaultParameters(BaseVaultParameters memory params) internal {
        vm.mockCall(
            address(params.whitelist),
            abi.encodeWithSelector(IWhitelist.isWhitelisted.selector, guardian),
            abi.encode(true)
        );

        parameters = params;
    }
}
