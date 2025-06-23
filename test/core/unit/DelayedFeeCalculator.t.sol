// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import {
    MAX_DISPUTE_PERIOD, MAX_PERFORMANCE_FEE, MAX_TVL_FEE, ONE_IN_BPS, SECONDS_PER_YEAR
} from "src/core/Constants.sol";
import { DelayedFeeCalculator } from "src/core/DelayedFeeCalculator.sol";

import { Ownable } from "@oz/access/Ownable.sol";
import { Fee, VaultAccruals, VaultSnapshot } from "src/core/Types.sol";
import { IBaseFeeCalculator } from "src/core/interfaces/IBaseFeeCalculator.sol";
import { IDelayedFeeCalculator } from "src/core/interfaces/IDelayedFeeCalculator.sol";
import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { MockDelayedFeeCalculator } from "test/core/mocks/MockDelayedFeeCalculator.sol";

contract DelayedFeeCalculatorTest is BaseTest {
    DelayedFeeCalculator internal feeCalculator;

    uint160 internal constant TEST_AMOUNT = 1000e18; // 1000 tokens

    uint256 internal constant DISPUTE_PERIOD = 15 days;

    uint16 internal constant VAULT_TVL_FEE = 100; // 1%
    uint16 internal constant VAULT_PERFORMANCE_FEE = 1000; // 10%
    uint16 internal constant PROTOCOL_TVL_FEE = 50; // 0.5%
    uint16 internal constant PROTOCOL_PERFORMANCE_FEE = 300; // 3%
    uint32 internal constant ACTIVE_RECIPIENT_END_TIMESTAMP = type(uint32).max;

    address internal immutable PROTOCOL_FEE_RECIPIENT = makeAddr("PROTOCOL_FEE_RECIPIENT");

    uint256 internal START_FEE_ACCRUAL;

    struct FeeTestContext {
        // Input parameters
        uint160 averageValue;
        uint128 highestProfit;
        // Timing
        uint256 startLastFeeAccrual;
        uint32 snapshotTimestamp;
        uint256 totalDuration;
        // Preview values
        uint256 claimableVaultFeesView;
        uint256 claimableProtocolFeesView;
        // Results
        VaultAccruals vaultAccruals;
        VaultSnapshot vaultSnapshot;
    }

    struct AccrueFeesParameters {
        uint96 averageValue;
        uint96 highestProfit;
        uint96 lastHighestProfit;
        uint16 protocolTvl;
        uint16 protocolPerformance;
        uint32 snapshotDelay;
        uint32 timePassed;
    }

    function setUp() public override {
        super.setUp();

        START_FEE_ACCRUAL = vm.getBlockTimestamp();

        // Set up fee configs with 1% TVL fee
        feeCalculator = new DelayedFeeCalculator(address(this), Authority(address(0)), DISPUTE_PERIOD);
        feeCalculator.setProtocolFeeRecipient(PROTOCOL_FEE_RECIPIENT);
        feeCalculator.setProtocolFees(PROTOCOL_TVL_FEE, PROTOCOL_PERFORMANCE_FEE);

        vm.prank(BASE_VAULT);
        feeCalculator.registerVault();

        vm.mockCall(BASE_VAULT, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(this)));
        feeCalculator.setVaultAccountant(BASE_VAULT, users.accountant);
        feeCalculator.setVaultFees(BASE_VAULT, VAULT_TVL_FEE, VAULT_PERFORMANCE_FEE);
    }

    function test_deployment_success() public view {
        (uint16 protocolTvlFee, uint16 protocolPerformanceFee) = feeCalculator.protocolFees();
        assertEq(protocolTvlFee, PROTOCOL_TVL_FEE);
        assertEq(protocolPerformanceFee, PROTOCOL_PERFORMANCE_FEE);
        FeeTestContext memory ctx;
        (ctx.vaultSnapshot, ctx.vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);

        assertEq(ctx.vaultSnapshot.timestamp, 0);
        assertEq(ctx.vaultSnapshot.finalizedAt, 0);
        assertEq(ctx.vaultSnapshot.averageValue, 0);
        assertEq(ctx.vaultSnapshot.highestProfit, 0);
        assertEq(ctx.vaultSnapshot.lastHighestProfit, 0);
        assertEq(ctx.vaultSnapshot.lastFeeAccrual, vm.getBlockTimestamp());

        assertEq(ctx.vaultAccruals.fees.tvl, VAULT_TVL_FEE);
        assertEq(ctx.vaultAccruals.fees.performance, VAULT_PERFORMANCE_FEE);
        assertEq(ctx.vaultAccruals.accruedProtocolFees, 0);
        assertEq(ctx.vaultAccruals.accruedFees, 0);

        assertEq(feeCalculator.owner(), address(this));
    }

    function test_deployment_revertsWith_DisputePeriodTooLong() public {
        vm.expectRevert(IDelayedFeeCalculator.Aera__DisputePeriodTooLong.selector);
        new DelayedFeeCalculator(address(this), Authority(address(0)), MAX_DISPUTE_PERIOD + 1);
    }

    ////////////////////////////////////////////////////////////
    //                     submitSnapshot                     //
    ////////////////////////////////////////////////////////////

    function test_submitSnapshot_success_noFees() public {
        skip(1 days);

        FeeTestContext memory ctx;

        ctx.averageValue = TEST_AMOUNT;
        ctx.highestProfit = uint128(TEST_AMOUNT / 10);
        ctx.snapshotTimestamp = uint32(vm.getBlockTimestamp());

        vm.expectEmit(false, false, false, true);
        emit IDelayedFeeCalculator.SnapshotSubmitted(
            BASE_VAULT, ctx.averageValue, ctx.highestProfit, ctx.snapshotTimestamp
        );

        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, ctx.averageValue, ctx.highestProfit, ctx.snapshotTimestamp);
        vm.snapshotGasLastCall("submitSnapshot - success - no accrual");

        (ctx.vaultSnapshot, ctx.vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);

        assertEq(ctx.vaultSnapshot.timestamp, ctx.snapshotTimestamp);
        assertEq(ctx.vaultSnapshot.finalizedAt, ctx.snapshotTimestamp + DISPUTE_PERIOD);
        assertEq(ctx.vaultSnapshot.averageValue, ctx.averageValue);
        assertEq(ctx.vaultSnapshot.highestProfit, ctx.highestProfit);
        assertEq(ctx.vaultSnapshot.lastHighestProfit, 0);
        assertEq(ctx.vaultSnapshot.lastFeeAccrual, START_FEE_ACCRUAL);

        assertEq(ctx.vaultAccruals.accruedProtocolFees, 0);
        assertEq(ctx.vaultAccruals.accruedFees, 0);
    }

    function test_submitSnapshot_success_overwritesPendingSnapshot() public {
        skip(1 days);

        FeeTestContext memory ctx;
        ctx.averageValue = TEST_AMOUNT;
        ctx.highestProfit = uint128(TEST_AMOUNT / 10);
        ctx.snapshotTimestamp = uint32(vm.getBlockTimestamp());

        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, ctx.averageValue, ctx.highestProfit, ctx.snapshotTimestamp);

        skip(DISPUTE_PERIOD - 1);

        uint128 highestProfit2 = uint128(TEST_AMOUNT * 2 / 10);
        uint160 averageValue2 = TEST_AMOUNT * 11 / 10;
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue2, highestProfit2, ctx.snapshotTimestamp);
        vm.snapshotGasLastCall("submitSnapshot - success - overwrites pending snapshot");

        (ctx.vaultSnapshot, ctx.vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);

        assertEq(ctx.vaultSnapshot.timestamp, ctx.snapshotTimestamp);
        assertEq(ctx.vaultSnapshot.finalizedAt, uint32(vm.getBlockTimestamp() + DISPUTE_PERIOD));
        assertEq(ctx.vaultSnapshot.averageValue, averageValue2);
        assertEq(ctx.vaultSnapshot.highestProfit, highestProfit2);
        assertEq(ctx.vaultSnapshot.lastHighestProfit, 0);
        assertEq(ctx.vaultSnapshot.lastFeeAccrual, START_FEE_ACCRUAL);

        assertEq(ctx.vaultAccruals.accruedProtocolFees, 0);
        assertEq(ctx.vaultAccruals.accruedFees, 0);
    }

    function test_submitSnapshot_success_accruesFees() public {
        FeeTestContext memory ctx;
        ctx.totalDuration = 10 days;
        skip(ctx.totalDuration);

        ctx.averageValue = TEST_AMOUNT;
        ctx.highestProfit = uint128(TEST_AMOUNT / 10);
        ctx.snapshotTimestamp = uint32(vm.getBlockTimestamp());

        uint256 expectedLastFeeAccrual = vm.getBlockTimestamp();
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, ctx.averageValue, ctx.highestProfit, ctx.snapshotTimestamp);

        skip(DISPUTE_PERIOD);

        uint32 newSnapshotTimestamp = ctx.snapshotTimestamp + 1;
        uint128 highestProfit2 = ctx.highestProfit * 11 / 10;
        uint160 averageValue2 = ctx.averageValue * 11 / 10;
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue2, highestProfit2, newSnapshotTimestamp);
        vm.snapshotGasLastCall("submitSnapshot - success - accrues fees");

        (ctx.vaultSnapshot, ctx.vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);

        assertEq(ctx.vaultSnapshot.timestamp, newSnapshotTimestamp);
        assertEq(ctx.vaultSnapshot.finalizedAt, uint32(vm.getBlockTimestamp() + DISPUTE_PERIOD));
        assertEq(ctx.vaultSnapshot.averageValue, averageValue2);
        assertEq(ctx.vaultSnapshot.highestProfit, highestProfit2);
        assertEq(ctx.vaultSnapshot.lastHighestProfit, ctx.highestProfit);
        assertEq(ctx.vaultSnapshot.lastFeeAccrual, expectedLastFeeAccrual);

        assertEq(
            ctx.vaultAccruals.accruedProtocolFees,
            _expectedProtocolFee(ctx.averageValue, ctx.highestProfit, ctx.totalDuration)
        );
        assertEq(
            ctx.vaultAccruals.accruedFees, _expectedVaultFee(ctx.averageValue, ctx.highestProfit, ctx.totalDuration)
        );
    }

    function test_submitSnapshot_success_sameHighestProfit() public {
        skip(1 days);

        FeeTestContext memory ctx;

        ctx.averageValue = TEST_AMOUNT;
        ctx.highestProfit = 0;
        ctx.snapshotTimestamp = uint32(vm.getBlockTimestamp());

        vm.expectEmit(false, false, false, true);
        emit IDelayedFeeCalculator.SnapshotSubmitted(
            BASE_VAULT, ctx.averageValue, ctx.highestProfit, ctx.snapshotTimestamp
        );

        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, ctx.averageValue, ctx.highestProfit, ctx.snapshotTimestamp);
        vm.snapshotGasLastCall("submitSnapshot - success - same highest profit");

        (ctx.vaultSnapshot, ctx.vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);

        assertEq(ctx.vaultSnapshot.timestamp, ctx.snapshotTimestamp);
        assertEq(ctx.vaultSnapshot.finalizedAt, ctx.snapshotTimestamp + DISPUTE_PERIOD);
        assertEq(ctx.vaultSnapshot.averageValue, ctx.averageValue);
        assertEq(ctx.vaultSnapshot.highestProfit, ctx.highestProfit);
        assertEq(ctx.vaultSnapshot.lastHighestProfit, 0);
        assertEq(ctx.vaultSnapshot.lastFeeAccrual, START_FEE_ACCRUAL);

        assertEq(ctx.vaultAccruals.accruedProtocolFees, 0);
        assertEq(ctx.vaultAccruals.accruedFees, 0);
    }

    function test_submitSnapshot_revertsWith_HighestProfitDecreased() public {
        skip(1 days);
        // Arrange: set initial high-water mark
        uint128 initialHighWaterMark = 1000e18;
        uint160 averageValue = 1 ether; // not relevant for this test
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, initialHighWaterMark, uint32(vm.getBlockTimestamp()));

        // Submit a snapshot with lower highestProfit
        uint128 newHighWaterMark = 900e18;

        skip(DISPUTE_PERIOD);

        vm.expectRevert(IDelayedFeeCalculator.Aera__HighestProfitDecreased.selector);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, newHighWaterMark, uint32(vm.getBlockTimestamp()));
    }

    function test_submitSnapshot_revertsWith_SnapshotInFuture() public {
        uint128 highestProfit = uint128(TEST_AMOUNT / 10);
        uint32 futureTimestamp = uint32(vm.getBlockTimestamp() + 1);

        vm.expectRevert(IDelayedFeeCalculator.Aera__SnapshotInFuture.selector);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, TEST_AMOUNT, highestProfit, futureTimestamp);
    }

    function test_submitSnapshot_revertsWith_SnapshotTooOld() public {
        uint128 highestProfit = uint128(TEST_AMOUNT / 10);

        // Try to submit an older snapshot
        uint32 oldTimestamp = uint32(vm.getBlockTimestamp() - 1);
        vm.expectRevert(IDelayedFeeCalculator.Aera__SnapshotTooOld.selector);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, TEST_AMOUNT, highestProfit, oldTimestamp);
    }

    function test_submitSnapshot_revertsWith_VaultNotRegistered() public {
        address notRegistered = makeAddr("NOT_REGISTERED");
        vm.mockCall(notRegistered, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(this)));
        feeCalculator.setVaultAccountant(notRegistered, users.accountant);
        vm.expectRevert(IBaseFeeCalculator.Aera__VaultNotRegistered.selector);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(notRegistered, TEST_AMOUNT, 0, uint32(vm.getBlockTimestamp()));
    }

    function test_submitSnapshot_revertsWith_NotVaultAccountant() public {
        vm.expectRevert(IBaseFeeCalculator.Aera__CallerIsNotVaultAccountant.selector);
        feeCalculator.submitSnapshot(BASE_VAULT, TEST_AMOUNT, 0, uint32(vm.getBlockTimestamp()));
    }

    ////////////////////////////////////////////////////////////
    //             accrueFees + previewClaimFees              //
    ////////////////////////////////////////////////////////////

    function test_accrueFees_success_withFees() public {
        FeeTestContext memory ctx;
        ctx.averageValue = 1000e18;
        ctx.highestProfit = 100e18;

        ctx.snapshotTimestamp = _submitSnapshotAfter(ctx.averageValue, ctx.highestProfit, 15 days);

        skip(15 days);

        // Preview values
        (ctx.claimableVaultFeesView, ctx.claimableProtocolFeesView) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        feeCalculator.accrueFees(BASE_VAULT);
        vm.snapshotGasLastCall("accrueFees - success");

        // Get results
        (ctx.vaultSnapshot, ctx.vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);

        assertEq(ctx.vaultSnapshot.lastFeeAccrual, ctx.snapshotTimestamp, "lastFeeAccrual");
        assertEq(ctx.vaultSnapshot.lastHighestProfit, ctx.highestProfit, "lastHighestProfit");

        assertEq(
            ctx.vaultAccruals.accruedProtocolFees,
            _expectedProtocolFee(ctx.averageValue, ctx.highestProfit, 15 days),
            "accruedProtocolFees"
        );
        assertEq(ctx.vaultAccruals.accruedProtocolFees, ctx.claimableProtocolFeesView, "claimableProtocolFeesView");

        assertEq(
            ctx.vaultAccruals.accruedFees,
            _expectedVaultFee(ctx.averageValue, ctx.highestProfit, 15 days),
            "accruedFees"
        );
    }

    function test_fuzz_accrueFees_success_withFees(uint112 averageValue, uint112 highestProfit) public {
        uint256 snapshotTimestamp = _submitSnapshotAfter(averageValue, highestProfit, 15 days);

        skip(15 days);

        (uint256 claimableVaultFeesView, uint256 claimableProtocolFeesView) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        feeCalculator.accrueFees(BASE_VAULT);

        (VaultSnapshot memory vaultSnapshot, VaultAccruals memory vaultAccruals) =
            feeCalculator.vaultFeeState(BASE_VAULT);

        assertEq(vaultSnapshot.lastFeeAccrual, snapshotTimestamp, "lastFeeAccrual");
        assertEq(vaultSnapshot.lastHighestProfit, highestProfit, "lastHighestProfit");

        assertEq(
            vaultAccruals.accruedProtocolFees,
            _expectedProtocolFee(averageValue, highestProfit, 15 days),
            "accruedProtocolFees"
        );
        assertEq(vaultAccruals.accruedProtocolFees, claimableProtocolFeesView, "claimableProtocolFeesView");

        assertEq(vaultAccruals.accruedFees, _expectedVaultFee(averageValue, highestProfit, 15 days), "accruedFees");
        assertEq(vaultAccruals.accruedFees, claimableVaultFeesView, "claimableVaultFeesView");
    }

    function test_accrueFees_nothingToAccrue() public {
        FeeTestContext memory ctx;
        ctx.averageValue = 1000e18;
        ctx.highestProfit = 100e18;

        ctx.snapshotTimestamp = _submitSnapshotAfter(ctx.averageValue, ctx.highestProfit, 15 days);

        skip(15 days);

        (uint256 claimableVaultFeesView, uint256 claimableProtocolFeesView) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        feeCalculator.accrueFees(BASE_VAULT);

        (uint256 claimableVaultFeesViewAfter, uint256 claimableProtocolFeesViewAfter) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        assertEq(claimableVaultFeesViewAfter, claimableVaultFeesView, "claimableVaultFeesView");
        assertEq(claimableProtocolFeesViewAfter, claimableProtocolFeesView, "claimableProtocolFeesView");
    }

    ////////////////////////////////////////////////////////////
    //                setProtocolFeeRecipient                 //
    ////////////////////////////////////////////////////////////

    function test_setProtocolFeeRecipient_success() public {
        address newRecipient = makeAddr("new_protocol_recipient");

        vm.expectEmit(false, false, false, true);
        emit IBaseFeeCalculator.ProtocolFeeRecipientSet(newRecipient);

        feeCalculator.setProtocolFeeRecipient(newRecipient);
        vm.snapshotGasLastCall("setProtocolFeeRecipient - success");

        assertEq(feeCalculator.protocolFeeRecipient(), newRecipient);
    }

    function test_setProtocolFeeRecipient_revertsWith_Unauthorized() public {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        vm.expectRevert("UNAUTHORIZED");
        feeCalculator.setProtocolFeeRecipient(makeAddr("new_recipient"));
    }

    function test_setProtocolFeeRecipient_revertsWith_ProtocolFeeRecipientZeroAddress() public {
        vm.expectRevert(IBaseFeeCalculator.Aera__ZeroAddressProtocolFeeRecipient.selector);
        feeCalculator.setProtocolFeeRecipient(address(0));
    }

    ////////////////////////////////////////////////////////////
    //                     registerVault                      //
    ////////////////////////////////////////////////////////////

    function test_registerVault_success() public {
        address newVault = makeAddr("NEW_VAULT");

        vm.expectEmit(true, true, true, true);
        emit IFeeCalculator.VaultRegistered(newVault);

        vm.prank(newVault);
        feeCalculator.registerVault();
        vm.snapshotGasLastCall("registerVault - success");

        (VaultSnapshot memory vaultSnapshot, VaultAccruals memory vaultAccruals) = feeCalculator.vaultFeeState(newVault);

        assertEq(vaultSnapshot.averageValue, 0, "pendingSnapshot.averageValue");
        assertEq(vaultSnapshot.highestProfit, 0, "pendingSnapshot.highestProfit");
        assertEq(vaultSnapshot.timestamp, 0, "pendingSnapshot.timestamp");
        assertEq(vaultSnapshot.finalizedAt, 0, "pendingSnapshot.finalizedAt");
        assertEq(vaultSnapshot.lastFeeAccrual, vm.getBlockTimestamp(), "lastFeeAccrual");
        assertEq(vaultSnapshot.lastHighestProfit, 0, "lastHighestProfit");

        assertEq(vaultAccruals.fees.tvl, 0, "tvl fee");
        assertEq(vaultAccruals.fees.performance, 0, "performance fee");
        assertEq(vaultAccruals.accruedProtocolFees, 0, "accruedProtocolFees");
        assertEq(vaultAccruals.accruedFees, 0, "accruedFees");
    }

    function test_registerVault_revertsWith_VaultAlreadyRegistered() public {
        vm.prank(BASE_VAULT);
        vm.expectRevert(IFeeCalculator.Aera__VaultAlreadyRegistered.selector);
        feeCalculator.registerVault();
    }

    ////////////////////////////////////////////////////////////
    //                       claimFees                        //
    ////////////////////////////////////////////////////////////

    function test_claimFees_success_accrueFees() public {
        uint160 averageValue = 1000e18;
        uint128 highestProfit = 100e18;
        uint256 duration = 1 days;

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        (uint256 previewVaultFees, uint256 previewProtocolFees) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        vm.prank(BASE_VAULT);
        (uint256 feeRecipientEarnedFees, uint256 protocolEarnedFees, address protocolFeeRecipient) =
            feeCalculator.claimFees(type(uint256).max);

        vm.snapshotGasLastCall("claimFees - success - accrue fees");

        assertEq(
            feeRecipientEarnedFees, _expectedVaultFee(averageValue, highestProfit, duration), "feeRecipientEarnedFees"
        );
        assertEq(protocolEarnedFees, _expectedProtocolFee(averageValue, highestProfit, duration), "protocolEarnedFees");
        assertEq(protocolFeeRecipient, feeCalculator.protocolFeeRecipient(), "protocolFeeRecipient");

        assertEq(previewVaultFees, feeRecipientEarnedFees, "previewVaultFees");
        assertEq(previewProtocolFees, protocolEarnedFees, "previewProtocolFees");

        (, VaultAccruals memory vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(vaultAccruals.accruedProtocolFees, 0, "accruedProtocolFees");
        assertEq(vaultAccruals.accruedFees, 0);
    }

    function test_fuzz_claimFees_success_accrueFees(uint112 averageValue, uint112 highestProfit, uint24 duration)
        public
    {
        vm.assume(duration > 0);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        (uint256 previewVaultFees, uint256 previewProtocolFees) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        vm.prank(BASE_VAULT);
        (uint256 feeRecipientEarnedFees, uint256 protocolEarnedFees, address protocolFeeRecipient) =
            feeCalculator.claimFees(type(uint256).max);

        assertEq(
            feeRecipientEarnedFees, _expectedVaultFee(averageValue, highestProfit, duration), "feeRecipientEarnedFees"
        );
        assertEq(protocolEarnedFees, _expectedProtocolFee(averageValue, highestProfit, duration), "protocolEarnedFees");
        assertEq(protocolFeeRecipient, feeCalculator.protocolFeeRecipient(), "protocolFeeRecipient");

        assertEq(previewVaultFees, feeRecipientEarnedFees, "previewVaultFees");
        assertEq(previewProtocolFees, protocolEarnedFees, "previewProtocolFees");

        (, VaultAccruals memory vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(vaultAccruals.accruedProtocolFees, 0, "accruedProtocolFees");
        assertEq(vaultAccruals.accruedFees, 0, "accruedVaultFees");
    }

    function test_claimFees_success_noAccrueFees() public {
        uint160 averageValue = 1000e18;
        uint128 highestProfit = 100e18;
        uint256 duration = 1 days;

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        (uint256 previewVaultFees, uint256 previewProtocolFees) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        feeCalculator.accrueFees(BASE_VAULT);

        vm.prank(BASE_VAULT);
        (uint256 feeRecipientEarnedFees, uint256 protocolEarnedFees, address protocolFeeRecipient) =
            feeCalculator.claimFees(type(uint256).max);

        vm.snapshotGasLastCall("claimFees - success - no accrual");

        assertEq(
            feeRecipientEarnedFees, _expectedVaultFee(averageValue, highestProfit, duration), "feeRecipientEarnedFees"
        );
        assertEq(protocolEarnedFees, _expectedProtocolFee(averageValue, highestProfit, duration), "protocolEarnedFees");
        assertEq(protocolFeeRecipient, feeCalculator.protocolFeeRecipient(), "protocolFeeRecipient");

        assertEq(previewVaultFees, feeRecipientEarnedFees, "previewVaultFees");
        assertEq(previewProtocolFees, protocolEarnedFees, "previewProtocolFees");

        (, VaultAccruals memory vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(vaultAccruals.accruedProtocolFees, 0, "accruedProtocolFees");
        assertEq(vaultAccruals.accruedFees, 0, "accruedVaultFees");
    }

    function test_claimFees_success_partialVaultFeesClaim() public {
        uint160 averageValue = 1000e18;
        uint128 highestProfit = 100e18;
        uint256 duration = 1 days;

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        (uint256 totalVaultFees, uint256 totalProtocolFees) = feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        // Simulate insufficient vault balance to cover all accrued fees
        uint256 remainingVaultFees = totalVaultFees / 2;
        uint256 feeTokenBalance = totalProtocolFees + totalVaultFees - remainingVaultFees;

        (uint256 previewVaultFees, uint256 previewProtocolFees) = feeCalculator.previewFees(BASE_VAULT, feeTokenBalance);

        vm.prank(BASE_VAULT);
        (uint256 feeRecipientEarnedFees, uint256 protocolEarnedFees, address protocolFeeRecipient) =
            feeCalculator.claimFees(feeTokenBalance);

        vm.snapshotGasLastCall("claimFees - success - partialVaultFeesClaim");

        assertEq(
            feeRecipientEarnedFees,
            _expectedVaultFee(averageValue, highestProfit, duration) - remainingVaultFees,
            "feeRecipientEarnedFees"
        );
        assertEq(protocolEarnedFees, _expectedProtocolFee(averageValue, highestProfit, duration), "protocolEarnedFees");
        assertEq(protocolFeeRecipient, feeCalculator.protocolFeeRecipient(), "protocolFeeRecipient");

        assertEq(previewVaultFees, feeRecipientEarnedFees, "previewVaultFees");
        assertEq(previewProtocolFees, protocolEarnedFees, "previewProtocolFees");

        (, VaultAccruals memory vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(vaultAccruals.accruedProtocolFees, 0, "accruedProtocolFees");
        assertEq(vaultAccruals.accruedFees, remainingVaultFees);
    }

    function test_claimFees_success_partialProtocolFeesClaim() public {
        uint160 averageValue = 1000e18;
        uint128 highestProfit = 100e18;
        uint256 duration = 1 days;

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        (uint256 totalVaultFees, uint256 totalProtocolFees) = feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        // Simulate insufficient vault balance to cover all protocol fees
        uint256 remainingProtocolFees = totalProtocolFees / 2;
        uint256 feeTokenBalance = totalProtocolFees - remainingProtocolFees;

        (uint256 previewVaultFees, uint256 previewProtocolFees) = feeCalculator.previewFees(BASE_VAULT, feeTokenBalance);

        vm.prank(BASE_VAULT);
        (uint256 feeRecipientEarnedFees, uint256 protocolEarnedFees, address protocolFeeRecipient) =
            feeCalculator.claimFees(feeTokenBalance);

        vm.snapshotGasLastCall("claimFees - success - partialProtocolFeesClaim");

        assertEq(feeRecipientEarnedFees, 0, "feeRecipientEarnedFees");
        assertEq(
            protocolEarnedFees,
            _expectedProtocolFee(averageValue, highestProfit, duration) - remainingProtocolFees,
            "protocolEarnedFees"
        );
        assertEq(protocolFeeRecipient, feeCalculator.protocolFeeRecipient(), "protocolFeeRecipient");

        assertEq(previewVaultFees, feeRecipientEarnedFees, "previewVaultFees");
        assertEq(previewProtocolFees, protocolEarnedFees, "previewProtocolFees");

        (, VaultAccruals memory vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(vaultAccruals.accruedProtocolFees, remainingProtocolFees, "accruedProtocolFees");
        assertEq(vaultAccruals.accruedFees, totalVaultFees);
    }

    ////////////////////////////////////////////////////////////
    //                   claimProtocolFees                    //
    ////////////////////////////////////////////////////////////

    function test_claimProtocolFees_success() public {
        FeeTestContext memory ctx;
        ctx.totalDuration = 10 days;
        skip(ctx.totalDuration);

        ctx.averageValue = TEST_AMOUNT;
        ctx.highestProfit = uint128(TEST_AMOUNT / 10);
        ctx.snapshotTimestamp = uint32(vm.getBlockTimestamp());

        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, ctx.averageValue, ctx.highestProfit, ctx.snapshotTimestamp);

        skip(DISPUTE_PERIOD);

        (, uint256 protocolEarnedFeesPreview) = feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        vm.prank(BASE_VAULT);
        (uint256 protocolEarnedFees, address protocolFeeRecipient) = feeCalculator.claimProtocolFees(type(uint256).max);

        assertEq(
            protocolEarnedFees,
            _expectedProtocolFee(ctx.averageValue, ctx.highestProfit, ctx.totalDuration),
            "protocolEarnedFees"
        );

        assertEq(protocolEarnedFees, protocolEarnedFeesPreview, "protocolEarnedFees");
        assertEq(protocolFeeRecipient, PROTOCOL_FEE_RECIPIENT, "protocolFeeRecipient");

        (, VaultAccruals memory vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(vaultAccruals.accruedProtocolFees, 0, "accruedProtocolFees");
    }

    function test_claimProtocolFees_success_partialProtocolFeesClaim() public {
        FeeTestContext memory ctx;
        ctx.totalDuration = 10 days;
        skip(ctx.totalDuration);

        ctx.averageValue = TEST_AMOUNT;
        ctx.highestProfit = uint128(TEST_AMOUNT / 10);
        ctx.snapshotTimestamp = uint32(vm.getBlockTimestamp());

        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, ctx.averageValue, ctx.highestProfit, ctx.snapshotTimestamp);

        skip(DISPUTE_PERIOD);

        (, uint256 totalProtocolFees) = feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        // Simulate insufficient vault balance to cover all protocol fees
        uint256 remainingProtocolFees = totalProtocolFees / 2;
        uint256 feeTokenBalance = totalProtocolFees - remainingProtocolFees;

        (, uint256 protocolEarnedFeesPreview) = feeCalculator.previewFees(BASE_VAULT, feeTokenBalance);

        vm.prank(BASE_VAULT);
        (uint256 protocolEarnedFees, address protocolFeeRecipient) = feeCalculator.claimProtocolFees(feeTokenBalance);

        assertEq(
            protocolEarnedFees,
            _expectedProtocolFee(ctx.averageValue, ctx.highestProfit, ctx.totalDuration) - remainingProtocolFees,
            "protocolEarnedFees"
        );

        assertEq(protocolEarnedFees, protocolEarnedFeesPreview, "protocolEarnedFees");
        assertEq(protocolFeeRecipient, PROTOCOL_FEE_RECIPIENT, "protocolFeeRecipient");

        (, VaultAccruals memory vaultAccruals) = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(vaultAccruals.accruedProtocolFees, remainingProtocolFees, "accruedProtocolFees");
    }

    ////////////////////////////////////////////////////////////
    //                      previewFees                       //
    ////////////////////////////////////////////////////////////

    function test_previewFees_success_accrueFeesAllClaimable() public {
        uint160 averageValue = 1000e18;
        uint128 highestProfit = 100e18;
        uint256 duration = 1 days;

        uint256 expectedVaultFee1 = _expectedVaultFee(averageValue, highestProfit, duration);
        uint256 expectedProtocolFee1 = _expectedProtocolFee(averageValue, highestProfit, duration);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        uint256 expectedVaultFee2 = _expectedVaultFee(averageValue, highestProfit, DISPUTE_PERIOD + duration);
        uint256 expectedProtocolFee2 = _expectedProtocolFee(averageValue, highestProfit, DISPUTE_PERIOD + duration);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit * 2, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        (uint256 previewVaultFees, uint256 previewProtocolFees) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        uint256 expectedVaultFee = expectedVaultFee1 + expectedVaultFee2;
        uint256 expectedProtocolFee = expectedProtocolFee1 + expectedProtocolFee2;

        vm.snapshotGasLastCall("previewFees - success - accrue fees all claimable");

        assertEq(previewVaultFees, expectedVaultFee, "previewVaultFees should equal expectedVaultFee");
        assertEq(previewProtocolFees, expectedProtocolFee, "previewProtocolFees should equal expectedProtocolFee");
    }

    function test_previewFees_success_accrueFeesPartialClaimable() public {
        uint160 averageValue = 1000e18;
        uint128 highestProfit = 100e18;
        uint256 duration = 1 days;

        uint256 expectedVaultFee1 = _expectedVaultFee(averageValue, highestProfit, duration);
        uint256 expectedProtocolFee1 = _expectedProtocolFee(averageValue, highestProfit, duration);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        uint256 expectedVaultFee2 = _expectedVaultFee(averageValue, highestProfit, DISPUTE_PERIOD + duration);
        uint256 expectedProtocolFee2 = _expectedProtocolFee(averageValue, highestProfit, DISPUTE_PERIOD + duration);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit * 2, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        uint256 expectedVaultFee = expectedVaultFee1 + expectedVaultFee2;
        uint256 expectedProtocolFee = expectedProtocolFee1 + expectedProtocolFee2;

        // Simulate insufficient vault balance to cover all accrued fees
        uint256 remainingVaultFees = expectedVaultFee / 2;
        uint256 feeTokenBalance = expectedProtocolFee + expectedVaultFee - remainingVaultFees;

        (uint256 previewVaultFees, uint256 previewProtocolFees) = feeCalculator.previewFees(BASE_VAULT, feeTokenBalance);

        vm.snapshotGasLastCall("previewFees - success - accrue fees partial claimable");

        assertEq(
            previewVaultFees,
            expectedVaultFee - remainingVaultFees,
            "previewVaultFees should equal expectedVaultFee minus remainingVaultFees"
        );
        assertEq(previewProtocolFees, expectedProtocolFee, "previewProtocolFees should equal expectedProtocolFee");
    }

    function test_previewFees_success_nothingToAccrueAllClaimable() public {
        uint160 averageValue = 1000e18;
        uint128 highestProfit = 100e18;
        uint256 duration = 1 days;

        uint256 expectedVaultFee = _expectedVaultFee(averageValue, highestProfit, duration);
        uint256 expectedProtocolFee = _expectedProtocolFee(averageValue, highestProfit, duration);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit * 2, uint32(vm.getBlockTimestamp()));

        (uint256 previewVaultFees, uint256 previewProtocolFees) =
            feeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        vm.snapshotGasLastCall("previewFees - success - nothing to accrue all claimable");

        assertEq(previewVaultFees, expectedVaultFee, "previewVaultFees should equal expectedVaultFee");
        assertEq(previewProtocolFees, expectedProtocolFee, "previewProtocolFees should equal expectedProtocolFee");
    }

    function test_previewFees_success_nothingToAccruePartialClaimable() public {
        uint160 averageValue = 1000e18;
        uint128 highestProfit = 100e18;
        uint256 duration = 1 days;

        uint256 expectedVaultFee = _expectedVaultFee(averageValue, highestProfit, duration);
        uint256 expectedProtocolFee = _expectedProtocolFee(averageValue, highestProfit, duration);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit, uint32(vm.getBlockTimestamp()));
        skip(DISPUTE_PERIOD);

        skip(duration);
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(BASE_VAULT, averageValue, highestProfit * 2, uint32(vm.getBlockTimestamp()));

        // Simulate insufficient vault balance to cover all accrued fees
        uint256 remainingVaultFees = expectedVaultFee / 2;
        uint256 feeTokenBalance = expectedProtocolFee + expectedVaultFee - remainingVaultFees;

        (uint256 previewVaultFees, uint256 previewProtocolFees) = feeCalculator.previewFees(BASE_VAULT, feeTokenBalance);

        vm.snapshotGasLastCall("previewFees - success - nothing to accrue partial claimable");

        assertEq(
            previewVaultFees,
            expectedVaultFee - remainingVaultFees,
            "previewVaultFees should equal expectedVaultFee minus remainingVaultFees"
        );
        assertEq(previewProtocolFees, expectedProtocolFee, "previewProtocolFees should equal expectedProtocolFee");
    }

    ////////////////////////////////////////////////////////////
    //                       accrueFees                       //
    ////////////////////////////////////////////////////////////

    function test_fuzz_accrueFees_success(Fee memory fees, AccrueFeesParameters memory parameters) public {
        vm.assume(parameters.protocolTvl <= MAX_TVL_FEE);
        vm.assume(parameters.protocolPerformance <= MAX_PERFORMANCE_FEE);
        vm.assume(fees.tvl <= MAX_TVL_FEE);
        vm.assume(fees.performance <= MAX_PERFORMANCE_FEE);
        vm.assume(block.timestamp + parameters.snapshotDelay + parameters.timePassed < type(uint32).max);

        // Minimize scenarios where no fees are accrued
        uint32 lastFeeAccrual = uint32(block.timestamp);
        uint32 timestamp = lastFeeAccrual + parameters.snapshotDelay;
        uint32 finalizedAt = uint32(timestamp + DISPUTE_PERIOD);
        VaultSnapshot memory snapshot = VaultSnapshot({
            lastFeeAccrual: lastFeeAccrual,
            timestamp: timestamp,
            finalizedAt: finalizedAt,
            averageValue: parameters.averageValue,
            highestProfit: parameters.highestProfit,
            lastHighestProfit: parameters.lastHighestProfit
        });
        VaultAccruals memory accruals = VaultAccruals({ fees: fees, accruedProtocolFees: 0, accruedFees: 0 });

        MockDelayedFeeCalculator mockDelayedFeeCalculator =
            new MockDelayedFeeCalculator(address(this), Authority(address(0)), DISPUTE_PERIOD);
        mockDelayedFeeCalculator.setProtocolFeeRecipient(PROTOCOL_FEE_RECIPIENT);
        mockDelayedFeeCalculator.setProtocolFees(parameters.protocolTvl, parameters.protocolPerformance);
        mockDelayedFeeCalculator.setVaultSnapshot(BASE_VAULT, snapshot);
        mockDelayedFeeCalculator.setVaultAccruals(BASE_VAULT, accruals);

        uint256 expectedFee = _expectedFee(
            parameters.averageValue,
            parameters.highestProfit,
            parameters.lastHighestProfit,
            parameters.snapshotDelay,
            accruals.fees.tvl,
            accruals.fees.performance
        );
        uint256 expectedProtocolFee = _expectedFee(
            parameters.averageValue,
            parameters.highestProfit,
            parameters.lastHighestProfit,
            parameters.snapshotDelay,
            parameters.protocolTvl,
            parameters.protocolPerformance
        );

        vm.warp(timestamp + parameters.timePassed);
        mockDelayedFeeCalculator.accrueFees(BASE_VAULT);

        VaultSnapshot memory updatedSnapshot = mockDelayedFeeCalculator.getVaultSnapshot(BASE_VAULT);
        VaultAccruals memory updatedAccruals = mockDelayedFeeCalculator.getVaultAccruals(BASE_VAULT);

        assertGe(updatedAccruals.accruedFees, accruals.accruedFees, "accruedFees should never decrease after accrual");
        assertGe(
            updatedAccruals.accruedProtocolFees,
            accruals.accruedProtocolFees,
            "accruedProtocolFees should never decrease after accrual"
        );
        assertGe(
            updatedSnapshot.lastFeeAccrual,
            snapshot.lastFeeAccrual,
            "lastFeeAccrual should never decrease after accrual"
        );

        // Fees are accrued only if the dispute period has passed
        if (parameters.snapshotDelay > 0 && DISPUTE_PERIOD <= parameters.timePassed) {
            assertEq(
                updatedSnapshot.lastHighestProfit,
                parameters.highestProfit,
                "lastHighestProfit should be updated after accrual"
            );
            assertEq(
                updatedSnapshot.lastFeeAccrual, snapshot.timestamp, "lastFeeAccrual should be updated after accrual"
            );
            assertEq(
                updatedAccruals.accruedFees,
                expectedFee + accruals.accruedFees,
                "accruedFees should be updated correctly"
            );
            assertEq(
                updatedAccruals.accruedProtocolFees,
                expectedProtocolFee + accruals.accruedProtocolFees,
                "accruedProtocolFees should be updated correctly"
            );
            assertEq(updatedSnapshot.averageValue, 0, "averageValue should reset to 0 after accrual");
            assertEq(updatedSnapshot.highestProfit, 0, "highestProfit should reset to 0 after accrual");
            assertEq(updatedSnapshot.timestamp, 0, "timestamp should reset to 0 after accrual");
            assertEq(updatedSnapshot.finalizedAt, 0, "finalizedAt should reset to 0 after accrual");
        }
    }

    function _expectedProtocolFee(uint256 averageValue, uint256 highestProfit, uint256 timeDelta)
        internal
        pure
        returns (uint256)
    {
        return _expectedFee(averageValue, highestProfit, 0, timeDelta, PROTOCOL_TVL_FEE, PROTOCOL_PERFORMANCE_FEE);
    }

    function _expectedVaultFee(uint256 averageValue, uint256 highestProfit, uint256 timeDelta)
        internal
        pure
        returns (uint256)
    {
        return _expectedFee(averageValue, highestProfit, 0, timeDelta, VAULT_TVL_FEE, VAULT_PERFORMANCE_FEE);
    }

    function _expectedFee(
        uint256 averageValue,
        uint256 highestProfit,
        uint256 oldHighestProfit,
        uint256 timeDelta,
        uint16 tvlFee,
        uint16 performanceFee
    ) internal pure returns (uint256) {
        return _expectedTvlFee(averageValue, timeDelta, tvlFee)
            + _expectedPerformanceFee(highestProfit, oldHighestProfit, performanceFee);
    }

    function _expectedTvlFee(uint256 averageValue, uint256 timeDelta, uint16 tvlFee) internal pure returns (uint256) {
        return averageValue * tvlFee * timeDelta / ONE_IN_BPS / SECONDS_PER_YEAR;
    }

    function _expectedPerformanceFee(uint256 newHighestProfit, uint256 oldHighestProfit, uint16 performanceFee)
        internal
        pure
        returns (uint256)
    {
        if (newHighestProfit <= oldHighestProfit) {
            return 0;
        }

        uint256 profit;
        unchecked {
            profit = newHighestProfit - oldHighestProfit;
        }
        return profit * performanceFee / ONE_IN_BPS;
    }

    function _submitSnapshotAfter(uint256 averageValue, uint256 highestProfit, uint256 duration)
        internal
        returns (uint32 snapshotTimestamp)
    {
        skip(duration);
        snapshotTimestamp = uint32(vm.getBlockTimestamp());
        vm.prank(users.accountant);
        feeCalculator.submitSnapshot(
            BASE_VAULT, uint160(averageValue), uint128(highestProfit), uint32(snapshotTimestamp)
        );
    }
}
