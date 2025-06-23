// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Ownable } from "@oz/access/Ownable.sol";
import { IERC20 } from "@oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

import { Math } from "@oz/utils/math/Math.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import {
    MAX_PERFORMANCE_FEE, MAX_TVL_FEE, ONE_DAY, ONE_IN_BPS, ONE_MINUTE, SECONDS_PER_YEAR
} from "src/core/Constants.sol";
import { PriceAndFeeCalculator } from "src/core/PriceAndFeeCalculator.sol";

import { Fee, VaultAccruals, VaultPriceState } from "src/core/Types.sol";

import { IBaseFeeCalculator } from "src/core/interfaces/IBaseFeeCalculator.sol";
import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";

import { console } from "forge-std/console.sol";
import { VaultAuth } from "src/core/VaultAuth.sol";
import { IHasNumeraire } from "src/core/interfaces/IHasNumeraire.sol";
import { IPriceAndFeeCalculator } from "src/core/interfaces/IPriceAndFeeCalculator.sol";
import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { MockPriceAndFeeCalculator } from "test/core/mocks/MockPriceAndFeeCalculator.sol";

contract PriceAndFeeCalculatorTest is BaseTest {
    PriceAndFeeCalculator internal priceAndFeeCalculator;

    uint256 internal constant UNIT_PRICE_PRECISION = 1e18;

    uint16 internal constant MAX_PRICE_TOLERANCE_RATIO = 11_000;
    uint16 internal constant MIN_PRICE_TOLERANCE_RATIO = 9000;
    uint16 internal constant MIN_UPDATE_INTERVAL_MINUTES = 1000;
    uint8 internal constant MAX_PRICE_AGE = 24;
    uint8 internal constant MAX_UPDATE_DELAY_DAYS = 1;

    uint16 internal constant VAULT_TVL_FEE = 100;
    uint16 internal constant VAULT_PERFORMANCE_FEE = 1000;
    uint16 internal constant PROTOCOL_TVL_FEE = 50;
    uint16 internal constant PROTOCOL_PERFORMANCE_FEE = 200;

    address internal immutable NUMERAIRE = makeAddr("NUMERAIRE");
    uint256 internal constant NUMERAIRE_TOKEN_DECIMALS = 18;
    address internal immutable ORACLE_REGISTRY = makeAddr("ORACLE_REGISTRY");
    address internal immutable NEW_VAULT = makeAddr("NEW_VAULT");
    uint128 internal constant INITIAL_UNIT_PRICE = 1e18;
    uint128 internal constant INITIAL_TOTAL_SUPPLY = 1e20;

    uint256 internal constant TOKEN_SCALAR = 1e18;

    uint32 internal INITIAL_TIMESTAMP;

    struct AccrueFeesParameters {
        uint8 maxPriceAge;
        uint16 minUpdateIntervalMinutes;
        uint16 maxPriceToleranceRatio;
        uint16 minPriceToleranceRatio;
        uint8 maxUpdateDelayDays;
        uint32 timestamp;
        uint24 accrualLag;
        uint128 unitPrice;
        uint128 highestPrice;
        uint128 lastTotalSupply;
        uint16 protocolTvl;
        uint16 protocolPerformance;
        uint96 price;
        uint32 timeDelta;
    }

    function setUp() public override {
        super.setUp();

        INITIAL_TIMESTAMP = uint32(vm.getBlockTimestamp());

        vm.mockCall(
            address(NUMERAIRE),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(NUMERAIRE_TOKEN_DECIMALS)
        );

        priceAndFeeCalculator = new PriceAndFeeCalculator(
            IERC20(NUMERAIRE), IOracleRegistry(ORACLE_REGISTRY), users.owner, Authority(address(0))
        );

        vm.mockCall(BASE_VAULT, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(INITIAL_TOTAL_SUPPLY));
        vm.mockCall(NEW_VAULT, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(INITIAL_TOTAL_SUPPLY));

        vm.prank(BASE_VAULT);
        priceAndFeeCalculator.registerVault();

        vm.prank(users.owner);
        priceAndFeeCalculator.setVaultAccountant(BASE_VAULT, users.owner);

        vm.prank(users.owner);
        priceAndFeeCalculator.setThresholds(
            BASE_VAULT,
            MIN_PRICE_TOLERANCE_RATIO,
            MAX_PRICE_TOLERANCE_RATIO,
            MIN_UPDATE_INTERVAL_MINUTES,
            MAX_PRICE_AGE,
            MAX_UPDATE_DELAY_DAYS
        );
        vm.prank(users.owner);
        priceAndFeeCalculator.setInitialPrice(BASE_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);

        vm.mockCall(NEW_VAULT, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.owner));
    }

    ////////////////////////////////////////////////////////////
    //                       deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public {
        PriceAndFeeCalculator newPriceAndFeeCalculator = new PriceAndFeeCalculator(
            IERC20(NUMERAIRE), IOracleRegistry(ORACLE_REGISTRY), users.owner, Authority(address(0))
        );

        assertEq(
            address(newPriceAndFeeCalculator.ORACLE_REGISTRY()), ORACLE_REGISTRY, "ORACLE_REGISTRY not set correctly"
        );
        assertEq(address(newPriceAndFeeCalculator.NUMERAIRE()), NUMERAIRE, "NUMERAIRE not set correctly");
    }

    function test_deployment_revertsWith_ZeroAddressOracleRegistry() public {
        vm.expectRevert(IPriceAndFeeCalculator.Aera__ZeroAddressOracleRegistry.selector);
        new PriceAndFeeCalculator(IERC20(NUMERAIRE), IOracleRegistry(address(0)), users.owner, Authority(address(0)));
    }

    function test_deployment_revertsWith_NumeraireZeroAddress() public {
        vm.expectRevert(IHasNumeraire.Aera__ZeroAddressNumeraire.selector);
        new PriceAndFeeCalculator(
            IERC20(address(0)), IOracleRegistry(ORACLE_REGISTRY), users.owner, Authority(address(0))
        );
    }

    ////////////////////////////////////////////////////////////
    //                     registerVault                      //
    ////////////////////////////////////////////////////////////

    function test_registerVault_success() public {
        vm.mockCall(NEW_VAULT, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(INITIAL_TOTAL_SUPPLY));

        vm.expectEmit(true, false, false, true, address(priceAndFeeCalculator));
        emit IFeeCalculator.VaultRegistered(NEW_VAULT);

        vm.prank(NEW_VAULT);
        priceAndFeeCalculator.registerVault();

        vm.snapshotGasLastCall("registerVault - success");

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(NEW_VAULT);

        assertEq(vaultPrice.maxPriceToleranceRatio, 0, "maxPriceToleranceRatio not set correctly");
        assertEq(vaultPrice.minPriceToleranceRatio, 0, "minPriceToleranceRatio not set correctly");
        assertEq(vaultPrice.minUpdateIntervalMinutes, 0, "minUpdateIntervalMinutes not set correctly");
        assertEq(vaultPrice.maxPriceAge, 0, "maxPriceAge not set correctly");
        assertEq(vaultPrice.paused, false, "paused not set correctly");

        assertEq(vaultPrice.timestamp, uint32(block.timestamp), "timestamp not set correctly");
        assertEq(vaultPrice.unitPrice, 0, "unitPrice not set correctly");
        assertEq(vaultPrice.highestPrice, 0, "highestPrice not set correctly");
        assertEq(vaultPrice.lastTotalSupply, 0, "lastTotalSupply not set correctly");
        assertEq(vaultPrice.accrualLag, 0, "accrualLag not set correctly");
    }

    function test_registerVault_revertsWith_VaultAlreadyRegistered() public {
        vm.prank(BASE_VAULT);
        vm.expectRevert(IFeeCalculator.Aera__VaultAlreadyRegistered.selector);
        priceAndFeeCalculator.registerVault();
    }

    ////////////////////////////////////////////////////////////
    //                     setInitialPrice                    //
    ////////////////////////////////////////////////////////////

    function test_setInitialPrice_success() public {
        PriceAndFeeCalculator newPriceAndFeeCalculator = _deployNewPriceAndFeeCalculator();

        _setDefaultThresholds(newPriceAndFeeCalculator, NEW_VAULT);

        vm.expectEmit(true, false, false, true, address(newPriceAndFeeCalculator));
        emit IPriceAndFeeCalculator.UnitPriceUpdated(NEW_VAULT, INITIAL_UNIT_PRICE, uint32(vm.getBlockTimestamp()));

        vm.prank(users.owner);
        newPriceAndFeeCalculator.setInitialPrice(NEW_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);

        (VaultPriceState memory vaultPrice,) = newPriceAndFeeCalculator.getVaultState(NEW_VAULT);

        assertEq(vaultPrice.timestamp, uint32(vm.getBlockTimestamp()), "timestamp not set correctly");
        assertEq(vaultPrice.unitPrice, INITIAL_UNIT_PRICE, "unitPrice not set correctly");
        assertEq(vaultPrice.highestPrice, INITIAL_UNIT_PRICE, "highestPrice not set correctly");
        assertEq(vaultPrice.lastTotalSupply, INITIAL_TOTAL_SUPPLY, "lastTotalSupply not set correctly");
        assertEq(vaultPrice.accrualLag, 0, "accrualLag not set correctly");
    }

    function test_setInitialPrice_revertsWith_CallerNotVaultOwner() public {
        PriceAndFeeCalculator newPriceAndFeeCalculator = _deployNewPriceAndFeeCalculator();
        vm.mockCall(NEW_VAULT, abi.encodeWithSelector(bytes4(keccak256("owner()"))), abi.encode(users.alice));
        vm.mockCall(NEW_VAULT, abi.encodeWithSelector(bytes4(keccak256("authority()"))), abi.encode(AUTHORITY));
        _mockCanCall(
            makeAddr("NOT_OWNER"),
            address(newPriceAndFeeCalculator),
            IPriceAndFeeCalculator.setInitialPrice.selector,
            false
        );

        vm.prank(makeAddr("NOT_OWNER"));
        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);
        newPriceAndFeeCalculator.setInitialPrice(NEW_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);
    }

    function test_setInitialPrice_revertsWith_InvalidPrice() public {
        PriceAndFeeCalculator newPriceAndFeeCalculator = _deployNewPriceAndFeeCalculator();

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__InvalidPrice.selector);
        newPriceAndFeeCalculator.setInitialPrice(NEW_VAULT, 0, INITIAL_TIMESTAMP);
    }

    function test_setInitialPrice_revertsWith_ThresholdNotSet() public {
        PriceAndFeeCalculator newPriceAndFeeCalculator = _deployNewPriceAndFeeCalculator();

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__ThresholdNotSet.selector);
        newPriceAndFeeCalculator.setInitialPrice(NEW_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);
    }

    function test_setInitialPrice_revertsWith_VaultAlreadyInitialized() public {
        PriceAndFeeCalculator newPriceAndFeeCalculator = _deployNewPriceAndFeeCalculator();

        _setDefaultThresholds(newPriceAndFeeCalculator, NEW_VAULT);

        vm.prank(users.owner);
        newPriceAndFeeCalculator.setInitialPrice(NEW_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultAlreadyInitialized.selector);
        newPriceAndFeeCalculator.setInitialPrice(NEW_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);
    }

    function test_setInitialPrice_revertsWith_StalePrice() public {
        PriceAndFeeCalculator newPriceAndFeeCalculator = _deployNewPriceAndFeeCalculator();

        _setDefaultThresholds(newPriceAndFeeCalculator, NEW_VAULT);

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__StalePrice.selector);
        newPriceAndFeeCalculator.setInitialPrice(NEW_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP - MAX_PRICE_AGE - 1);
    }

    ////////////////////////////////////////////////////////////
    //                     setThresholds                      //
    ////////////////////////////////////////////////////////////

    function test_setThresholds_success() public {
        uint16 newMaxPriceToleranceRatio = 12_000;
        uint16 newMinPriceToleranceRatio = 8000;
        uint16 newMinUpdateIntervalMinutes = 12;
        uint8 newMaxPriceAge = 24;
        uint8 newMaxUpdateDelayDays = 5;

        vm.expectEmit(true, false, false, true, address(priceAndFeeCalculator));
        emit IPriceAndFeeCalculator.ThresholdsSet(
            BASE_VAULT,
            newMinPriceToleranceRatio,
            newMaxPriceToleranceRatio,
            newMinUpdateIntervalMinutes,
            newMaxPriceAge
        );

        vm.prank(users.owner);
        priceAndFeeCalculator.setThresholds(
            BASE_VAULT,
            newMinPriceToleranceRatio,
            newMaxPriceToleranceRatio,
            newMinUpdateIntervalMinutes,
            newMaxPriceAge,
            newMaxUpdateDelayDays
        );

        vm.snapshotGasLastCall("setThresholds - success");

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(
            vaultPrice.maxPriceToleranceRatio, newMaxPriceToleranceRatio, "maxPriceToleranceRatio not set correctly"
        );
        assertEq(
            vaultPrice.minPriceToleranceRatio, newMinPriceToleranceRatio, "minPriceToleranceRatio not set correctly"
        );
        assertEq(
            vaultPrice.minUpdateIntervalMinutes,
            newMinUpdateIntervalMinutes,
            "minUpdateIntervalMinutes not set correctly"
        );
        assertEq(vaultPrice.maxPriceAge, newMaxPriceAge, "maxPriceAge not set correctly");

        assertEq(vaultPrice.accrualLag, 0, "accrualLag not set correctly");
        assertEq(vaultPrice.timestamp, uint32(block.timestamp), "timestamp not set correctly");
        assertEq(vaultPrice.paused, false, "paused not set correctly");
        assertEq(vaultPrice.unitPrice, INITIAL_UNIT_PRICE, "unitPrice not set correctly");
        assertEq(vaultPrice.highestPrice, INITIAL_UNIT_PRICE, "highestPrice not set correctly");
        assertEq(vaultPrice.lastTotalSupply, INITIAL_TOTAL_SUPPLY, "lastTotalSupply not set correctly");
    }

    function test_setThresholds_revertsWith_InvalidMinPriceToleranceRatio() public {
        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__InvalidMinPriceToleranceRatio.selector);
        priceAndFeeCalculator.setThresholds(
            BASE_VAULT,
            uint16(ONE_IN_BPS + 1),
            MAX_PRICE_TOLERANCE_RATIO,
            MIN_UPDATE_INTERVAL_MINUTES,
            MAX_PRICE_AGE,
            MAX_UPDATE_DELAY_DAYS
        );
    }

    function test_setThresholds_revertsWith_InvalidMaxPriceToleranceRatio() public {
        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__InvalidMaxPriceToleranceRatio.selector);
        priceAndFeeCalculator.setThresholds(
            BASE_VAULT,
            MIN_PRICE_TOLERANCE_RATIO,
            uint16(ONE_IN_BPS - 1),
            MIN_UPDATE_INTERVAL_MINUTES,
            MAX_PRICE_AGE,
            MAX_UPDATE_DELAY_DAYS
        );
    }

    function test_setThresholds_revertsWith_InvalidMaxPriceAge() public {
        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__InvalidMaxPriceAge.selector);
        priceAndFeeCalculator.setThresholds(
            BASE_VAULT,
            MIN_PRICE_TOLERANCE_RATIO,
            MAX_PRICE_TOLERANCE_RATIO,
            MIN_UPDATE_INTERVAL_MINUTES,
            0,
            MAX_UPDATE_DELAY_DAYS
        );
    }

    function test_setThresholds_revertsWith_InvalidMaxUpdateDelayDays() public {
        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__InvalidMaxUpdateDelayDays.selector);
        priceAndFeeCalculator.setThresholds(
            BASE_VAULT,
            MIN_PRICE_TOLERANCE_RATIO,
            MAX_PRICE_TOLERANCE_RATIO,
            MIN_UPDATE_INTERVAL_MINUTES,
            MAX_PRICE_AGE,
            0
        );
    }

    function test_setThresholds_revertsWith_VaultNotRegistered() public {
        address unregisteredVault = makeAddr("UNREGISTERED_VAULT");

        vm.mockCall(unregisteredVault, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.owner));
        vm.mockCall(
            unregisteredVault, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(INITIAL_TOTAL_SUPPLY)
        );

        vm.prank(users.owner);
        vm.expectRevert(IBaseFeeCalculator.Aera__VaultNotRegistered.selector);
        priceAndFeeCalculator.setThresholds(
            unregisteredVault,
            MIN_PRICE_TOLERANCE_RATIO,
            MAX_PRICE_TOLERANCE_RATIO,
            MIN_UPDATE_INTERVAL_MINUTES,
            MAX_PRICE_AGE,
            MAX_UPDATE_DELAY_DAYS
        );
    }

    function test_setThresholds_revertsWith_CallerIsNotAuthorized() public {
        _mockCanCall(
            address(this), address(priceAndFeeCalculator), IPriceAndFeeCalculator.setThresholds.selector, false
        );

        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);
        priceAndFeeCalculator.setThresholds(
            BASE_VAULT,
            MIN_PRICE_TOLERANCE_RATIO,
            MAX_PRICE_TOLERANCE_RATIO,
            MIN_UPDATE_INTERVAL_MINUTES,
            MAX_PRICE_AGE,
            MAX_UPDATE_DELAY_DAYS
        );
    }

    ////////////////////////////////////////////////////////////
    //                     setUnitPrice                      //
    ////////////////////////////////////////////////////////////

    function test_setUnitPrice_success_no_pause() public {
        uint128 initialPrice = INITIAL_UNIT_PRICE + 1;

        uint32 timestamp = uint32(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);
        vm.warp(timestamp + MAX_PRICE_AGE - 1);

        vm.expectEmit(true, false, false, true, address(priceAndFeeCalculator));
        emit IPriceAndFeeCalculator.UnitPriceUpdated(BASE_VAULT, initialPrice, timestamp);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, initialPrice, timestamp);

        vm.snapshotGasLastCall("setUnitPrice - success - no pause");

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.unitPrice, initialPrice, "Unit price not set correctly");
        assertEq(vaultPrice.timestamp, timestamp, "Timestamp not set correctly");
        assertEq(vaultPrice.paused, false, "Contract should not be paused");
    }

    function test_setUnitPrice_success_paused_minUpdateInterval() public {
        uint128 price = INITIAL_UNIT_PRICE + 1;
        uint32 timestamp = uint32(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE) - 1;
        vm.warp(timestamp);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.VaultPausedChanged(BASE_VAULT, true);
        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.UnitPriceUpdated(BASE_VAULT, price, timestamp);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, timestamp);

        vm.snapshotGasLastCall("setUnitPrice - success - paused minUpdateIntervalMinutes");

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.unitPrice, price, "Unit price not updated correctly");
        assertEq(vaultPrice.timestamp, timestamp, "Timestamp not updated correctly");
        assertEq(vaultPrice.paused, true, "Contract should be paused due to minimum update interval");
        assertEq(
            vaultPrice.minPriceToleranceRatio, MIN_PRICE_TOLERANCE_RATIO, "minPriceToleranceRatio not set correctly"
        );
        assertEq(
            vaultPrice.maxPriceToleranceRatio, MAX_PRICE_TOLERANCE_RATIO, "maxPriceToleranceRatio not set correctly"
        );
        assertEq(
            vaultPrice.minUpdateIntervalMinutes,
            MIN_UPDATE_INTERVAL_MINUTES,
            "minUpdateIntervalMinutes not set correctly"
        );
        assertEq(vaultPrice.maxPriceAge, MAX_PRICE_AGE, "maxPriceAge not set correctly");
    }

    function test_setUnitPrice_success_paused_maxPriceToleranceRatio() public {
        uint128 price = uint128(INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS + 1);
        uint32 timestamp = uint32(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);
        vm.warp(timestamp);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, timestamp);

        vm.snapshotGasLastCall("setUnitPrice - success - paused maxPriceToleranceRatio");

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.unitPrice, price, "Unit price not updated correctly");
        assertEq(vaultPrice.timestamp, timestamp, "Timestamp not updated correctly");
        assertEq(vaultPrice.paused, true, "Contract should be paused due to max price tolerance ratio");
    }

    function test_setUnitPrice_success_paused_minPriceToleranceRatio() public {
        uint128 price = uint128(INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS - 1);
        uint32 timestamp = uint32(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);
        vm.warp(timestamp);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, timestamp);

        vm.snapshotGasLastCall("setUnitPrice - success - paused minPriceToleranceRatio");

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.unitPrice, price, "Unit price not updated correctly");
        assertEq(vaultPrice.timestamp, timestamp, "Timestamp not updated correctly");
        assertEq(vaultPrice.paused, true, "Contract should be paused due to min price tolerance ratio");
    }

    function test_setUnitPrice_success_paused_maxTimeBetweenUpdates() public {
        uint128 price = INITIAL_UNIT_PRICE + 1;

        skip(MAX_UPDATE_DELAY_DAYS * ONE_DAY + 1);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.VaultPausedChanged(BASE_VAULT, true);
        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.UnitPriceUpdated(BASE_VAULT, price, uint32(block.timestamp));
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, uint32(block.timestamp));

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.unitPrice, price, "Unit price not updated correctly");
        assertEq(vaultPrice.timestamp, uint32(block.timestamp), "Timestamp not updated correctly");
        assertEq(vaultPrice.paused, true, "Contract should be paused due to min price tolerance ratio");
    }

    function test_setUnitPrice_success_accrueFees_increasedExchangeRate() public {
        _setupFees();

        uint128 price = uint128(INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS);
        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, uint32(vm.getBlockTimestamp()));

        vm.snapshotGasLastCall("setUnitPrice - success - accrueFees increased exchange rate");

        (, VaultAccruals memory vaultAccruals) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        (uint256 accruedVaultFeesView, uint256 accruedProtocolFeesView) =
            priceAndFeeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        (uint256 expectedVaultFeesEarned, uint256 expectedProtocolFeesEarned) =
            _expectedFees(INITIAL_UNIT_PRICE, INITIAL_TOTAL_SUPPLY, price);

        assertEq(vaultAccruals.accruedFees, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");
        assertEq(accruedVaultFeesView, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");

        assertEq(
            vaultAccruals.accruedProtocolFees,
            expectedProtocolFeesEarned,
            "Protocol accrued fees not calculated correctly"
        );
        assertEq(accruedProtocolFeesView, expectedProtocolFeesEarned, "Protocol accrued fees not calculated correctly");
    }

    function test_setUnitPrice_success_accrueFees_decreasedExchangeRate() public {
        _setupFees();

        uint128 price = uint128(INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS);
        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, uint32(vm.getBlockTimestamp()));

        vm.snapshotGasLastCall("setUnitPrice - success - accrueFees decreased exchange rate");

        (, VaultAccruals memory vaultAccruals) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        (uint256 accruedVaultFeesView, uint256 accruedProtocolFeesView) =
            priceAndFeeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        (uint256 expectedVaultFeesEarned, uint256 expectedProtocolFeesEarned) =
            _expectedFees(price, INITIAL_TOTAL_SUPPLY, price);

        assertEq(vaultAccruals.accruedFees, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");
        assertEq(accruedVaultFeesView, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");

        assertEq(
            vaultAccruals.accruedProtocolFees,
            expectedProtocolFeesEarned,
            "Protocol accrued fees not calculated correctly"
        );
        assertEq(accruedProtocolFeesView, expectedProtocolFeesEarned, "Protocol accrued fees not calculated correctly");
    }

    function test_setUnitPrice_success_accrueFees_decreasedTotalSupply() public {
        _setupFees();

        uint256 totalSupply = INITIAL_TOTAL_SUPPLY / 2;
        vm.mockCall(BASE_VAULT, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply));

        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, INITIAL_UNIT_PRICE, uint32(vm.getBlockTimestamp()));

        vm.snapshotGasLastCall("setUnitPrice - success - accrueFees decreased total supply");

        (, VaultAccruals memory vaultAccruals) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        (uint256 accruedVaultFeesView, uint256 accruedProtocolFeesView) =
            priceAndFeeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        (uint256 expectedVaultFeesEarned, uint256 expectedProtocolFeesEarned) =
            _expectedFees(INITIAL_UNIT_PRICE, totalSupply, INITIAL_UNIT_PRICE);

        assertEq(vaultAccruals.accruedFees, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");
        assertEq(accruedVaultFeesView, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");

        assertEq(
            vaultAccruals.accruedProtocolFees,
            expectedProtocolFeesEarned,
            "Protocol accrued fees not calculated correctly"
        );
        assertEq(accruedProtocolFeesView, expectedProtocolFeesEarned, "Protocol accrued fees not calculated correctly");
    }

    function test_setUnitPrice_success_accrueFees_afterPausedVault() public {
        _setupFees();

        uint128 price = uint128(INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS + 1); // paused due to max
            // price tolerance ratio
        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, uint32(vm.getBlockTimestamp()));
        (VaultPriceState memory vaultPrice, VaultAccruals memory vaultAccruals) =
            priceAndFeeCalculator.getVaultState(BASE_VAULT);

        assertTrue(vaultPrice.paused, "Vault should be paused");
        assertEq(vaultAccruals.accruedFees, 0, "Vault accrued fees should be 0");
        assertEq(vaultAccruals.accruedProtocolFees, 0, "Protocol accrued fees should be 0");
        assertEq(vaultPrice.accrualLag, block.timestamp - INITIAL_TIMESTAMP, "Accrual lag");

        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, uint32(block.timestamp));

        (vaultPrice, vaultAccruals) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultAccruals.accruedFees, 0, "Vault accrued fees should be 0");
        assertEq(vaultAccruals.accruedProtocolFees, 0, "Protocol accrued fees should be 0");
        assertEq(vaultPrice.accrualLag, block.timestamp - INITIAL_TIMESTAMP, "Accrual lag");

        vm.prank(users.owner);
        priceAndFeeCalculator.unpauseVault(BASE_VAULT, price, uint32(block.timestamp));

        (vaultPrice, vaultAccruals) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertNotEq(vaultAccruals.accruedFees, 0, "Vault accrued fees should be 0");
        assertNotEq(vaultAccruals.accruedProtocolFees, 0, "Protocol accrued fees should be 0");
        assertEq(vaultPrice.accrualLag, 0, "Accrual lag");

        (uint256 expectedVaultFeesEarned, uint256 expectedProtocolFeesEarned) =
            _expectedFees(price, INITIAL_TOTAL_SUPPLY, price);

        assertEq(vaultAccruals.accruedFees, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");
        assertEq(
            vaultAccruals.accruedProtocolFees,
            expectedProtocolFeesEarned,
            "Protocol accrued fees not calculated correctly"
        );
    }

    function test_setUnitPrice_success_paused_noAccruals() public {
        _setupFees();

        uint128 price = uint128(INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS + 1); // paused due to max
            // price tolerance ratio
        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, uint32(vm.getBlockTimestamp()));

        (VaultPriceState memory vaultPrice, VaultAccruals memory vaultAccruals) =
            priceAndFeeCalculator.getVaultState(BASE_VAULT);
        (uint256 accruedVaultFeesView, uint256 accruedProtocolFeesView) =
            priceAndFeeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        assertTrue(vaultPrice.paused, "Vault should be paused");
        assertEq(vaultAccruals.accruedFees, 0, "Vault accrued fees should be 0");
        assertEq(vaultAccruals.accruedProtocolFees, 0, "Protocol accrued fees should be 0");
        assertEq(accruedVaultFeesView, 0, "Vault accrued fees should be 0");
        assertEq(accruedProtocolFeesView, 0, "Protocol accrued fees should be 0");
    }

    function test_setUnitPrice_success_whenPaused() public {
        _setupFees();

        uint128 price = uint128(INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS + 1); // paused due to max
            // price tolerance ratio
        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, uint32(vm.getBlockTimestamp()));

        skip(1 hours);
        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price + 1, uint32(vm.getBlockTimestamp()));

        (VaultPriceState memory vaultPrice, VaultAccruals memory vaultAccruals) =
            priceAndFeeCalculator.getVaultState(BASE_VAULT);
        (uint256 accruedVaultFeesView, uint256 accruedProtocolFeesView) =
            priceAndFeeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        assertTrue(vaultPrice.paused, "Vault should be paused");
        assertEq(vaultAccruals.accruedFees, 0, "Vault accrued fees should be 0");
        assertEq(vaultAccruals.accruedProtocolFees, 0, "Protocol accrued fees should be 0");
        assertEq(accruedVaultFeesView, 0, "Vault accrued fees should be 0");
        assertEq(accruedProtocolFeesView, 0, "Protocol accrued fees should be 0");
        assertEq(vaultPrice.unitPrice, price + 1, "Unit price should be updated");
        assertEq(vaultPrice.timestamp, vm.getBlockTimestamp(), "Timestamp should not be updated");
    }

    function test_setUnitPrice_revertsWith_InvalidPrice() public {
        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__InvalidPrice.selector);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, 0, uint32(vm.getBlockTimestamp()));
    }

    function test_setUnitPrice_revertsWith_TimestampMustBeAfterLastUpdate() public {
        uint128 price = INITIAL_UNIT_PRICE + 1;
        uint32 timestamp = uint32(vm.getBlockTimestamp());

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__TimestampMustBeAfterLastUpdate.selector);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, timestamp);
    }

    function test_setUnitPrice_revertsWith_TimestampCantBeInFuture() public {
        uint128 price = INITIAL_UNIT_PRICE + 1;
        uint32 futureTimestamp = uint32(vm.getBlockTimestamp() + MAX_PRICE_AGE + 1);

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__TimestampCantBeInFuture.selector);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, futureTimestamp);
    }

    function test_setUnitPrice_revertsWith_ThresholdNotSet() public {
        PriceAndFeeCalculator newPriceAndFeeCalculator = _deployNewPriceAndFeeCalculator();

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__ThresholdNotSet.selector);
        newPriceAndFeeCalculator.setInitialPrice(NEW_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);
    }

    function test_setUnitPrice_revertsWith_StalePrice() public {
        uint128 price = INITIAL_UNIT_PRICE + 1;
        uint32 timestamp = uint32(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.warp(timestamp + MAX_PRICE_AGE + 1);

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__StalePrice.selector);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, timestamp);
    }

    function test_setUnitPrice_revertsWith_NotVaultAccountant() public {
        uint128 price = INITIAL_UNIT_PRICE + 1;
        uint32 timestamp = uint32(vm.getBlockTimestamp());

        vm.expectRevert(IBaseFeeCalculator.Aera__CallerIsNotVaultAccountant.selector);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, timestamp);
    }

    ////////////////////////////////////////////////////////////
    //                     pauseVault                         //
    ////////////////////////////////////////////////////////////

    function test_pauseVault_success_owner() public {
        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.VaultPausedChanged(BASE_VAULT, true);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.paused, true, "Vault should be paused");
    }

    function test_pauseVault_success_authorized() public {
        _mockCanCall(address(this), address(priceAndFeeCalculator), IPriceAndFeeCalculator.pauseVault.selector, true);

        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.VaultPausedChanged(BASE_VAULT, true);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.paused, true, "Vault should be paused");
    }

    function test_pauseVault_success_accountant() public {
        _mockCanCall(users.accountant, address(priceAndFeeCalculator), IPriceAndFeeCalculator.pauseVault.selector, true);
        vm.prank(users.accountant);

        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.VaultPausedChanged(BASE_VAULT, true);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.paused, true, "Vault should be paused");
    }

    function test_pauseVault_revertsWith_CallerIsNotAuthorized() public {
        _mockCanCall(
            makeAddr("attacker"), address(priceAndFeeCalculator), IPriceAndFeeCalculator.pauseVault.selector, false
        );

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);
    }

    function test_pauseVault_revertsWith_VaultPaused() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultPaused.selector);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);
    }

    ////////////////////////////////////////////////////////////
    //                     unpauseVault                       //
    ////////////////////////////////////////////////////////////

    function test_unpauseVault_success_owner() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.VaultPausedChanged(BASE_VAULT, false);
        priceAndFeeCalculator.unpauseVault(BASE_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.paused, false, "Vault should be unpaused");
    }

    function test_unpauseVault_success_authorized() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        _mockCanCall(address(this), address(priceAndFeeCalculator), IPriceAndFeeCalculator.unpauseVault.selector, true);

        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.VaultPausedChanged(BASE_VAULT, false);
        priceAndFeeCalculator.unpauseVault(BASE_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.paused, false, "Vault should be unpaused");
    }

    function test_unpauseVault_success_accountant() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        _mockCanCall(
            users.accountant, address(priceAndFeeCalculator), IPriceAndFeeCalculator.unpauseVault.selector, true
        );
        vm.prank(users.accountant);

        vm.expectEmit(true, false, false, true);
        emit IPriceAndFeeCalculator.VaultPausedChanged(BASE_VAULT, false);
        priceAndFeeCalculator.unpauseVault(BASE_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);

        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.paused, false, "Vault should be unpaused");
    }

    function test_unpauseVault_success_accrueFees() public {
        _setupFees();

        uint128 price = uint128(INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS + 1); // paused due to max
            // price tolerance ratio
        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, price, uint32(vm.getBlockTimestamp()));

        vm.prank(users.owner);
        priceAndFeeCalculator.unpauseVault(BASE_VAULT, price, uint32(vm.getBlockTimestamp()));

        (VaultPriceState memory vaultPrice, VaultAccruals memory vaultAccruals) =
            priceAndFeeCalculator.getVaultState(BASE_VAULT);
        (uint256 accruedVaultFeesView, uint256 accruedProtocolFeesView) =
            priceAndFeeCalculator.previewFees(BASE_VAULT, type(uint256).max);

        (uint256 expectedVaultFeesEarned, uint256 expectedProtocolFeesEarned) =
            _expectedFees(price, INITIAL_TOTAL_SUPPLY, price);

        assertEq(vaultPrice.paused, false, "Vault should be unpaused");
        assertTrue(vaultAccruals.accruedFees > 0, "Vault accrued fees should be greater than 0");
        assertEq(vaultAccruals.accruedFees, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");
        assertEq(
            vaultAccruals.accruedProtocolFees,
            expectedProtocolFeesEarned,
            "Protocol accrued fees not calculated correctly"
        );
        assertTrue(vaultAccruals.accruedProtocolFees > 0, "Protocol accrued fees should be greater than 0");
        assertEq(accruedVaultFeesView, expectedVaultFeesEarned, "Vault accrued fees not calculated correctly");
        assertEq(accruedProtocolFeesView, expectedProtocolFeesEarned, "Protocol accrued fees not calculated correctly");
    }

    function test_unpauseVault_revertsWith_VaultNotPaused() public {
        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultNotPaused.selector);
        priceAndFeeCalculator.unpauseVault(BASE_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP);
    }

    function test_unpauseVault_revertsWith_UnitPriceMismatch() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__UnitPriceMismatch.selector);
        priceAndFeeCalculator.unpauseVault(BASE_VAULT, INITIAL_UNIT_PRICE + 1, INITIAL_TIMESTAMP);
    }

    function test_unpauseVault_revertsWith_TimestampMismatch() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__TimestampMismatch.selector);
        priceAndFeeCalculator.unpauseVault(BASE_VAULT, INITIAL_UNIT_PRICE, INITIAL_TIMESTAMP + 1);
    }

    ////////////////////////////////////////////////////////////
    //                  convertUnitsToToken                  //
    ////////////////////////////////////////////////////////////

    function testFuzz_convertUnitsToToken_numeraireToken(uint128 unitPrice, uint256 unitsAmount) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        vm.assume(unitsAmount < type(uint256).max / unitPrice);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        uint256 expectedTokenAmount = unitsAmount * unitPrice / UNIT_PRICE_PRECISION;

        uint256 actualTokenAmount =
            priceAndFeeCalculator.convertUnitsToToken(BASE_VAULT, IERC20(NUMERAIRE), unitsAmount);

        assertEq(actualTokenAmount, expectedTokenAmount, "Token amount not calculated correctly");
    }

    function testFuzz_convertUnitsToToken_otherToken(uint128 unitPrice, uint256 unitsAmount, uint256 tokenAmount)
        public
    {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        address otherToken = makeAddr("OTHER_TOKEN");
        vm.assume(unitsAmount < type(uint256).max / unitPrice);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        uint256 numeraireAmount = unitsAmount * unitPrice / UNIT_PRICE_PRECISION;

        vm.mockCall(
            ORACLE_REGISTRY,
            abi.encodeWithSelector(
                IOracleRegistry.getQuoteForUser.selector,
                numeraireAmount,
                address(NUMERAIRE),
                address(otherToken),
                BASE_VAULT
            ),
            abi.encode(tokenAmount)
        );

        uint256 actualTokenAmount =
            priceAndFeeCalculator.convertUnitsToToken(BASE_VAULT, IERC20(otherToken), unitsAmount);

        assertEq(actualTokenAmount, tokenAmount, "Token amount not calculated correctly");
    }

    ////////////////////////////////////////////////////////////
    //                  convertUnitsToTokenIfActive          //
    ////////////////////////////////////////////////////////////

    function testFuzz_convertUnitsToTokenIfActive_numeraireToken(uint128 unitPrice, uint256 unitsAmount) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        vm.assume(unitsAmount < type(uint256).max / unitPrice);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        uint256 expectedTokenAmount = unitsAmount * unitPrice / UNIT_PRICE_PRECISION;

        uint256 actualTokenAmount = priceAndFeeCalculator.convertUnitsToTokenIfActive(
            BASE_VAULT, IERC20(NUMERAIRE), unitsAmount, Math.Rounding.Floor
        );

        assertEq(actualTokenAmount, expectedTokenAmount, "Token amount not calculated correctly");
    }

    function testFuzz_convertUnitsToTokenIfActive_otherToken_floor(
        uint128 unitPrice,
        uint256 unitsAmount,
        uint256 tokenAmount
    ) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        address otherToken = makeAddr("OTHER_TOKEN");
        vm.assume(unitsAmount < type(uint256).max / unitPrice);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        uint256 numeraireAmount = unitsAmount * unitPrice / UNIT_PRICE_PRECISION;

        vm.mockCall(
            ORACLE_REGISTRY,
            abi.encodeWithSelector(
                IOracleRegistry.getQuoteForUser.selector,
                numeraireAmount,
                address(NUMERAIRE),
                address(otherToken),
                BASE_VAULT
            ),
            abi.encode(tokenAmount)
        );

        uint256 actualTokenAmount = priceAndFeeCalculator.convertUnitsToTokenIfActive(
            BASE_VAULT, IERC20(otherToken), unitsAmount, Math.Rounding.Floor
        );

        assertEq(actualTokenAmount, tokenAmount, "Token amount not calculated correctly");
    }

    function testFuzz_convertUnitsToTokenIfActive_otherToken_ceil(
        uint128 unitPrice,
        uint256 unitsAmount,
        uint256 tokenAmount
    ) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        address otherToken = makeAddr("OTHER_TOKEN");
        vm.assume(unitsAmount < type(uint256).max / unitPrice);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        uint256 numeraireAmount = Math.mulDiv(unitsAmount, unitPrice, UNIT_PRICE_PRECISION, Math.Rounding.Ceil);
        console.log(" expected numeraireAmount", numeraireAmount);

        vm.mockCall(
            ORACLE_REGISTRY,
            abi.encodeWithSelector(
                IOracleRegistry.getQuoteForUser.selector,
                numeraireAmount,
                address(NUMERAIRE),
                address(otherToken),
                BASE_VAULT
            ),
            abi.encode(tokenAmount)
        );

        uint256 actualTokenAmount = priceAndFeeCalculator.convertUnitsToTokenIfActive(
            BASE_VAULT, IERC20(otherToken), unitsAmount, Math.Rounding.Ceil
        );

        assertEq(actualTokenAmount, tokenAmount, "Token amount not calculated correctly");
    }

    function test_convertUnitsToTokenIfActive_revertsWith_VaultPaused() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultPaused.selector);
        priceAndFeeCalculator.convertUnitsToTokenIfActive(BASE_VAULT, IERC20(NUMERAIRE), 1, Math.Rounding.Floor);
    }

    ////////////////////////////////////////////////////////////
    //                  convertTokenToUnits                   //
    ////////////////////////////////////////////////////////////

    function testFuzz_convertTokenToUnits_numeraireToken(uint128 unitPrice, uint256 tokenAmount) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        vm.assume(tokenAmount < type(uint256).max / TOKEN_SCALAR);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        uint256 expectedUnitsAmount = tokenAmount * TOKEN_SCALAR / unitPrice;
        uint256 actualUnitsAmount =
            priceAndFeeCalculator.convertTokenToUnits(BASE_VAULT, IERC20(NUMERAIRE), tokenAmount);

        assertEq(actualUnitsAmount, expectedUnitsAmount, "Units amount not calculated correctly");
    }

    function testFuzz_convertTokenToUnits_otherToken(uint128 unitPrice, uint256 tokenAmount, uint256 numeraireAmount)
        public
    {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        address otherToken = makeAddr("OTHER_TOKEN");
        vm.assume(numeraireAmount < type(uint256).max / TOKEN_SCALAR);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        vm.mockCall(
            ORACLE_REGISTRY,
            abi.encodeWithSelector(
                IOracleRegistry.getQuoteForUser.selector,
                tokenAmount,
                address(otherToken),
                address(NUMERAIRE),
                BASE_VAULT
            ),
            abi.encode(numeraireAmount)
        );

        uint256 expectedUnitsAmount = numeraireAmount * UNIT_PRICE_PRECISION / unitPrice;
        uint256 actualUnitsAmount =
            priceAndFeeCalculator.convertTokenToUnits(BASE_VAULT, IERC20(otherToken), tokenAmount);

        assertEq(actualUnitsAmount, expectedUnitsAmount, "Units amount not calculated correctly");
    }

    ////////////////////////////////////////////////////////////
    //                  convertTokenToUnitsIfActive          //
    ////////////////////////////////////////////////////////////

    function testFuzz_convertTokenToUnitsIfActive_numeraireToken(uint128 unitPrice, uint256 tokenAmount) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        vm.assume(tokenAmount < type(uint256).max / TOKEN_SCALAR);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        uint256 expectedUnitsAmount = tokenAmount * TOKEN_SCALAR / unitPrice;
        uint256 actualUnitsAmount = priceAndFeeCalculator.convertTokenToUnitsIfActive(
            BASE_VAULT, IERC20(NUMERAIRE), tokenAmount, Math.Rounding.Floor
        );

        assertEq(actualUnitsAmount, expectedUnitsAmount, "Units amount not calculated correctly");
    }

    function testFuzz_convertTokenToUnitsIfActive_otherToken_floor(
        uint128 unitPrice,
        uint256 tokenAmount,
        uint256 numeraireAmount
    ) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        address otherToken = makeAddr("OTHER_TOKEN");
        vm.assume(numeraireAmount < type(uint256).max / TOKEN_SCALAR);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        vm.mockCall(
            ORACLE_REGISTRY,
            abi.encodeWithSelector(
                IOracleRegistry.getQuoteForUser.selector,
                tokenAmount,
                address(otherToken),
                address(NUMERAIRE),
                BASE_VAULT
            ),
            abi.encode(numeraireAmount)
        );

        uint256 expectedUnitsAmount = numeraireAmount * UNIT_PRICE_PRECISION / unitPrice;
        uint256 actualUnitsAmount = priceAndFeeCalculator.convertTokenToUnitsIfActive(
            BASE_VAULT, IERC20(otherToken), tokenAmount, Math.Rounding.Floor
        );

        assertEq(actualUnitsAmount, expectedUnitsAmount, "Units amount not calculated correctly");
    }

    function testFuzz_convertTokenToUnitsIfActive_otherToken_ceil(
        uint128 unitPrice,
        uint256 tokenAmount,
        uint256 numeraireAmount
    ) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        address otherToken = makeAddr("OTHER_TOKEN");
        vm.assume(numeraireAmount < type(uint256).max / TOKEN_SCALAR);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        vm.mockCall(
            ORACLE_REGISTRY,
            abi.encodeWithSelector(
                IOracleRegistry.getQuoteForUser.selector,
                tokenAmount,
                address(otherToken),
                address(NUMERAIRE),
                BASE_VAULT
            ),
            abi.encode(numeraireAmount)
        );

        uint256 expectedUnitsAmount = Math.mulDiv(numeraireAmount, UNIT_PRICE_PRECISION, unitPrice, Math.Rounding.Ceil);
        uint256 actualUnitsAmount = priceAndFeeCalculator.convertTokenToUnitsIfActive(
            BASE_VAULT, IERC20(otherToken), tokenAmount, Math.Rounding.Ceil
        );

        assertEq(actualUnitsAmount, expectedUnitsAmount, "Units amount not calculated correctly");
    }

    function test_convertTokenToUnitsIfActive_revertsWith_VaultPaused() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultPaused.selector);
        priceAndFeeCalculator.convertTokenToUnitsIfActive(BASE_VAULT, IERC20(NUMERAIRE), 1, Math.Rounding.Floor);
    }

    ////////////////////////////////////////////////////////////
    //                  convertUnitsToNumeraire              //
    ////////////////////////////////////////////////////////////

    function testFuzz_convertUnitsToNumeraire_numeraireToken(uint128 unitPrice, uint256 unitsAmount) public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        unitPrice = uint128(
            bound(
                unitPrice,
                INITIAL_UNIT_PRICE * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS,
                INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS
            )
        );

        vm.assume(unitsAmount < type(uint256).max / unitPrice);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, unitPrice, uint32(vm.getBlockTimestamp()));

        uint256 expectedTokenAmount = unitsAmount * unitPrice / UNIT_PRICE_PRECISION;

        uint256 actualTokenAmount = priceAndFeeCalculator.convertUnitsToNumeraire(BASE_VAULT, unitsAmount);

        assertEq(actualTokenAmount, expectedTokenAmount, "Token amount not calculated correctly");
    }

    function test_convertUnitsToNumeraire_revertsWith_VaultPaused() public {
        vm.prank(users.owner);
        priceAndFeeCalculator.pauseVault(BASE_VAULT);

        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultPaused.selector);
        priceAndFeeCalculator.convertUnitsToNumeraire(BASE_VAULT, 1);
    }

    ////////////////////////////////////////////////////////////
    //                  getVaultsPriceAge                     //
    ////////////////////////////////////////////////////////////

    function test_getVaultsPriceAge_success() public {
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        uint256 timestamp = vm.getBlockTimestamp() - MAX_PRICE_AGE;

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, INITIAL_UNIT_PRICE, uint32(timestamp));

        uint256 actualPriceAge = priceAndFeeCalculator.getVaultsPriceAge(BASE_VAULT);
        assertEq(actualPriceAge, vm.getBlockTimestamp() - timestamp, "Timestamp not calculated correctly");
    }

    ////////////////////////////////////////////////////////////
    //                   resetHighestPrice                    //
    ////////////////////////////////////////////////////////////

    function test_resetHighestPrice_revertsWith_CallerIsNotAuthorized() public {
        _mockCanCall(
            address(this), address(priceAndFeeCalculator), IPriceAndFeeCalculator.resetHighestPrice.selector, false
        );

        vm.expectRevert(VaultAuth.Aera__CallerIsNotAuthorized.selector);
        priceAndFeeCalculator.resetHighestPrice(BASE_VAULT);
    }

    function test_resetHighestPrice_revertsWith_VaultNotInitialized() public {
        address uninitializedVault = makeAddr("UNINITIALIZED_VAULT");

        vm.mockCall(uninitializedVault, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.owner));
        vm.mockCall(
            uninitializedVault, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(INITIAL_TOTAL_SUPPLY)
        );

        vm.prank(uninitializedVault);
        priceAndFeeCalculator.registerVault();

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultNotInitialized.selector);
        priceAndFeeCalculator.resetHighestPrice(uninitializedVault);
    }

    function test_resetHighestPrice_revertsWith_CurrentPriceAboveHighestPrice() public {
        // First, set up a higher initial price
        uint128 highPrice = uint128(INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS - 1); // Just under 110%

        // Update to a high price first
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);
        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, highPrice, uint32(vm.getBlockTimestamp()));

        // Now try to reset the high-water mark when the price hasn't dropped
        // This should revert because current price = highest price, not below it
        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__CurrentPriceAboveHighestPrice.selector);
        priceAndFeeCalculator.resetHighestPrice(BASE_VAULT);

        // Also test when price goes even higher
        uint128 evenHigherPrice = uint128(highPrice * 105 / 100); // 5% higher
        vm.warp(vm.getBlockTimestamp() + MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);
        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, evenHigherPrice, uint32(vm.getBlockTimestamp()));

        // Should still revert since current price > highest price
        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__CurrentPriceAboveHighestPrice.selector);
        priceAndFeeCalculator.resetHighestPrice(BASE_VAULT);
    }

    function test_resetHighestPrice_success() public {
        // Set a higher unit price to create a high-water mark
        // But keep it within the maxPriceToleranceRatio (110%)
        uint128 highPrice = uint128(INITIAL_UNIT_PRICE * MAX_PRICE_TOLERANCE_RATIO / ONE_IN_BPS - 1); // Just under 110%
        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, highPrice, uint32(vm.getBlockTimestamp()));

        skip(MIN_UPDATE_INTERVAL_MINUTES * ONE_MINUTE);

        // Price drops but safely above the minimum tolerance
        uint128 lowerPrice = uint128(highPrice * MIN_PRICE_TOLERANCE_RATIO / ONE_IN_BPS + 1);

        vm.prank(users.owner);
        priceAndFeeCalculator.setUnitPrice(BASE_VAULT, lowerPrice, uint32(vm.getBlockTimestamp()));

        // Check high-water mark is still the high price
        (VaultPriceState memory vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.highestPrice, highPrice, "High-water mark should still be the high price");
        assertEq(vaultPrice.paused, false, "Vault should not be paused");

        // Setup fees to test fee accrual
        _setupFees();

        // Reset the high-water mark
        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true, address(priceAndFeeCalculator));
        emit IPriceAndFeeCalculator.HighestPriceReset(BASE_VAULT, lowerPrice);
        priceAndFeeCalculator.resetHighestPrice(BASE_VAULT);

        vm.snapshotGasLastCall("resetHighestPrice - success");

        // Check high-water mark was reset to current price
        (vaultPrice,) = priceAndFeeCalculator.getVaultState(BASE_VAULT);
        assertEq(vaultPrice.highestPrice, lowerPrice, "High-water mark should be reset to current price");

        assertEq(vaultPrice.accrualLag, 0, "accrualLag should be updated");
    }

    function _deployNewPriceAndFeeCalculator() internal returns (PriceAndFeeCalculator) {
        PriceAndFeeCalculator newPriceAndFeeCalculator = new PriceAndFeeCalculator(
            IERC20(NUMERAIRE), IOracleRegistry(ORACLE_REGISTRY), users.owner, Authority(address(0))
        );

        vm.prank(NEW_VAULT);
        newPriceAndFeeCalculator.registerVault();

        return newPriceAndFeeCalculator;
    }

    function _setupFees() internal {
        vm.startPrank(users.owner);
        priceAndFeeCalculator.setVaultFees(BASE_VAULT, VAULT_TVL_FEE, VAULT_PERFORMANCE_FEE);
        priceAndFeeCalculator.setProtocolFeeRecipient(users.protocolFeeRecipient);
        priceAndFeeCalculator.setProtocolFees(PROTOCOL_TVL_FEE, PROTOCOL_PERFORMANCE_FEE);
        vm.stopPrank();
    }

    function _expectedFees(uint256 tvlUsedPrice, uint256 tvlUsedTotalSupply, uint256 price)
        internal
        view
        returns (uint256 vaultFeesEarned, uint256 protocolFeesEarned)
    {
        uint256 timeDelta = vm.getBlockTimestamp() - INITIAL_TIMESTAMP;
        uint256 expectedTvl = tvlUsedPrice * tvlUsedTotalSupply / UNIT_PRICE_PRECISION;

        vaultFeesEarned = expectedTvl * VAULT_TVL_FEE * timeDelta / ONE_IN_BPS / SECONDS_PER_YEAR;
        protocolFeesEarned = expectedTvl * PROTOCOL_TVL_FEE * timeDelta / ONE_IN_BPS / SECONDS_PER_YEAR;

        if (price > INITIAL_UNIT_PRICE) {
            vaultFeesEarned += (price - INITIAL_UNIT_PRICE) * INITIAL_TOTAL_SUPPLY / UNIT_PRICE_PRECISION
                * VAULT_PERFORMANCE_FEE / ONE_IN_BPS;
            protocolFeesEarned += (price - INITIAL_UNIT_PRICE) * INITIAL_TOTAL_SUPPLY / UNIT_PRICE_PRECISION
                * PROTOCOL_PERFORMANCE_FEE / ONE_IN_BPS;
        }
    }

    ////////////////////////////////////////////////////////////
    //                       accrueFees                       //
    ////////////////////////////////////////////////////////////

    function test_fuzz_accrueFees_success(Fee memory fees, AccrueFeesParameters memory parameters) public {
        vm.assume(parameters.maxPriceToleranceRatio >= ONE_IN_BPS);
        vm.assume(block.timestamp + parameters.timeDelta < type(uint32).max);

        parameters.minPriceToleranceRatio = uint16(bound(parameters.minPriceToleranceRatio, 0, ONE_IN_BPS));
        parameters.maxPriceAge = uint8(bound(parameters.maxPriceAge, 1, type(uint8).max));
        parameters.maxUpdateDelayDays = uint8(bound(parameters.maxUpdateDelayDays, 1, type(uint8).max));
        parameters.protocolTvl = uint16(bound(parameters.protocolTvl, 0, MAX_TVL_FEE));
        parameters.protocolPerformance = uint16(bound(parameters.protocolPerformance, 0, MAX_PERFORMANCE_FEE));
        fees.tvl = uint16(bound(fees.tvl, 0, MAX_TVL_FEE));
        fees.performance = uint16(bound(fees.performance, 0, MAX_PERFORMANCE_FEE));

        // Minimize scenarios where no fees are accrued
        uint32 lastFeeAccrual = uint32(block.timestamp);
        uint32 timestamp = lastFeeAccrual + parameters.timeDelta;
        VaultPriceState memory priceState = VaultPriceState({
            paused: false,
            maxPriceAge: parameters.maxPriceAge,
            minUpdateIntervalMinutes: parameters.minUpdateIntervalMinutes,
            maxPriceToleranceRatio: parameters.maxPriceToleranceRatio,
            minPriceToleranceRatio: parameters.minPriceToleranceRatio,
            maxUpdateDelayDays: parameters.maxUpdateDelayDays,
            timestamp: lastFeeAccrual,
            accrualLag: parameters.accrualLag,
            unitPrice: parameters.unitPrice,
            highestPrice: parameters.highestPrice,
            lastTotalSupply: parameters.lastTotalSupply
        });
        VaultAccruals memory accruals = VaultAccruals({ fees: fees, accruedProtocolFees: 0, accruedFees: 0 });

        MockPriceAndFeeCalculator mockPriceAndFeeCalculator = new MockPriceAndFeeCalculator(
            IERC20(NUMERAIRE), IOracleRegistry(ORACLE_REGISTRY), users.owner, Authority(address(0))
        );
        vm.startPrank(users.owner);
        mockPriceAndFeeCalculator.setProtocolFeeRecipient(users.protocolFeeRecipient);
        mockPriceAndFeeCalculator.setProtocolFees(parameters.protocolTvl, parameters.protocolPerformance);
        vm.stopPrank();
        mockPriceAndFeeCalculator.setVaultPriceState(BASE_VAULT, priceState);
        mockPriceAndFeeCalculator.setVaultAccruals(BASE_VAULT, accruals);

        mockPriceAndFeeCalculator.accrueFees(BASE_VAULT, parameters.price, timestamp);

        VaultPriceState memory updatedPriceState = mockPriceAndFeeCalculator.getVaultPriceState(BASE_VAULT);
        VaultAccruals memory updatedAccruals = mockPriceAndFeeCalculator.getVaultAccruals(BASE_VAULT);

        assertGe(updatedAccruals.accruedFees, accruals.accruedFees, "accruedFees should never decrease after accrual");
        assertGe(
            updatedAccruals.accruedProtocolFees,
            accruals.accruedProtocolFees,
            "accruedProtocolFees should never decrease after accrual"
        );
        assertEq(
            updatedPriceState.lastTotalSupply,
            IERC20(BASE_VAULT).totalSupply(),
            "lastTotalSupply should be updated correctly"
        );
        assertEq(updatedPriceState.accrualLag, 0, "averageValue should reset to 0 after accrual");
    }

    function _setDefaultThresholds(IPriceAndFeeCalculator calculator, address vault) internal {
        vm.prank(users.owner);
        calculator.setThresholds(
            vault,
            MIN_PRICE_TOLERANCE_RATIO,
            MAX_PRICE_TOLERANCE_RATIO,
            MIN_UPDATE_INTERVAL_MINUTES,
            MAX_PRICE_AGE,
            MAX_UPDATE_DELAY_DAYS
        );
    }
}
