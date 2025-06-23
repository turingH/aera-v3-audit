// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { IOdosRouterV2 } from "src/dependencies/odos/interfaces/IOdosRouterV2.sol";

import { ODOS_ROUTER_V2_ETH_ADDRESS } from "src/periphery/Constants.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { OdosV2DexHooks } from "src/periphery/hooks/slippage/OdosV2DexHooks.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

import { MockOdosV2DexHooks } from "test/periphery/mocks/hooks/slippage/MockOdosV2DexHooks.sol";
import { SwapUtils } from "test/periphery/utils/SwapUtils.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract OdosV2DexHooksTest is BaseTest {
    OdosV2DexHooks public hooks;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public numeraire;
    OracleRegistry public oracleRegistry;

    address public constant VAULT = address(0xabcdef);
    address public constant ODOS_EXECUTOR = address(0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559);
    uint128 public constant MAX_DAILY_LOSS = 100e18;
    uint16 public constant MAX_SLIPPAGE_100BPS = 100; // 1%
    uint16 public constant SLIPPAGE_10BPS = 10; // 0.1%

    uint256 public constant INPUT_AMOUNT = 10e18;
    uint256 public constant INPUT_VALUE = 100e18; // 10e18 * 10 (oracle price)

    function setUp() public override {
        super.setUp();

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        numeraire = new ERC20Mock();
        oracleRegistry = new OracleRegistry(address(this), Authority(address(0)), ORACLE_UPDATE_DELAY);

        // Deploy OdosV2 Hooks with USDC as numeraire and mine address to have before hooks
        uint160 targetBits = uint160(1); // Set least significant bit
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockOdosV2DexHooks(address(numeraire))).code);
        hooks = MockOdosV2DexHooks(address(targetAddress | targetBits));

        vm.label(VAULT, "VAULT");
        vm.label(address(hooks), "DEX_HOOKS");
        vm.label(address(numeraire), "NUMERAIRE");
        vm.label(address(oracleRegistry), "ORACLE_REGISTRY");
        vm.label(address(tokenA), "TOKEN_A");
        vm.label(address(tokenB), "TOKEN_B");

        vm.mockCall(VAULT, bytes4(keccak256("owner()")), abi.encode(address(this)));

        hooks.setMaxDailyLoss(VAULT, MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(VAULT, MAX_SLIPPAGE_100BPS);
        hooks.setOracleRegistry(VAULT, address(oracleRegistry));
    }

    function test_swap_success() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(tokenA), VAULT, INPUT_AMOUNT);

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: INPUT_AMOUNT,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: INPUT_VALUE
        });

        uint256 expectedOutputValue = SwapUtils.applyLossToAmount(INPUT_VALUE, 0, SLIPPAGE_10BPS);
        uint256 minOutput = SwapUtils.applyLossToAmount(INPUT_AMOUNT, 0, SLIPPAGE_10BPS);
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: minOutput,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: expectedOutputValue
        });

        IOdosRouterV2.SwapTokenInfo memory tokenInfo = IOdosRouterV2.SwapTokenInfo({
            inputToken: address(tokenA),
            inputAmount: INPUT_AMOUNT,
            inputReceiver: ODOS_EXECUTOR,
            outputToken: address(tokenB),
            outputQuote: expectedOutputValue,
            outputMin: minOutput,
            outputReceiver: VAULT
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        uint256 lossBefore = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        uint256 amountInNumeraire = oracleRegistry.getQuote(INPUT_AMOUNT, address(tokenA), address(numeraire));
        uint256 amountOutNumeraire = oracleRegistry.getQuote(minOutput, address(tokenB), address(numeraire));
        uint256 lossDuringSwap = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            VAULT, address(tokenA), address(tokenB), amountInNumeraire, amountOutNumeraire, uint128(lossDuringSwap)
        );
        vm.prank(VAULT);
        hooks.swap(tokenInfo, bytes(""), ODOS_EXECUTOR, 0);
        vm.snapshotGasLastCall("swap - success");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringSwap, "Loss does not match the slippage from the swap");
    }

    function test_swap_revertsWith_InputAmountIsZero() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 minOutput = SwapUtils.applyLossToAmount(INPUT_AMOUNT, 0, SLIPPAGE_10BPS);

        IOdosRouterV2.SwapTokenInfo memory tokenInfo = IOdosRouterV2.SwapTokenInfo({
            inputToken: address(tokenA),
            inputAmount: 0,
            inputReceiver: ODOS_EXECUTOR,
            outputToken: address(tokenB),
            outputQuote: INPUT_VALUE,
            outputMin: minOutput,
            outputReceiver: VAULT
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        vm.expectRevert(IBaseSlippageHooks.AeraPeriphery__InputAmountIsZero.selector);
        vm.prank(VAULT);
        hooks.swap(tokenInfo, bytes(""), ODOS_EXECUTOR, 0);
    }

    function test_swap_revertsWith_InputTokenIsETH() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 minOutput = SwapUtils.applyLossToAmount(INPUT_AMOUNT, 0, SLIPPAGE_10BPS);

        IOdosRouterV2.SwapTokenInfo memory tokenInfo = IOdosRouterV2.SwapTokenInfo({
            inputToken: ODOS_ROUTER_V2_ETH_ADDRESS, // ETH
            inputAmount: INPUT_AMOUNT,
            inputReceiver: ODOS_EXECUTOR,
            outputToken: address(tokenB),
            outputQuote: INPUT_VALUE,
            outputMin: minOutput,
            outputReceiver: VAULT
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        vm.expectRevert(IBaseSlippageHooks.AeraPeriphery__InputTokenIsETH.selector);
        vm.prank(VAULT);
        hooks.swap(tokenInfo, bytes(""), ODOS_EXECUTOR, 0);
    }

    function test_swap_revertsWith_OutputTokenIsETH() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 minOutput = SwapUtils.applyLossToAmount(INPUT_AMOUNT, 0, SLIPPAGE_10BPS);

        IOdosRouterV2.SwapTokenInfo memory tokenInfo = IOdosRouterV2.SwapTokenInfo({
            inputToken: address(tokenA),
            inputAmount: INPUT_AMOUNT,
            inputReceiver: ODOS_EXECUTOR,
            outputToken: ODOS_ROUTER_V2_ETH_ADDRESS, // ETH
            outputQuote: INPUT_VALUE,
            outputMin: minOutput,
            outputReceiver: VAULT
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        vm.expectRevert(IBaseSlippageHooks.AeraPeriphery__OutputTokenIsETH.selector);
        vm.prank(VAULT);
        hooks.swap(tokenInfo, bytes(""), ODOS_EXECUTOR, 0);
    }

    function test_swap_revertsWith_ExcessiveSlippage() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 inputAmount = INPUT_AMOUNT;
        uint256 minOutput = SwapUtils.applyLossToAmount(inputAmount, 0, MAX_SLIPPAGE_100BPS);
        uint256 inputValue = INPUT_VALUE;

        deal(address(tokenA), VAULT, inputAmount);

        // Pre-hooks quote for input value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: inputAmount,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: inputValue
        });

        uint256 outputValue = SwapUtils.applyLossToAmount(inputValue, 0, MAX_SLIPPAGE_100BPS * 9); // 9% loss
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: minOutput,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValue
        });

        IOdosRouterV2.SwapTokenInfo memory tokenInfo = IOdosRouterV2.SwapTokenInfo({
            inputToken: address(tokenA),
            inputAmount: inputAmount,
            inputReceiver: ODOS_EXECUTOR,
            outputToken: address(tokenB),
            outputQuote: inputValue, // Original value without slippage
            outputMin: minOutput,
            outputReceiver: VAULT
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector,
                inputValue - outputValue,
                inputValue,
                MAX_SLIPPAGE_100BPS
            )
        );
        vm.prank(VAULT);
        hooks.swap(tokenInfo, bytes(""), ODOS_EXECUTOR, 0);
    }

    function test_swap_revertsWith_ExcessiveDailyLoss() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint128 LOW_MAX_DAILY_LOSS = uint128(MAX_DAILY_LOSS / 100_000);
        uint16 HIGH_SLIPPAGE = uint16(MAX_SLIPPAGE_100BPS * 10);
        hooks.setMaxDailyLoss(VAULT, LOW_MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(VAULT, HIGH_SLIPPAGE);

        uint256 inputAmount = INPUT_AMOUNT;
        uint256 inputValue = INPUT_VALUE;
        uint256 minOutput = SwapUtils.applyLossToAmount(inputAmount, 0, HIGH_SLIPPAGE); // Allow high slippage

        deal(address(tokenA), VAULT, inputAmount);

        // Pre-hooks quote for input value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: inputAmount,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: inputValue
        });

        uint256 outputValue = SwapUtils.applyLossToAmount(inputValue, 0, MAX_SLIPPAGE_100BPS * 9); // 9% loss
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: minOutput,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValue
        });

        IOdosRouterV2.SwapTokenInfo memory tokenInfo = IOdosRouterV2.SwapTokenInfo({
            inputToken: address(tokenA),
            inputAmount: inputAmount,
            inputReceiver: ODOS_EXECUTOR,
            outputToken: address(tokenB),
            outputQuote: inputValue, // Original value without loss
            outputMin: minOutput,
            outputReceiver: VAULT
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector,
                inputValue - outputValue,
                LOW_MAX_DAILY_LOSS
            )
        );
        vm.prank(VAULT);
        hooks.swap(tokenInfo, bytes(""), ODOS_EXECUTOR, 0);
    }
}
