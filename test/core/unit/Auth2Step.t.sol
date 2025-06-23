// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { Auth2Step } from "src/core/Auth2Step.sol";
import { IAuth2Step } from "src/core/interfaces/IAuth2Step.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract Auth2StepTest is BaseTest {
    Auth2Step internal auth2Step;

    address internal immutable NEW_OWNER = makeAddr("NEW_OWNER");

    function setUp() public override {
        super.setUp();
        auth2Step = new Auth2Step(users.owner, Authority(address(0)));
    }

    function test_deployment_success_noAuthority() public {
        vm.expectEmit(false, false, false, true);
        emit Auth.OwnershipTransferred(address(0), users.owner);
        vm.expectEmit(false, false, false, true);
        emit Auth.AuthorityUpdated(address(0), Authority(address(0)));

        // Deploy with no authority
        auth2Step = new Auth2Step(users.owner, Authority(address(0)));
        vm.snapshotGasLastCall("deployment - no authority");

        // Assert state after deployment
        assertEq(auth2Step.owner(), users.owner, "Owner should be set correctly");
        assertEq(address(auth2Step.authority()), address(0), "Authority should be zero address");
        assertEq(auth2Step.pendingOwner(), address(0), "Pending owner should be zero address");
    }

    function test_deployment_success_withAuthority() public {
        vm.expectEmit(false, false, false, true);
        emit Auth.OwnershipTransferred(address(0), users.owner);
        vm.expectEmit(false, false, false, true);
        emit Auth.AuthorityUpdated(address(0), Authority(AUTHORITY));

        // Deploy with an authority
        auth2Step = new Auth2Step(users.owner, Authority(AUTHORITY));
        vm.snapshotGasLastCall("deployment - with authority");

        // Assert state after deployment
        assertEq(auth2Step.owner(), users.owner, "Owner should be set correctly");
        assertEq(address(auth2Step.authority()), AUTHORITY, "Authority should be set correctly");
        assertEq(auth2Step.pendingOwner(), address(0), "Pending owner should be zero address");
    }

    ////////////////////////////////////////////////////////////
    //                   transferOwnership                    //
    ////////////////////////////////////////////////////////////

    function test_transferOwnership_success() public {
        // Expect the OwnershipTransferStarted event to be emitted
        vm.expectEmit(false, false, false, true);
        emit IAuth2Step.OwnershipTransferStarted(users.owner, NEW_OWNER);

        // Call transferOwnership as the owner
        vm.prank(users.owner);
        auth2Step.transferOwnership(NEW_OWNER);
        vm.snapshotGasLastCall("transferOwnership - success");

        // Assert state after transferOwnership
        assertEq(auth2Step.owner(), users.owner, "Owner should not change");
        assertEq(auth2Step.pendingOwner(), NEW_OWNER, "Pending owner should be set to new owner");
    }

    function test_transferOwnership_revertsWith_Unauthorized() public {
        // Call transferOwnership as a non-owner
        vm.prank(users.alice);

        // Expect the call to revert with Unauthorized
        vm.expectRevert(IAuth2Step.Aera__Unauthorized.selector);
        auth2Step.transferOwnership(NEW_OWNER);

        // Assert state remains unchanged
        assertEq(auth2Step.owner(), users.owner, "Owner should remain unchanged");
        assertEq(auth2Step.pendingOwner(), address(0), "Pending owner should remain zero address");
    }

    ////////////////////////////////////////////////////////////
    //                    acceptOwnership                     //
    ////////////////////////////////////////////////////////////

    function test_acceptOwnership_success() public {
        // First set up a pending owner
        vm.prank(users.owner);
        auth2Step.transferOwnership(NEW_OWNER);

        // Expect the OwnershipTransferred event to be emitted
        vm.expectEmit(false, false, false, true);
        emit Auth.OwnershipTransferred(NEW_OWNER, NEW_OWNER);

        // Call acceptOwnership as the pending owner
        vm.prank(NEW_OWNER);
        auth2Step.acceptOwnership();
        vm.snapshotGasLastCall("acceptOwnership - success");

        // Assert state after acceptOwnership
        assertEq(auth2Step.owner(), NEW_OWNER, "Owner should be updated to new owner");
        assertEq(auth2Step.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_acceptOwnership_revertsWith_Unauthorized() public {
        // First set up a pending owner
        vm.prank(users.owner);
        auth2Step.transferOwnership(NEW_OWNER);

        // Call acceptOwnership as someone who is not the pending owner
        vm.prank(users.alice);

        // Expect the call to revert with Unauthorized
        vm.expectRevert(IAuth2Step.Aera__Unauthorized.selector);
        auth2Step.acceptOwnership();

        // Assert state remains unchanged
        assertEq(auth2Step.owner(), users.owner, "Owner should remain unchanged");
        assertEq(auth2Step.pendingOwner(), NEW_OWNER, "Pending owner should remain set");
    }
}
