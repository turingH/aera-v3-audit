// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";

import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { CCTPHooks } from "src/periphery/hooks/slippage/CCTPHooks.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";
import { ICCTPHooks } from "src/periphery/interfaces/hooks/slippage/ICCTPHooks.sol";

import { MockCCTPHooks } from "test/periphery/mocks/hooks/slippage/MockCCTPHooks.sol";
import { SwapUtils } from "test/periphery/utils/SwapUtils.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract CCTPHooksTest is BaseTest {
    CCTPHooks public hooks;
    ERC20Mock public token;
    ERC20Mock public numeraire;
    OracleRegistry public oracleRegistry;

    address public constant VAULT = address(0xabcdef);
    uint128 public constant MAX_DAILY_LOSS = 300 * 10 ** 18;
    uint16 public constant MAX_SLIPPAGE_100BPS = 100; // 1%
    uint16 public constant SLIPPAGE_10BPS = 10; // 0.1%
    uint32 internal constant BASE_DOMAIN_ID = 6;
    uint32 internal constant FINALITY_THRESHOLD_STANDARD = 2000;
    uint32 internal constant FINALITY_THRESHOLD_FAST = 1000;

    uint256 public constant AMOUNT = 10_000 * 10 ** 6;
    uint256 public constant VALUE = 10_000 * 10 ** 18;

    function setUp() public override {
        super.setUp();

        token = new ERC20Mock();
        numeraire = new ERC20Mock();
        oracleRegistry = new OracleRegistry(address(this), Authority(address(0)), ORACLE_UPDATE_DELAY);

        uint160 targetBits = uint160(1); // Set least significant bit
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockCCTPHooks(address(numeraire))).code);
        hooks = MockCCTPHooks(address(targetAddress | targetBits));

        vm.label(VAULT, "VAULT");
        vm.label(address(hooks), "CCTP_HOOKS");
        vm.label(address(numeraire), "NUMERAIRE");
        vm.label(address(oracleRegistry), "ORACLE_REGISTRY");
        vm.label(address(token), "TOKEN");

        vm.mockCall(VAULT, bytes4(keccak256("owner()")), abi.encode(address(this)));

        hooks.setMaxDailyLoss(VAULT, MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(VAULT, MAX_SLIPPAGE_100BPS);
        hooks.setOracleRegistry(VAULT, address(oracleRegistry));
    }

    ////////////////////////////////////////////////////////////
    //                CCTP - standard transfer                //
    ////////////////////////////////////////////////////////////
    function test_standardTransfer_success() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(token), VAULT, AMOUNT);

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        vm.prank(VAULT);
        hooks.depositForBurn(
            AMOUNT,
            BASE_DOMAIN_ID,
            bytes32(uint256(uint160(VAULT))),
            address(token),
            bytes32(0),
            0,
            FINALITY_THRESHOLD_STANDARD
        );
        vm.snapshotGasLastCall("standard transfer - success");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        assertEq(
            hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire, 0, "Loss should be zero for standard transfers"
        );
    }

    function test_standardTransfer_revertsWith_DestinationCallerNotZero() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(token), VAULT, AMOUNT);

        vm.expectRevert(ICCTPHooks.AeraPeriphery__DestinationCallerNotZero.selector);
        vm.prank(VAULT);
        hooks.depositForBurn(
            AMOUNT,
            BASE_DOMAIN_ID,
            bytes32(uint256(uint160(VAULT))),
            address(token),
            bytes32(uint256(1)),
            0,
            FINALITY_THRESHOLD_STANDARD
        );
    }

    ////////////////////////////////////////////////////////////
    //                  CCTP - fast transfer                  //
    ////////////////////////////////////////////////////////////
    function test_fastTransfer_success() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(token), VAULT, AMOUNT);

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: AMOUNT,
            baseToken: address(token),
            quoteToken: address(numeraire),
            quoteAmount: VALUE
        });

        uint256 fee = AMOUNT * SLIPPAGE_10BPS / 10_000; // 0.1% fee
        uint256 feeInNumeraire = VALUE * SLIPPAGE_10BPS / 10_000;

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: fee,
            baseToken: address(token),
            quoteToken: address(numeraire),
            quoteAmount: feeInNumeraire
        });

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: AMOUNT - fee,
            baseToken: address(token),
            quoteToken: address(numeraire),
            quoteAmount: VALUE - feeInNumeraire
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            VAULT, address(token), address(token), VALUE, VALUE - feeInNumeraire, uint128(feeInNumeraire)
        );
        vm.prank(VAULT);
        hooks.depositForBurn(
            AMOUNT,
            BASE_DOMAIN_ID,
            bytes32(uint256(uint160(VAULT))),
            address(token),
            bytes32(0),
            fee,
            FINALITY_THRESHOLD_FAST
        );
        vm.snapshotGasLastCall("fast transfer - success");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        assertEq(
            hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire,
            oracleRegistry.getQuote(fee, address(token), address(numeraire)),
            "Loss should equal the fee in fast transfers"
        );
    }

    function test_fastTransfer_revertsWith_DestinationCallerNotZero() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(token), VAULT, AMOUNT);

        vm.expectRevert(ICCTPHooks.AeraPeriphery__DestinationCallerNotZero.selector);
        vm.prank(VAULT);
        hooks.depositForBurn(
            AMOUNT,
            BASE_DOMAIN_ID,
            bytes32(uint256(uint160(VAULT))),
            address(token),
            bytes32(uint256(1)),
            1,
            FINALITY_THRESHOLD_FAST
        );
    }

    function test_fastTransfer_revertsWith_ExcessiveSlippage() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(token), VAULT, AMOUNT);

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: AMOUNT,
            baseToken: address(token),
            quoteToken: address(numeraire),
            quoteAmount: VALUE
        });

        uint256 fee = AMOUNT * (MAX_SLIPPAGE_100BPS * 2) / 10_000; // 2% fee
        uint256 feeInNumeraire = VALUE * (MAX_SLIPPAGE_100BPS * 2) / 10_000;

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: AMOUNT - fee,
            baseToken: address(token),
            quoteToken: address(numeraire),
            quoteAmount: VALUE - feeInNumeraire
        });

        vm.prank(VAULT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector, feeInNumeraire, VALUE, MAX_SLIPPAGE_100BPS
            )
        );
        hooks.depositForBurn(
            AMOUNT,
            BASE_DOMAIN_ID,
            bytes32(uint256(uint160(VAULT))),
            address(token),
            bytes32(0),
            fee,
            FINALITY_THRESHOLD_FAST
        );
    }

    function test_fastTransfer_revertsWith_ExcessiveDailyLoss() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(token), VAULT, AMOUNT);

        uint16 HIGH_SLIPPAGE = uint16(MAX_SLIPPAGE_100BPS * 10);
        hooks.setMaxSlippagePerTrade(VAULT, HIGH_SLIPPAGE);

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: AMOUNT,
            baseToken: address(token),
            quoteToken: address(numeraire),
            quoteAmount: VALUE
        });

        uint256 fee = AMOUNT * (MAX_SLIPPAGE_100BPS * 9) / 10_000; // 9% fee
        uint256 feeInNumeraire = VALUE * (MAX_SLIPPAGE_100BPS * 9) / 10_000;

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: AMOUNT - fee,
            baseToken: address(token),
            quoteToken: address(numeraire),
            quoteAmount: VALUE - feeInNumeraire
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector, feeInNumeraire, MAX_DAILY_LOSS
            )
        );
        vm.prank(VAULT);
        hooks.depositForBurn(
            AMOUNT,
            BASE_DOMAIN_ID,
            bytes32(uint256(uint160(VAULT))),
            address(token),
            bytes32(0),
            fee,
            FINALITY_THRESHOLD_FAST
        );
    }
}
