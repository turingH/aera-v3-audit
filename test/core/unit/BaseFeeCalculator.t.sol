// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Math } from "@oz/utils/math/Math.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { MAX_PERFORMANCE_FEE, MAX_TVL_FEE, ONE_IN_BPS, SECONDS_PER_YEAR } from "src/core/Constants.sol";
import { VaultAccruals } from "src/core/Types.sol";
import { VaultAuth } from "src/core/VaultAuth.sol";
import { IBaseFeeCalculator } from "src/core/interfaces/IBaseFeeCalculator.sol";

import { MockBaseFeeCalculator } from "test/core/mocks/MockBaseFeeCalculator.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract BaseFeeCalculatorTest is BaseTest {
    MockBaseFeeCalculator public feeCalculator;

    function setUp() public override {
        super.setUp();

        feeCalculator = new MockBaseFeeCalculator(users.owner, Authority(address(0)));
    }

    ////////////////////////////////////////////////////////////
    //                       deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public view {
        assertEq(feeCalculator.owner(), users.owner);
        assertEq(address(feeCalculator.authority()), address(0));
    }

    ////////////////////////////////////////////////////////////
    //                setProtocolFeeRecipient                 //
    ////////////////////////////////////////////////////////////

    function test_setProtocolFeeRecipient_success() public {
        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true);
        emit IBaseFeeCalculator.ProtocolFeeRecipientSet(users.protocolFeeRecipient);
        feeCalculator.setProtocolFeeRecipient(users.protocolFeeRecipient);

        assertEq(feeCalculator.protocolFeeRecipient(), users.protocolFeeRecipient);
    }

    function test_setProtocolFeeRecipient_zeroAddress() public {
        vm.prank(users.owner);
        vm.expectRevert(IBaseFeeCalculator.Aera__ZeroAddressProtocolFeeRecipient.selector);
        feeCalculator.setProtocolFeeRecipient(address(0));
    }

    function test_setProtocolFeeRecipient_notOwner() public {
        vm.prank(users.stranger);
        vm.expectRevert("UNAUTHORIZED");
        feeCalculator.setProtocolFeeRecipient(users.protocolFeeRecipient);
    }

    ////////////////////////////////////////////////////////////
    //                    setProtocolFees                     //
    ////////////////////////////////////////////////////////////

    function test_setProtocolFees_success() public {
        vm.prank(users.owner);
        feeCalculator.setProtocolFeeRecipient(users.protocolFeeRecipient);

        uint16 newTvlFee = 200; // 2%
        uint16 newPerfFee = 2000; // 20%

        vm.expectEmit(true, true, true, true);
        emit IBaseFeeCalculator.ProtocolFeesSet(newTvlFee, newPerfFee);
        vm.prank(users.owner);
        feeCalculator.setProtocolFees(newTvlFee, newPerfFee);
        vm.snapshotGasLastCall("setProtocolFees - success");

        (uint16 tvlFee, uint16 perfFee) = feeCalculator.protocolFees();
        assertEq(tvlFee, newTvlFee, "tvl fee");
        assertEq(perfFee, newPerfFee, "performance fee");
    }

    function test_setProtocolFees_revertsWith_Unauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("UNAUTHORIZED");
        feeCalculator.setProtocolFees(100, 1000);
    }

    function test_setProtocolFees_revertsWith_TvlFeeTooHigh() public {
        uint16 tooHighTvlFee = uint16(MAX_TVL_FEE + 1); // 100%

        vm.expectRevert(IBaseFeeCalculator.Aera__TvlFeeTooHigh.selector);
        vm.prank(users.owner);
        feeCalculator.setProtocolFees(tooHighTvlFee, 1000);
    }

    function test_setProtocolFees_revertsWith_PerformanceFeeTooHigh() public {
        uint16 tooHighPerfFee = uint16(MAX_PERFORMANCE_FEE + 1); // 100%

        vm.expectRevert(IBaseFeeCalculator.Aera__PerformanceFeeTooHigh.selector);
        vm.prank(users.owner);
        feeCalculator.setProtocolFees(100, tooHighPerfFee);
    }

    function test_setProtocolFees_revertsWith_ZeroAddressProtocolFeeRecipient() public {
        vm.prank(users.owner);
        vm.expectRevert(IBaseFeeCalculator.Aera__ZeroAddressProtocolFeeRecipient.selector);
        feeCalculator.setProtocolFees(100, 100);
    }

    ////////////////////////////////////////////////////////////
    //                  setVaultAccountant                    //
    ////////////////////////////////////////////////////////////

    function test_setVaultAccountant_success() public {
        address newAccountant = makeAddr("accountant");

        vm.expectEmit(true, true, true, true);
        emit IBaseFeeCalculator.VaultAccountantSet(BASE_VAULT, newAccountant);
        vm.prank(users.owner);
        feeCalculator.setVaultAccountant(BASE_VAULT, newAccountant);
        vm.snapshotGasLastCall("setVaultAccountant - success");

        assertEq(feeCalculator.vaultAccountant(BASE_VAULT), newAccountant);
    }

    function test_setVaultAccountant_revertsWith_CallerIsNotAuthorized() public {
        address attacker = makeAddr("attacker");

        _mockCanCall(attacker, address(feeCalculator), IBaseFeeCalculator.setVaultAccountant.selector, false);

        vm.prank(attacker);
        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);
        feeCalculator.setVaultAccountant(BASE_VAULT, attacker);
    }

    ////////////////////////////////////////////////////////////
    //                     registerVault                      //
    ////////////////////////////////////////////////////////////

    function test_registerVault_success() public {
        feeCalculator.registerVault();
    }

    ////////////////////////////////////////////////////////////
    //                      setVaultFees                      //
    ////////////////////////////////////////////////////////////

    function test_setVaultFees_success() public {
        uint16 newTvlFee = 200; // 2%
        uint16 newPerfFee = 2000; // 20%

        vm.expectEmit(true, true, true, true);
        emit IBaseFeeCalculator.VaultFeesSet(BASE_VAULT, newTvlFee, newPerfFee);

        vm.prank(users.owner);
        feeCalculator.setVaultFees(BASE_VAULT, newTvlFee, newPerfFee);

        VaultAccruals memory vaultAccruals = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(vaultAccruals.fees.tvl, newTvlFee, "tvl fee");
        assertEq(vaultAccruals.fees.performance, newPerfFee, "performance fee");
        vm.snapshotGasLastCall("setVaultFees - success");
    }

    function test_setVaultFees_revertsWith_TvlFeeTooHigh() public {
        uint16 tooHighTvlFee = uint16(MAX_TVL_FEE + 1);

        vm.expectRevert(IBaseFeeCalculator.Aera__TvlFeeTooHigh.selector);
        vm.prank(users.owner);
        feeCalculator.setVaultFees(BASE_VAULT, tooHighTvlFee, 1000);
    }

    function test_setVaultFees_revertsWith_PerformanceFeeTooHigh() public {
        uint16 tooHighPerfFee = uint16(MAX_PERFORMANCE_FEE + 1);

        vm.expectRevert(IBaseFeeCalculator.Aera__PerformanceFeeTooHigh.selector);
        vm.prank(users.owner);
        feeCalculator.setVaultFees(BASE_VAULT, 100, tooHighPerfFee);
    }

    function test_setVaultFees_revertsWith_CallerIsNotVaultOwner() public {
        _mockCanCall(makeAddr("attacker"), address(feeCalculator), IBaseFeeCalculator.setVaultFees.selector, false);
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);
        feeCalculator.setVaultFees(BASE_VAULT, 100, 1000);
    }

    ////////////////////////////////////////////////////////////
    //                       claimFees                        //
    ////////////////////////////////////////////////////////////

    function test_fuzz_claimFees_success(VaultAccruals memory accruals, uint256 tokenBalance) public {
        feeCalculator.setVaultAccruals(BASE_VAULT, accruals);
        vm.prank(users.owner);
        feeCalculator.setProtocolFeeRecipient(users.protocolFeeRecipient);

        vm.prank(BASE_VAULT);
        (uint256 claimableVaultFee, uint256 claimableProtocolFee, address feeRecipient) =
            feeCalculator.claimFees(tokenBalance);

        uint256 expectedClaimableProtocolFee = Math.min(tokenBalance, accruals.accruedProtocolFees);
        uint256 expectedClaimableVaultFee = Math.min(tokenBalance - expectedClaimableProtocolFee, accruals.accruedFees);

        assertEq(claimableVaultFee, expectedClaimableVaultFee, "claimableVaultFee");
        assertEq(claimableProtocolFee, expectedClaimableProtocolFee, "claimableProtocolFee");
        assertEq(feeRecipient, users.protocolFeeRecipient, "feeRecipient");

        VaultAccruals memory updatedAccruals = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(updatedAccruals.accruedFees, accruals.accruedFees - expectedClaimableVaultFee, "accruedFees");
        assertEq(
            updatedAccruals.accruedProtocolFees,
            accruals.accruedProtocolFees - expectedClaimableProtocolFee,
            "accruedProtocolFees"
        );
        assertGe(tokenBalance, claimableVaultFee + claimableProtocolFee, "Claimable fees exceed token balance");
    }

    ////////////////////////////////////////////////////////////
    //                   claimProtocolFees                    //
    ////////////////////////////////////////////////////////////

    function test_fuzz_claimProtocolFees_success(VaultAccruals memory accruals, uint256 tokenBalance) public {
        feeCalculator.setVaultAccruals(BASE_VAULT, accruals);
        vm.prank(users.owner);
        feeCalculator.setProtocolFeeRecipient(users.protocolFeeRecipient);

        vm.prank(BASE_VAULT);
        (uint256 claimableProtocolFee, address feeRecipient) = feeCalculator.claimProtocolFees(tokenBalance);

        assertEq(claimableProtocolFee, Math.min(tokenBalance, accruals.accruedProtocolFees), "claimableProtocolFee");
        assertEq(feeRecipient, users.protocolFeeRecipient, "feeRecipient");

        VaultAccruals memory updatedAccruals = feeCalculator.vaultFeeState(BASE_VAULT);
        assertEq(
            updatedAccruals.accruedProtocolFees,
            accruals.accruedProtocolFees - claimableProtocolFee,
            "accruedProtocolFees"
        );
        assertGe(tokenBalance, claimableProtocolFee, "Claimable protocol fees exceed token balance");
    }

    ////////////////////////////////////////////////////////////
    //                      calculateFees                     //
    ////////////////////////////////////////////////////////////

    function test_fuzz_calculateTvlFee_success(uint160 averageValue, uint16 tvlFee, uint32 timeDelta) public view {
        uint256 expected = uint256(averageValue) * tvlFee * timeDelta / ONE_IN_BPS / SECONDS_PER_YEAR;
        assertEq(feeCalculator.calculateTvlFee(averageValue, tvlFee, timeDelta), expected, "calculateTvlFee");
    }

    function test_fuzz_calculatePerformanceFee_success(uint128 profit, uint16 performanceFee) public view {
        uint256 expected = uint256(profit) * performanceFee / ONE_IN_BPS;
        assertEq(feeCalculator.calculatePerformanceFee(profit, performanceFee), expected, "calculatePerformanceFee");
    }
}
