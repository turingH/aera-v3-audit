// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import { Test } from "forge-std/Test.sol";
import { BaseVaultFactory } from "src/core/BaseVaultFactory.sol";
import { BaseVaultParameters } from "src/core/Types.sol";
import { Whitelist } from "src/core/Whitelist.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { ComputeBaseVaultAddressLens } from "src/periphery/ComputeBaseVaultAddressLens.sol";

contract ComputeBaseVaultAddressLensTest is Test {
    ComputeBaseVaultAddressLens internal helper;
    Whitelist internal whitelist;

    address internal owner = address(this);
    address internal guardian = 0x1234567890123456789012345678901234567890;

    function setUp() public {
        helper = new ComputeBaseVaultAddressLens();
        whitelist = new Whitelist(owner, Authority(address(0))); // Whitelist is owned by the test contract initially

        // Pre-whitelist the guardian for the test
        whitelist.setWhitelisted(guardian, true);
    }

    function test_computeBaseVaultAddress() public {
        BaseVaultFactory factory = new BaseVaultFactory(owner, Authority(address(0)));
        bytes32 salt = bytes32(uint256(1));
        string memory description = "Test Base Vault";

        BaseVaultParameters memory baseVaultParams = BaseVaultParameters({
            owner: 0x1234567890123456789012345678901234567890, // Vault owner
            authority: Authority(address(0)),
            submitHooks: ISubmitHooks(address(0)),
            whitelist: whitelist
        });

        address expectedAddress = helper.computeBaseVaultAddress(factory, salt);

        // BaseVaultFactory create function is onlyOwner
        vm.prank(owner);
        address actualAddress = factory.create(salt, description, baseVaultParams, expectedAddress);

        assertEq(actualAddress, expectedAddress);
    }
}
