// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";
import { MockBaseSlippageHooks } from "test/periphery/mocks/hooks/slippage/MockBaseSlippageHooks.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { VaultAuth } from "src/core/VaultAuth.sol";

contract BaseSlippageHooksTest is BaseTest {
    MockBaseSlippageHooks public hooks;
    ERC20Mock public numeraire;
    OracleRegistry public oracleRegistry;

    uint128 public constant MAX_DAILY_LOSS = 100e18;
    uint16 public constant MAX_SLIPPAGE_100BPS = 100;

    function setUp() public override {
        super.setUp();

        numeraire = new ERC20Mock();
        oracleRegistry = new OracleRegistry(address(this), Authority(address(0)), ORACLE_UPDATE_DELAY);
        hooks = new MockBaseSlippageHooks(address(numeraire));

        vm.label(address(hooks), "BASE_SLIPPAGE_HOOKS");
        vm.label(address(numeraire), "NUMERAIRE");
        vm.label(address(oracleRegistry), "ORACLE_REGISTRY");

        vm.mockCall(BASE_VAULT, bytes4(keccak256("owner()")), abi.encode(address(this)));
    }

    ////////////////////////////////////////////////////////////
    //                    setMaxDailyLoss                     //
    ////////////////////////////////////////////////////////////

    function test_setMaxDailyLoss_revertsWith_CallerNotVaultOwner() public {
        _mockCanCall(makeAddr("attacker"), address(hooks), IBaseSlippageHooks.setMaxDailyLoss.selector, false);

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);

        hooks.setMaxDailyLoss(BASE_VAULT, MAX_DAILY_LOSS);
    }

    function test_setMaxDailyLoss_success() public {
        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.UpdateMaxDailyLoss(BASE_VAULT, MAX_DAILY_LOSS);

        hooks.setMaxDailyLoss(BASE_VAULT, MAX_DAILY_LOSS);
        vm.snapshotGasLastCall("setMaxDailyLoss - success");

        IBaseSlippageHooks.State memory state = hooks.vaultStates(BASE_VAULT);
        assertEq(state.maxDailyLossInNumeraire, MAX_DAILY_LOSS);
    }

    ////////////////////////////////////////////////////////////
    //                 setMaxSlippagePerTrade                 //
    ////////////////////////////////////////////////////////////

    function test_setMaxSlippagePerTrade_revertsWith_CallerIsNotAuthorized() public {
        _mockCanCall(makeAddr("attacker"), address(hooks), IBaseSlippageHooks.setMaxSlippagePerTrade.selector, false);

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);

        hooks.setMaxSlippagePerTrade(BASE_VAULT, MAX_SLIPPAGE_100BPS);
    }

    function test_setMaxSlippagePerTrade_success() public {
        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.UpdateMaxSlippage(BASE_VAULT, MAX_SLIPPAGE_100BPS);

        hooks.setMaxSlippagePerTrade(BASE_VAULT, MAX_SLIPPAGE_100BPS);
        vm.snapshotGasLastCall("setMaxSlippagePerTrade - success");

        IBaseSlippageHooks.State memory state = hooks.vaultStates(BASE_VAULT);
        assertEq(state.maxSlippagePerTrade, MAX_SLIPPAGE_100BPS);
    }

    ////////////////////////////////////////////////////////////
    //                   setOracleRegistry                    //
    ////////////////////////////////////////////////////////////

    function test_setOracleRegistry_revertsWith_OracleRegistryZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IBaseSlippageHooks.AeraPeriphery__ZeroAddressOracleRegistry.selector));
        hooks.setOracleRegistry(BASE_VAULT, address(0));
    }

    function test_setOracleRegistry_revertsWith_CallerNotVaultOwner() public {
        _mockCanCall(makeAddr("attacker"), address(hooks), IBaseSlippageHooks.setOracleRegistry.selector, false);

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);
        hooks.setOracleRegistry(BASE_VAULT, address(oracleRegistry));
    }

    function test_setOracleRegistry_success() public {
        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.UpdateOracleRegistry(BASE_VAULT, address(oracleRegistry));

        hooks.setOracleRegistry(BASE_VAULT, address(oracleRegistry));
        vm.snapshotGasLastCall("setOracleRegistry - success");

        IBaseSlippageHooks.State memory state = hooks.vaultStates(BASE_VAULT);
        assertEq(address(state.oracleRegistry), address(oracleRegistry));
    }

    ////////////////////////////////////////////////////////////
    //                   vaultStates                          //
    ////////////////////////////////////////////////////////////

    function test_vaultStates_success_currentDay() public {
        IBaseSlippageHooks.State memory state = IBaseSlippageHooks.State({
            currentDay: uint32(vm.getBlockTimestamp() / 1 days),
            cumulativeDailyLossInNumeraire: 0,
            maxDailyLossInNumeraire: 100e18,
            maxSlippagePerTrade: 100,
            oracleRegistry: oracleRegistry
        });
        hooks.setVaultState(BASE_VAULT, state);

        IBaseSlippageHooks.State memory result = hooks.vaultStates(BASE_VAULT);
        assertEq(result.currentDay, state.currentDay);
        assertEq(result.cumulativeDailyLossInNumeraire, state.cumulativeDailyLossInNumeraire);
        assertEq(result.maxDailyLossInNumeraire, state.maxDailyLossInNumeraire);
        assertEq(result.maxSlippagePerTrade, state.maxSlippagePerTrade);
    }

    function test_vaultStates_success_nextDay() public {
        IBaseSlippageHooks.State memory state = IBaseSlippageHooks.State({
            currentDay: uint32(vm.getBlockTimestamp() / 1 days),
            cumulativeDailyLossInNumeraire: 0,
            maxDailyLossInNumeraire: 100e18,
            maxSlippagePerTrade: 100,
            oracleRegistry: oracleRegistry
        });
        hooks.setVaultState(BASE_VAULT, state);

        skip(10 days);

        IBaseSlippageHooks.State memory result = hooks.vaultStates(BASE_VAULT);
        assertEq(result.currentDay, state.currentDay + 10);
        assertEq(result.cumulativeDailyLossInNumeraire, 0);
        assertEq(result.maxDailyLossInNumeraire, state.maxDailyLossInNumeraire);
        assertEq(result.maxSlippagePerTrade, state.maxSlippagePerTrade);
    }
}
