// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { MilkmanHooks } from "src/periphery/hooks/slippage/MilkmanHooks.sol";

import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";
import { IMilkmanHooks } from "src/periphery/interfaces/hooks/slippage/IMilkmanHooks.sol";

import { MockMilkmanHooks } from "test/periphery/mocks/hooks/slippage/MockMilkmanHooks.sol";
import { SwapUtils } from "test/periphery/utils/SwapUtils.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract MilkmanHooksTest is BaseTest {
    MilkmanHooks public hooks;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public numeraire;
    OracleRegistry public oracleRegistry;

    address public constant ROUTER = address(0x123456);
    address public constant VAULT = address(0xabcdef);
    uint128 public constant MAX_DAILY_LOSS = 100e18;
    uint16 public constant MAX_BPS = 10_000;
    uint16 public constant MAX_SLIPPAGE_100BPS = 100; // 1%

    uint256 internal constant TOKEN_A_PRICE_IN_NUMERAIRE = 100e18; // 1 A = 100 numeraire
    uint256 internal constant TOKEN_B_PRICE_IN_NUMERAIRE = 50e18; // 1 B = 50 numeraire
    uint256 internal constant TOKEN_A_PRICE_IN_TOKEN_B = 2e18; // 1 A = 2 B
    uint256 internal constant SELL_AMOUNT = 10e18;

    function setUp() public override {
        super.setUp();

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        numeraire = new ERC20Mock();
        oracleRegistry = new OracleRegistry(address(this), Authority(address(0)), ORACLE_UPDATE_DELAY);

        // Deploy Milkman Hooks with USDC as numeraire and mine address to have before hooks
        uint160 targetBits = uint160(1); // Set least significant bit
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockMilkmanHooks(address(numeraire))).code);
        hooks = MockMilkmanHooks(address(targetAddress | targetBits));

        vm.label(VAULT, "VAULT");
        vm.label(address(hooks), "MILKMAN_HOOKS");
        vm.label(address(numeraire), "NUMERAIRE");
        vm.label(address(oracleRegistry), "ORACLE_REGISTRY");
        vm.label(address(tokenA), "TOKEN_A");
        vm.label(address(tokenB), "TOKEN_B");

        vm.mockCall(VAULT, bytes4(keccak256("owner()")), abi.encode(address(this)));

        hooks.setMaxDailyLoss(VAULT, MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(VAULT, MAX_SLIPPAGE_100BPS);
        hooks.setOracleRegistry(VAULT, address(oracleRegistry));
    }

    ////////////////////////////////////////////////////////////
    //                      requestSell                       //
    ////////////////////////////////////////////////////////////
    function test_requestSell_success() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 expectedLossAmount = SELL_AMOUNT * MAX_SLIPPAGE_100BPS / MAX_BPS;
        uint256 expectedLossValue = TOKEN_A_PRICE_IN_NUMERAIRE * MAX_SLIPPAGE_100BPS / MAX_BPS;

        // Mock price checker validation (A->B)
        SwapUtils.mock_OracleRegistry_GetQuoteForVault({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: SELL_AMOUNT,
            baseToken: address(tokenA),
            quoteToken: address(tokenB),
            quoteAmount: SELL_AMOUNT * TOKEN_A_PRICE_IN_TOKEN_B,
            vault: VAULT
        });

        // Mock loss value (A with slippage->numeraire)
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: expectedLossAmount,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: expectedLossValue
        });

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        uint256 lossBefore = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;

        vm.prank(VAULT);
        hooks.requestSell(SELL_AMOUNT, tokenA, tokenB, bytes32(0), address(hooks), abi.encode(VAULT));
        vm.snapshotGasLastCall("requestSell - success");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + expectedLossValue, "Daily loss mismatch");
    }

    function test_requestSell_revertsWith_InvalidPriceChecker() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        address invalidPriceChecker = address(0xdead);

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IMilkmanHooks.AeraPeriphery__InvalidPriceChecker.selector, address(hooks), invalidPriceChecker
            )
        );
        vm.prank(VAULT);
        hooks.requestSell(SELL_AMOUNT, tokenA, tokenB, bytes32(0), invalidPriceChecker, abi.encode(VAULT));
    }

    function test_requestSell_revertsWith_InvalidVaultInPriceCheckerData() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        address invalidVault = address(0xdead);

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IMilkmanHooks.AeraPeriphery__InvalidVaultInPriceCheckerData.selector, VAULT, invalidVault
            )
        );
        vm.prank(VAULT);
        hooks.requestSell(SELL_AMOUNT, tokenA, tokenB, bytes32(0), address(hooks), abi.encode(invalidVault));
    }

    function test_requestSell_revertsWith_ExcessiveDailyLoss() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        // Set low max daily loss
        uint128 lowMaxDailyLoss = 0.1e18;
        hooks.setMaxDailyLoss(VAULT, lowMaxDailyLoss);

        uint256 expectedLossAmount = SELL_AMOUNT * MAX_SLIPPAGE_100BPS / MAX_BPS;
        uint256 expectedLossValue = TOKEN_A_PRICE_IN_NUMERAIRE * MAX_SLIPPAGE_100BPS / MAX_BPS;

        // Mock price checker validation (A->B)
        SwapUtils.mock_OracleRegistry_GetQuoteForVault({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: SELL_AMOUNT,
            baseToken: address(tokenA),
            quoteToken: address(tokenB),
            quoteAmount: SELL_AMOUNT * TOKEN_A_PRICE_IN_TOKEN_B,
            vault: VAULT
        });

        // Mock loss value (A with slippage->numeraire)
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: expectedLossAmount,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: expectedLossValue
        });

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector, expectedLossValue, lowMaxDailyLoss
            )
        );
        vm.prank(VAULT);
        hooks.requestSell(SELL_AMOUNT, tokenA, tokenB, bytes32(0), address(hooks), abi.encode(VAULT));
    }

    ////////////////////////////////////////////////////////////
    //                       checkPrice                       //
    ////////////////////////////////////////////////////////////

    function test_checkPrice_success() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 expectedOut = SELL_AMOUNT * TOKEN_A_PRICE_IN_TOKEN_B / 1e18;
        uint256 validMinOut = SwapUtils.applyLossToAmount(expectedOut, 0, MAX_SLIPPAGE_100BPS - 1);
        uint256 invalidMinOut = SwapUtils.applyLossToAmount(expectedOut, 0, MAX_SLIPPAGE_100BPS + 1);

        // Mock oracle response
        SwapUtils.mock_OracleRegistry_GetQuoteForVault({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: SELL_AMOUNT,
            baseToken: address(tokenA),
            quoteToken: address(tokenB),
            quoteAmount: expectedOut,
            vault: VAULT
        });

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        bool validResult = hooks.checkPrice(
            SELL_AMOUNT, // amountIn
            address(tokenA), // fromToken
            address(tokenB), // toToken
            0, // feeAmount
            validMinOut, // minOut
            abi.encode(VAULT) // data
        );
        vm.snapshotGasLastCall("checkPrice - success - price > minOut");
        assertTrue(validResult, "Should accept valid minimum output");

        bool invalidResult = hooks.checkPrice(
            SELL_AMOUNT, // amountIn
            address(tokenA), // fromToken
            address(tokenB), // toToken
            0, // feeAmount
            invalidMinOut, // minOut
            abi.encode(VAULT) // data
        );
        vm.snapshotGasLastCall("checkPrice - success - price < minOut");
        assertFalse(invalidResult, "Should reject invalid minimum output");
    }
}
