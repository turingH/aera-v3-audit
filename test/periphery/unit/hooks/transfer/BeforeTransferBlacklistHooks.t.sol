// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Ownable } from "@oz/access/Ownable.sol";
import { IChainalysisSanctionsOracle } from "src/dependencies/chainalysis/IChainalysisSanctionsOracle.sol";

import { TransferBlacklistHook } from "src/periphery/hooks/transfer/TransferBlacklistHook.sol";

import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";
import { ITransferBlacklistHook } from "src/periphery/interfaces/hooks/transfer/ITransferBlacklistHook.sol";

import { MockChainalysisSanctionsOracle } from "test/core/mocks/MockChainalysisSanctionsOracle.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract BeforeTransferBlacklistHookTest is BaseTest {
    TransferBlacklistHook internal beforeTransferHook;
    MockChainalysisSanctionsOracle internal mockChainalysisSanctionsOracle;

    function setUp() public override {
        super.setUp();
        mockChainalysisSanctionsOracle = new MockChainalysisSanctionsOracle();
        beforeTransferHook =
            new TransferBlacklistHook(IChainalysisSanctionsOracle(address(mockChainalysisSanctionsOracle)));

        vm.mockCall(address(BASE_VAULT), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.owner));
        vm.prank(users.owner);
        beforeTransferHook.setIsVaultUnitsTransferable(address(BASE_VAULT), true);
    }

    modifier mockBlacklistOracle(address sanctionedUser) {
        address[] memory blacklist = new address[](1);
        blacklist[0] = sanctionedUser;
        mockChainalysisSanctionsOracle.addToSanctionsList(blacklist);
        _;
    }

    ////////////////////////////////////////////////////////////
    //                     beforeTransfer                     //
    ////////////////////////////////////////////////////////////

    function test_beforeTransfer_revertsWith_VaultUnitNotTransferable() public {
        vm.prank(users.owner);
        beforeTransferHook.setIsVaultUnitsTransferable(address(BASE_VAULT), false);

        vm.prank(BASE_VAULT);
        vm.expectRevert(
            abi.encodeWithSelector(IBeforeTransferHook.Aera__VaultUnitsNotTransferable.selector, BASE_VAULT)
        );
        beforeTransferHook.beforeTransfer(users.alice, users.stranger, PROVISIONER);
    }

    function test_beforeTransfer_revertsWith_BlacklistedAddress_From() public mockBlacklistOracle(users.alice) {
        vm.prank(BASE_VAULT);
        vm.expectRevert(
            abi.encodeWithSelector(ITransferBlacklistHook.AeraPeriphery__BlacklistedAddress.selector, users.alice)
        );
        beforeTransferHook.beforeTransfer(users.alice, users.stranger, PROVISIONER);
    }

    function test_beforeTransfer_revertsWith_BlacklistedAddress_To() public mockBlacklistOracle(users.stranger) {
        vm.prank(BASE_VAULT);
        vm.expectRevert(
            abi.encodeWithSelector(ITransferBlacklistHook.AeraPeriphery__BlacklistedAddress.selector, users.stranger)
        );
        beforeTransferHook.beforeTransfer(users.alice, users.stranger, PROVISIONER);
    }

    function test_beforeTransfer_success_blacklist() public {
        vm.prank(BASE_VAULT);
        beforeTransferHook.beforeTransfer(users.alice, users.stranger, PROVISIONER);
        vm.snapshotGasLastCall("beforeTransfer - success - blacklist");
    }

    function test_beforeTransfer_success_transferAgent_from() public {
        vm.prank(users.owner);
        beforeTransferHook.setIsVaultUnitsTransferable(address(BASE_VAULT), false);

        vm.prank(BASE_VAULT);
        beforeTransferHook.beforeTransfer(PROVISIONER, users.stranger, PROVISIONER);
        vm.snapshotGasLastCall("beforeTransfer - success - transferAgent - from");
    }

    function test_beforeTransfer_success_transferAgent_to() public {
        vm.prank(users.owner);
        beforeTransferHook.setIsVaultUnitsTransferable(address(BASE_VAULT), false);

        vm.prank(BASE_VAULT);
        beforeTransferHook.beforeTransfer(users.alice, PROVISIONER, PROVISIONER);
        vm.snapshotGasLastCall("beforeTransfer - success - transferAgent - to");
    }
}
