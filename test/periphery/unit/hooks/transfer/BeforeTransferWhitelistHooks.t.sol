// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Ownable } from "@oz/access/Ownable.sol";

import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";
import { TransferWhitelistHook } from "src/periphery/hooks/transfer/TransferWhitelistHook.sol";
import { ITransferWhitelistHook } from "src/periphery/interfaces/hooks/transfer/ITransferWhitelistHook.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

contract BeforeTransferWhitelistHookTest is BaseTest {
    TransferWhitelistHook internal beforeTransferHook;

    function setUp() public override {
        super.setUp();
        beforeTransferHook = new TransferWhitelistHook();

        vm.mockCall(address(BASE_VAULT), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.owner));
        vm.prank(users.owner);
        beforeTransferHook.setIsVaultUnitsTransferable(address(BASE_VAULT), true);
    }

    modifier setVaultOwner(address vault, address owner) {
        vm.mockCall(address(vault), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(owner));
        _;
    }

    ////////////////////////////////////////////////////////////
    //                    updateWhitelist                     //
    ////////////////////////////////////////////////////////////

    function test_updateWhitelist_success() public {
        address[] memory whitelistedAddresses = new address[](2);
        whitelistedAddresses[0] = users.alice;
        whitelistedAddresses[1] = users.stranger;

        vm.expectEmit(false, false, false, true);
        emit ITransferWhitelistHook.VaultWhitelistUpdated(address(BASE_VAULT), whitelistedAddresses, true);
        vm.prank(users.owner);
        beforeTransferHook.updateWhitelist(address(BASE_VAULT), whitelistedAddresses, true);
        vm.snapshotGasLastCall("updateWhitelist - success");
    }

    ////////////////////////////////////////////////////////////
    //                     beforeTransfer                     //
    ////////////////////////////////////////////////////////////

    modifier updateWhitelist(
        address vault,
        address whitelistedAddress1,
        address whitelistedAddress2,
        bool isWhitelisted
    ) {
        address[] memory addresses = new address[](2);
        addresses[0] = whitelistedAddress1;
        addresses[1] = whitelistedAddress2;

        vm.prank(users.owner);
        beforeTransferHook.updateWhitelist(vault, addresses, isWhitelisted);

        _;
    }

    function test_beforeTransfer_revertsWith_VaultUnitNotTransferable() public {
        vm.prank(users.owner);
        beforeTransferHook.setIsVaultUnitsTransferable(address(BASE_VAULT), false);

        vm.prank(BASE_VAULT);
        vm.expectRevert(
            abi.encodeWithSelector(IBeforeTransferHook.Aera__VaultUnitsNotTransferable.selector, BASE_VAULT)
        );
        beforeTransferHook.beforeTransfer(users.alice, users.stranger, PROVISIONER);
    }

    function test_beforeTransfer_revertsWith_NotWhitelisted_From()
        public
        updateWhitelist(BASE_VAULT, address(0), address(0), true)
    {
        vm.prank(BASE_VAULT);
        vm.expectRevert(
            abi.encodeWithSelector(ITransferWhitelistHook.AeraPeriphery__NotWhitelisted.selector, users.alice)
        );
        beforeTransferHook.beforeTransfer(users.alice, users.stranger, PROVISIONER);
    }

    function test_beforeTransfer_revertsWith_NotWhitelisted_To()
        public
        updateWhitelist(BASE_VAULT, users.alice, address(0), true)
    {
        vm.prank(BASE_VAULT);
        vm.expectRevert(
            abi.encodeWithSelector(ITransferWhitelistHook.AeraPeriphery__NotWhitelisted.selector, users.stranger)
        );
        beforeTransferHook.beforeTransfer(users.alice, users.stranger, PROVISIONER);
    }

    function test_beforeTransfer_success_whitelist() public {
        address[] memory addresses = new address[](3);
        addresses[0] = users.alice;
        addresses[1] = users.stranger;
        addresses[2] = users.guardian;

        vm.prank(users.owner);
        beforeTransferHook.updateWhitelist(BASE_VAULT, addresses, true);

        vm.prank(BASE_VAULT);
        beforeTransferHook.beforeTransfer(users.alice, users.stranger, PROVISIONER);
        vm.snapshotGasLastCall("beforeTransfer - success - whitelist");
    }

    function test_beforeTransfer_success_transferAgent_from() public {
        address[] memory addresses = new address[](1);
        addresses[0] = users.alice;

        vm.prank(users.owner);
        beforeTransferHook.updateWhitelist(BASE_VAULT, addresses, true);

        vm.prank(users.owner);
        beforeTransferHook.setIsVaultUnitsTransferable(address(BASE_VAULT), false);

        vm.prank(BASE_VAULT);
        beforeTransferHook.beforeTransfer(PROVISIONER, users.alice, PROVISIONER);
        vm.snapshotGasLastCall("beforeTransfer - success - transferAgent - from");
    }

    function test_beforeTransfer_success_transferAgent_to() public {
        address[] memory addresses = new address[](1);
        addresses[0] = users.alice;

        vm.prank(users.owner);
        beforeTransferHook.updateWhitelist(BASE_VAULT, addresses, true);

        vm.prank(users.owner);
        beforeTransferHook.setIsVaultUnitsTransferable(address(BASE_VAULT), false);

        vm.prank(BASE_VAULT);
        beforeTransferHook.beforeTransfer(users.alice, PROVISIONER, PROVISIONER);
        vm.snapshotGasLastCall("beforeTransfer - success - transferAgent - to");
    }
}
