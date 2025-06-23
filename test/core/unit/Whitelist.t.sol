// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Whitelist } from "src/core/Whitelist.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { Auth, Authority } from "src/dependencies/solmate/auth/Auth.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract WhitelistTest is BaseTest {
    Whitelist internal whitelist;

    function setUp() public override {
        super.setUp();
        whitelist = new Whitelist(users.owner, Authority(address(0)));
    }

    function test_deployment_success() public {
        // Deploy a new instance to test the constructor
        vm.expectEmit(false, false, false, true);
        emit Auth.OwnershipTransferred(address(0), users.owner);
        vm.expectEmit(false, false, false, true);
        emit Auth.AuthorityUpdated(address(0), Authority(address(0)));

        Whitelist newRegistry = new Whitelist(users.owner, Authority(address(0)));
        vm.snapshotGasLastCall("deployment - success");

        // Assert state after deployment
        assertEq(newRegistry.owner(), users.owner, "Owner should be set correctly");
        assertFalse(newRegistry.isWhitelisted(users.guardian), "Guardian should not be whitelisted by default");
    }

    ////////////////////////////////////////////////////////////
    //                     setWhitelisted                     //
    ////////////////////////////////////////////////////////////
    function test_setWhitelisted_success() public {
        // Expect the WhitelistSet event to be emitted
        vm.expectEmit(false, false, false, true);
        emit IWhitelist.WhitelistSet(users.guardian, true);

        vm.prank(users.owner);
        whitelist.setWhitelisted(users.guardian, true);
        vm.snapshotGasLastCall("setWhitelisted - success - set to true");

        // Assert state after setWhitelisted
        assertTrue(whitelist.isWhitelisted(users.guardian), "Guardian should be whitelisted");

        // Now test setting to false
        vm.expectEmit(false, false, false, true);
        emit IWhitelist.WhitelistSet(users.guardian, false);

        vm.prank(users.owner);
        whitelist.setWhitelisted(users.guardian, false);
        vm.snapshotGasLastCall("setWhitelisted - success - set to false");

        // Assert state after setWhitelisted to false
        assertFalse(whitelist.isWhitelisted(users.guardian), "Guardian should not be whitelisted");
    }

    function test_setWhitelisted_revertsWith_Unauthorized() public {
        // Call setWhitelisted as a non-owner
        vm.prank(users.alice);

        vm.expectRevert("UNAUTHORIZED");
        whitelist.setWhitelisted(users.guardian, true);

        // Assert state remains unchanged
        assertFalse(whitelist.isWhitelisted(users.guardian), "Guardian should remain not whitelisted");
    }

    ////////////////////////////////////////////////////////////
    //                     isWhitelisted                      //
    ////////////////////////////////////////////////////////////
    function test_isWhitelisted_success() public {
        vm.prank(users.owner);
        whitelist.setWhitelisted(users.guardian, true);
        assertTrue(whitelist.isWhitelisted(users.guardian), "Guardian should be whitelisted");

        vm.prank(users.owner);
        whitelist.setWhitelisted(users.guardian, false);
        assertFalse(whitelist.isWhitelisted(users.guardian), "Guardian should not be whitelisted");
    }

    ////////////////////////////////////////////////////////////
    //                   getAllWhitelisted                    //
    ////////////////////////////////////////////////////////////
    function test_getAllWhitelisted_success() public {
        address[] memory expectedAddresses = new address[](5);
        expectedAddresses[0] = users.guardian;
        expectedAddresses[1] = users.alice;
        expectedAddresses[2] = users.bob;
        expectedAddresses[3] = users.charlie;
        expectedAddresses[4] = users.dan;

        vm.startPrank(users.owner);
        for (uint256 i = 0; i < expectedAddresses.length; i++) {
            whitelist.setWhitelisted(expectedAddresses[i], true);
        }
        vm.stopPrank();

        // Get all whitelisted addresses
        address[] memory whitelistedAddresses = whitelist.getAllWhitelisted();
        assertEq(
            whitelistedAddresses.length,
            expectedAddresses.length,
            "The number of whitelisted addresses should be correct"
        );
        for (uint256 i = 0; i < expectedAddresses.length; i++) {
            assertEq(
                whitelistedAddresses[i], expectedAddresses[i], "The whitelisted address should be the correct address"
            );
        }
    }
}
