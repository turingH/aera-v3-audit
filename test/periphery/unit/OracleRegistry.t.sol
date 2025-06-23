// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Ownable } from "@oz/access/Ownable.sol";
import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@oz/utils/introspection/IERC165.sol";

import { Authority } from "@solmate/auth/Auth.sol";
import { OracleData } from "src/core/Types.sol";
import { IOracle } from "src/dependencies/oracles/IOracle.sol";
import { MAXIMUM_UPDATE_DELAY } from "src/periphery/Constants.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";
import { MockChainlink7726Adapter } from "test/periphery/mocks/MockChainlink7726Adapter.sol";
import { BaseOracleRegistryTest } from "test/utils/BaseOracleRegistryTest.t.sol";

contract OracleRegistryTest is BaseOracleRegistryTest {
    OracleRegistry public oracleRegistry;

    address public base1 = makeAddr("base1");
    address public quote1 = makeAddr("quote1");
    address public oracle1 = makeAddr("oracle1");
    address public base2 = makeAddr("base2");
    address public quote2 = makeAddr("quote2");
    address public oracle2 = makeAddr("oracle2");

    MockChainlink7726Adapter public erc7726Oracle;

    uint256 public constant BASE1_DECIMALS = 18;
    uint256 public constant BASE2_DECIMALS = 6;
    uint256 public constant DEFAULT_QUOTE_AMOUNT = 1;
    uint256 public constant DEFAULT_NEW_QUOTE_AMOUNT = 2;
    uint256 public constant DEFAULT_BASE_AMOUNT = 10 ** BASE1_DECIMALS;

    function setUp() public virtual override {
        super.setUp();

        _mockGetQuote(IOracle(oracle1), DEFAULT_BASE_AMOUNT, base1, quote1, DEFAULT_QUOTE_AMOUNT);

        vm.prank(users.owner);
        oracleRegistry = new OracleRegistry(users.owner, Authority(address(0)), ORACLE_UPDATE_DELAY);
        vm.prank(users.owner);
        oracleRegistry.addOracle(base1, quote1, IOracle(oracle1));

        vm.mockCall(
            address(base1), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(BASE1_DECIMALS)
        );
        vm.mockCall(
            address(base2), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(BASE2_DECIMALS)
        );
    }

    ////////////////////////////////////////////////////////////
    //                   deplyoment                           //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public {
        uint256 oracleUpdateDelay = 10 days;

        OracleRegistry newOracleRegistry =
            new OracleRegistry(address(this), Authority(address(0xabcd)), oracleUpdateDelay);
        vm.snapshotGasLastCall("deployment - success ");

        assertEq(newOracleRegistry.ORACLE_UPDATE_DELAY(), oracleUpdateDelay);
        assertEq(newOracleRegistry.owner(), address(this));
        assertEq(address(newOracleRegistry.authority()), address(0xabcd));
    }

    function test_deployment_revertsWith_OracleUpdateDelayTooLong() public {
        vm.expectRevert(IOracleRegistry.AeraPeriphery__OracleUpdateDelayTooLong.selector);
        new OracleRegistry(address(this), Authority(address(0)), MAXIMUM_UPDATE_DELAY + 1);
    }

    function test_deployment_revertsWith_ZeroAddressOwner() public {
        vm.expectRevert(IOracleRegistry.AeraPeriphery__ZeroAddressOwner.selector);
        new OracleRegistry(address(0), Authority(address(0)), 10 days);
    }

    ////////////////////////////////////////////////////////////
    //                   addOracle                            //
    ////////////////////////////////////////////////////////////

    function test_addOracle_success() public {
        _mockGetQuote(IOracle(oracle2), 10 ** BASE2_DECIMALS, base2, quote2, DEFAULT_QUOTE_AMOUNT);

        vm.prank(users.owner);
        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.OracleSet(base2, quote2, IOracle(oracle2));
        oracleRegistry.addOracle(base2, quote2, IOracle(oracle2));

        OracleData memory oracleData = oracleRegistry.getOracleData(base2, quote2);
        assertEq(address(oracleData.oracle), address(oracle2));
        assertFalse(oracleData.isScheduledForUpdate);
        assertFalse(oracleData.isDisabled);
        assertEq(address(oracleData.pendingOracle), address(0));
        assertEq(oracleData.commitTimestamp, 0);
    }

    function test_addOracle_revertsWith_UNAUTHORIZED() public {
        vm.expectRevert("UNAUTHORIZED");
        oracleRegistry.addOracle(base1, quote1, IOracle(oracle1));
    }

    function test_addOracle_revertsWith_OracleAlreadySet() public {
        vm.prank(users.owner);
        vm.expectRevert(IOracleRegistry.AeraPeriphery__OracleAlreadySet.selector);
        oracleRegistry.addOracle(base1, quote1, IOracle(oracle1));
    }

    function test_addOracle_revertsWith_OracleNotERC7726Compatible() public {
        vm.prank(users.owner);
        vm.expectRevert();
        oracleRegistry.addOracle(base2, quote2, IOracle(makeAddr("newOracle")));
    }

    function test_addOracle_revertsWith_OracleConvertsOneBaseTokenToZeroQuoteTokens() public {
        _mockGetQuote(IOracle(oracle2), 10 ** BASE2_DECIMALS, base2, quote2, 0);

        vm.prank(users.owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleRegistry.AeraPeriphery__OracleConvertsOneBaseTokenToZeroQuoteTokens.selector, base2, quote2
            )
        );
        oracleRegistry.addOracle(base2, quote2, IOracle(oracle2));
    }

    ////////////////////////////////////////////////////////////
    //                   scheduleOracleUpdate                 //
    ////////////////////////////////////////////////////////////

    function test_scheduleOracleUpdate_success() public {
        IOracle newOracle = IOracle(makeAddr("newOracle"));
        _mockGetQuote(newOracle, 10 ** BASE1_DECIMALS, base1, quote1, 1);

        vm.prank(users.owner);
        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.OracleScheduled(
            base1, quote1, newOracle, uint32(vm.getBlockTimestamp() + ORACLE_UPDATE_DELAY)
        );
        oracleRegistry.scheduleOracleUpdate(base1, quote1, newOracle);
        vm.snapshotGasLastCall("scheduleOracleUpdate - success");

        OracleData memory oracleData = oracleRegistry.getOracleData(base1, quote1);
        assertEq(address(oracleData.oracle), address(oracle1));
        assertTrue(oracleData.isScheduledForUpdate);
        assertFalse(oracleData.isDisabled);
        assertEq(address(oracleData.pendingOracle), address(newOracle));
        assertEq(oracleData.commitTimestamp, uint32(vm.getBlockTimestamp() + ORACLE_UPDATE_DELAY));
    }

    function test_scheduleOracleUpdate_revertsWith_UNAUTHORIZED() public {
        vm.expectRevert("UNAUTHORIZED");
        oracleRegistry.scheduleOracleUpdate(base1, quote1, IOracle(oracle1));
    }

    function test_scheduleOracleUpdate_revertsWith_OracleUpdateAlreadyScheduled() public {
        IOracle newOracle = IOracle(makeAddr("newOracle"));
        _mockGetQuote(newOracle, 10 ** BASE1_DECIMALS, base1, quote1, 1);

        vm.prank(users.owner);
        oracleRegistry.scheduleOracleUpdate(base1, quote1, newOracle);

        vm.prank(users.owner);
        vm.expectRevert(IOracleRegistry.AeraPeriphery__OracleUpdateAlreadyScheduled.selector);
        oracleRegistry.scheduleOracleUpdate(base1, quote1, newOracle);
    }

    function test_scheduleOracleUpdate_revertsWith_CannotScheduleOracleUpdateForSameOracle() public {
        vm.prank(users.owner);
        vm.expectRevert(
            abi.encodeWithSelector(IOracleRegistry.AeraPeriphery__CannotScheduleOracleUpdateForTheSameOracle.selector)
        );
        oracleRegistry.scheduleOracleUpdate(base1, quote1, IOracle(oracle1));
    }

    function test_scheduleOracleUpdate_revertsWith_OracleNotERC7726Compatible() public {
        vm.prank(users.owner);
        vm.expectRevert();
        oracleRegistry.scheduleOracleUpdate(base1, quote1, IOracle(makeAddr("newOracle")));
    }

    function test_scheduleOracleUpdate_revertsWith_OracleConvertsOneBaseTokenToZeroQuoteTokens() public {
        IOracle newOracle = IOracle(makeAddr("newOracle"));
        _mockGetQuote(newOracle, 10 ** BASE1_DECIMALS, base1, quote1, 0);

        vm.prank(users.owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleRegistry.AeraPeriphery__OracleConvertsOneBaseTokenToZeroQuoteTokens.selector, base1, quote1
            )
        );
        oracleRegistry.scheduleOracleUpdate(base1, quote1, newOracle);
    }

    ////////////////////////////////////////////////////////////
    //                   commitOracleUpdate                   //
    ////////////////////////////////////////////////////////////

    function test_commitOracleUpdate_success() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        skip(ORACLE_UPDATE_DELAY);

        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.OracleSet(base1, quote1, newOracle);
        oracleRegistry.commitOracleUpdate(base1, quote1);
        vm.snapshotGasLastCall("commitOracleUpdate - success");

        OracleData memory oracleData = oracleRegistry.getOracleData(base1, quote1);
        assertEq(address(oracleData.oracle), address(newOracle));
        assertFalse(oracleData.isScheduledForUpdate);
        assertFalse(oracleData.isDisabled);
        assertEq(address(oracleData.pendingOracle), address(0));
        assertEq(oracleData.commitTimestamp, 0);
    }

    function test_commitOracleUpdate_success_whenDisabled() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        vm.prank(users.owner);
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));

        skip(ORACLE_UPDATE_DELAY);

        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.OracleSet(base1, quote1, newOracle);
        oracleRegistry.commitOracleUpdate(base1, quote1);

        OracleData memory oracleData = oracleRegistry.getOracleData(base1, quote1);
        assertEq(address(oracleData.oracle), address(newOracle));
        assertFalse(oracleData.isScheduledForUpdate);
        assertFalse(oracleData.isDisabled);
        assertEq(address(oracleData.pendingOracle), address(0));
        assertEq(oracleData.commitTimestamp, 0);
    }

    function test_commitOracleUpdate_revertsWith_NoPendingOracleUpdate() public {
        vm.expectRevert(IOracleRegistry.AeraPeriphery__NoPendingOracleUpdate.selector);
        oracleRegistry.commitOracleUpdate(base1, quote1);
    }

    function test_commitOracleUpdate_revertsWith_CommitTimestampNotReached() public {
        _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        skip(ORACLE_UPDATE_DELAY - 1);

        vm.expectRevert(IOracleRegistry.AeraPeriphery__CommitTimestampNotReached.selector);
        oracleRegistry.commitOracleUpdate(base1, quote1);
    }

    function test_commitOracleUpdate_revertsWith_OracleNotERC7726Compatible() public {
        _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        skip(ORACLE_UPDATE_DELAY);

        vm.clearMockedCalls();

        vm.expectRevert();
        oracleRegistry.commitOracleUpdate(base1, quote1);
    }

    function test_commitOracleUpdate_revertsWith_OracleConvertsOneBaseTokenToZeroQuoteTokens() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        skip(ORACLE_UPDATE_DELAY);
        skip(ORACLE_UPDATE_DELAY);

        _mockGetQuote(newOracle, 10 ** BASE1_DECIMALS, base1, quote1, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleRegistry.AeraPeriphery__OracleConvertsOneBaseTokenToZeroQuoteTokens.selector, base1, quote1
            )
        );
        oracleRegistry.commitOracleUpdate(base1, quote1);
    }

    ////////////////////////////////////////////////////////////
    //                   cancelScheduledOracleUpdate                   //
    ////////////////////////////////////////////////////////////

    function test_cancelScheduledOracleUpdate_success() public {
        _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        vm.prank(users.owner);
        vm.expectEmit(true, true, false, true);
        emit IOracleRegistry.OracleUpdateCancelled(base1, quote1);
        oracleRegistry.cancelScheduledOracleUpdate(base1, quote1);
        vm.snapshotGasLastCall("cancelOracleUpdate - success");

        OracleData memory oracleData = oracleRegistry.getOracleData(base1, quote1);
        assertFalse(oracleData.isScheduledForUpdate);
        assertFalse(oracleData.isDisabled);
        assertEq(address(oracleData.oracle), address(oracle1));
        assertEq(address(oracleData.pendingOracle), address(0));
        assertEq(oracleData.commitTimestamp, 0);
    }

    function test_cancelScheduledOracleUpdate_revertsWith_UNAUTHORIZED() public {
        vm.expectRevert("UNAUTHORIZED");
        oracleRegistry.cancelScheduledOracleUpdate(base1, quote1);
    }

    function test_cancelScheduledOracleUpdate_revertsWith_NoPendingOracleUpdate() public {
        vm.prank(users.owner);
        vm.expectRevert(IOracleRegistry.AeraPeriphery__NoPendingOracleUpdate.selector);
        oracleRegistry.cancelScheduledOracleUpdate(base1, quote1);
    }

    ////////////////////////////////////////////////////////////
    //                   disableOracle                        //
    ////////////////////////////////////////////////////////////

    function test_disableOracle_success_active() public {
        vm.prank(users.owner);
        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.OracleDisabled(base1, quote1, IOracle(oracle1));
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));
        vm.snapshotGasLastCall("disableOracle active - success");

        OracleData memory oracleData = oracleRegistry.getOracleData(base1, quote1);
        assertTrue(oracleData.isDisabled);
        assertFalse(oracleData.isScheduledForUpdate);
        assertEq(address(oracleData.oracle), address(oracle1));
        assertEq(address(oracleData.pendingOracle), address(0));
        assertEq(oracleData.commitTimestamp, 0);
    }

    function test_disableOracle_success_scheduledForUpdate() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        vm.prank(users.owner);
        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.OracleDisabled(base1, quote1, IOracle(oracle1));
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));
        vm.snapshotGasLastCall("disableOracle - success");

        OracleData memory oracleData = oracleRegistry.getOracleData(base1, quote1);
        assertTrue(oracleData.isDisabled);
        assertTrue(oracleData.isScheduledForUpdate);
        assertEq(address(oracleData.oracle), address(oracle1));
        assertEq(address(oracleData.pendingOracle), address(newOracle));
        assertEq(oracleData.commitTimestamp, vm.getBlockTimestamp() + ORACLE_UPDATE_DELAY);
    }

    function test_disableOracle_revertsWith_UNAUTHORIZED() public {
        vm.expectRevert("UNAUTHORIZED");
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));
    }

    function test_disableOracle_revertsWith_OracleAlreadyDisabled() public {
        vm.prank(users.owner);
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));

        vm.prank(users.owner);
        vm.expectRevert(IOracleRegistry.AeraPeriphery__OracleAlreadyDisabled.selector);
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));
    }

    function test_disableOracle_revertsWith_OracleMismatch() public {
        vm.prank(users.owner);
        vm.expectRevert(IOracleRegistry.AeraPeriphery__OracleMismatch.selector);
        oracleRegistry.disableOracle(base1, quote1, IOracle(makeAddr("newOracle")));
    }

    function test_disableOracle_revertsWith_ZeroAddressOracle() public {
        vm.prank(users.owner);
        vm.expectRevert(IOracleRegistry.AeraPeriphery__ZeroAddressOracle.selector);
        oracleRegistry.disableOracle(base2, quote1, IOracle(address(0)));
    }

    ////////////////////////////////////////////////////////////
    //                   acceptPendingOracle                       //
    ////////////////////////////////////////////////////////////

    function test_overrideOracle_success_vault() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        vm.prank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.PendingOracleAccepted(users.alice, base1, quote1, newOracle);
        oracleRegistry.acceptPendingOracle(base1, quote1, users.alice, newOracle);

        vm.snapshotGasLastCall("acceptPendingOracle - success - vault");

        IOracle oracleOverride = oracleRegistry.oracleOverrides(users.alice, base1, quote1);
        assertEq(address(oracleOverride), address(newOracle));

        assertEq(
            oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base1, quote1, users.alice), DEFAULT_NEW_QUOTE_AMOUNT
        );
        assertEq(oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base1, quote1), DEFAULT_QUOTE_AMOUNT);
    }

    function test_overrideOracle_success_owner() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        vm.mockCall(users.alice, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.bob));

        vm.prank(users.bob);
        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.PendingOracleAccepted(users.alice, base1, quote1, newOracle);
        oracleRegistry.acceptPendingOracle(base1, quote1, users.alice, newOracle);

        vm.snapshotGasLastCall("acceptPendingOracle - success - owner");

        IOracle oracleOverride = oracleRegistry.oracleOverrides(users.alice, base1, quote1);
        assertEq(address(oracleOverride), address(newOracle));

        assertEq(
            oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base1, quote1, users.alice), DEFAULT_NEW_QUOTE_AMOUNT
        );
        assertEq(oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base1, quote1), DEFAULT_QUOTE_AMOUNT);
    }

    function test_overrideOracle_revertsWith_CallerIsNotAuthorized() public {
        vm.mockCall(users.alice, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.bob));
        vm.mockCall(users.alice, abi.encodeWithSelector(bytes4(keccak256("authority()"))), abi.encode(AUTHORITY));
        _mockCanCall(address(this), address(oracleRegistry), IOracleRegistry.acceptPendingOracle.selector, false);

        vm.expectRevert(IOracleRegistry.AeraPeriphery__CallerIsNotAuthorized.selector);
        oracleRegistry.acceptPendingOracle(base1, quote1, users.alice, IOracle(oracle1));
    }

    function test_overrideOracle_revertsWith_OracleMismatch() public {
        _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        vm.prank(users.alice);
        vm.expectRevert(IOracleRegistry.AeraPeriphery__OracleMismatch.selector);
        oracleRegistry.acceptPendingOracle(base1, quote1, users.alice, IOracle(makeAddr("newOracle2")));
    }

    ////////////////////////////////////////////////////////////
    //                   removeOracleOverride                 //
    ////////////////////////////////////////////////////////////

    function test_removeOracleOverride_success_vault() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        vm.prank(users.alice);
        oracleRegistry.acceptPendingOracle(base1, quote1, users.alice, newOracle);

        vm.prank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.OracleOverrideRemoved(users.alice, base1, quote1);
        oracleRegistry.removeOracleOverride(base1, quote1, users.alice);

        vm.snapshotGasLastCall("removeOracleOverride - success - vault");

        assertEq(address(oracleRegistry.oracleOverrides(users.alice, base1, quote1)), address(0));
    }

    function test_removeOracleOverride_success_owner() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        vm.prank(users.alice);
        oracleRegistry.acceptPendingOracle(base1, quote1, users.alice, newOracle);

        vm.mockCall(users.alice, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.bob));

        vm.prank(users.bob);
        vm.expectEmit(true, true, true, true);
        emit IOracleRegistry.OracleOverrideRemoved(users.alice, base1, quote1);
        oracleRegistry.removeOracleOverride(base1, quote1, users.alice);

        vm.snapshotGasLastCall("removeOracleOverride - success - owner");

        assertEq(address(oracleRegistry.oracleOverrides(users.alice, base1, quote1)), address(0));
    }

    function test_removeOracleOverride_revertsWith_CallerIsNotAuthorized() public {
        vm.mockCall(users.alice, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.bob));
        vm.mockCall(users.alice, abi.encodeWithSelector(bytes4(keccak256("authority()"))), abi.encode(AUTHORITY));
        _mockCanCall(address(this), address(oracleRegistry), IOracleRegistry.removeOracleOverride.selector, false);

        vm.expectRevert(IOracleRegistry.AeraPeriphery__CallerIsNotAuthorized.selector);
        oracleRegistry.removeOracleOverride(base1, quote1, users.alice);
    }

    ////////////////////////////////////////////////////////////
    //                   getQuote                             //
    ////////////////////////////////////////////////////////////

    function test_getQuote_success_active() public view {
        assertEq(oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base1, quote1), DEFAULT_QUOTE_AMOUNT);
    }

    function test_getQuote_success_scheduledForUpdate() public {
        _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        assertEq(oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base1, quote1), DEFAULT_QUOTE_AMOUNT);
    }

    function test_getQuote_success_scheduledForUpdate_overridden() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        oracleRegistry.acceptPendingOracle(base1, quote1, address(this), newOracle);

        assertEq(oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base1, quote1), DEFAULT_NEW_QUOTE_AMOUNT);
    }

    function test_getQuote_success_scheduledForUpdate_overriddenWithOld() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        oracleRegistry.acceptPendingOracle(base1, quote1, address(this), newOracle);

        skip(ORACLE_UPDATE_DELAY);
        oracleRegistry.commitOracleUpdate(base1, quote1);

        IOracle newNewOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        skip(ORACLE_UPDATE_DELAY);
        oracleRegistry.commitOracleUpdate(base1, quote1);
        _mockGetQuote(newNewOracle, DEFAULT_BASE_AMOUNT, base1, quote1, 100);

        assertEq(oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base1, quote1), 100);
    }

    function test_getQuote_success_disabled_overridden() public {
        vm.prank(users.owner);
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));

        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        oracleRegistry.acceptPendingOracle(base1, quote1, address(this), newOracle);

        assertEq(oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base1, quote1), DEFAULT_NEW_QUOTE_AMOUNT);
    }

    function test_getQuote_revertsWith_OracleNotSet() public {
        vm.expectRevert(IOracleRegistry.AeraPeriphery__OracleNotSet.selector);
        oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base2, quote2);
    }

    function test_getQuote_revertsWith_OracleIsDisabled() public {
        vm.prank(users.owner);
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));

        vm.expectRevert(
            abi.encodeWithSelector(IOracleRegistry.AeraPeriphery__OracleIsDisabled.selector, base1, quote1, oracle1)
        );
        oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base1, quote1);
    }

    ////////////////////////////////////////////////////////////
    //                   getQuoteForUser                    //
    ////////////////////////////////////////////////////////////

    function test_getQuoteForUser_success_active() public view {
        assertEq(
            oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base1, quote1, address(this)), DEFAULT_QUOTE_AMOUNT
        );
    }

    function test_getQuoteForUser_success_scheduledForUpdate() public {
        _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        assertEq(
            oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base1, quote1, address(this)), DEFAULT_QUOTE_AMOUNT
        );
    }

    function test_getQuoteForUser_success_scheduledForUpdate_overridden() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        oracleRegistry.acceptPendingOracle(base1, quote1, address(this), newOracle);

        assertEq(
            oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base1, quote1, address(this)), DEFAULT_NEW_QUOTE_AMOUNT
        );
    }

    function test_getQuoteForUser_success_scheduledForUpdate_overriddenWithOld() public {
        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        oracleRegistry.acceptPendingOracle(base1, quote1, address(this), newOracle);

        skip(ORACLE_UPDATE_DELAY);
        oracleRegistry.commitOracleUpdate(base1, quote1);

        IOracle newNewOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        skip(ORACLE_UPDATE_DELAY);
        oracleRegistry.commitOracleUpdate(base1, quote1);
        _mockGetQuote(newNewOracle, DEFAULT_BASE_AMOUNT, base1, quote1, 100);

        _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);

        assertEq(oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base1, quote1, address(this)), 100);
    }

    function test_getQuoteForUser_success_disabled_overridden() public {
        vm.prank(users.owner);
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));

        IOracle newOracle = _scheduleNewOracleUpdate(base1, quote1, BASE1_DECIMALS);
        oracleRegistry.acceptPendingOracle(base1, quote1, address(this), newOracle);

        assertEq(
            oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base1, quote1, address(this)), DEFAULT_NEW_QUOTE_AMOUNT
        );
    }

    function test_getQuoteForUser_revertsWith_OracleNotSet() public {
        vm.expectRevert(IOracleRegistry.AeraPeriphery__OracleNotSet.selector);
        oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base2, quote2, address(this));
    }

    function test_getQuoteForUser_revertsWith_OracleIsDisabled() public {
        vm.prank(users.owner);
        oracleRegistry.disableOracle(base1, quote1, IOracle(oracle1));

        vm.expectRevert(
            abi.encodeWithSelector(IOracleRegistry.AeraPeriphery__OracleIsDisabled.selector, base1, quote1, oracle1)
        );
        oracleRegistry.getQuoteForUser(DEFAULT_BASE_AMOUNT, base1, quote1, address(this));
    }

    ////////////////////////////////////////////////////////////
    //                   supportsInterface                    //
    ////////////////////////////////////////////////////////////

    function test_supportsInterface_success() public view {
        assertTrue(oracleRegistry.supportsInterface(type(IOracleRegistry).interfaceId));
        assertTrue(oracleRegistry.supportsInterface(type(IOracle).interfaceId));
        assertTrue(oracleRegistry.supportsInterface(type(IERC165).interfaceId));
    }

    function _scheduleNewOracleUpdate(address base, address quote, uint256 baseDecimals)
        internal
        returns (IOracle newOracle)
    {
        newOracle = IOracle(vm.randomAddress());
        _mockGetQuote(newOracle, 10 ** baseDecimals, base, quote, DEFAULT_NEW_QUOTE_AMOUNT);

        vm.prank(users.owner);
        oracleRegistry.scheduleOracleUpdate(base, quote, newOracle);
    }
}
