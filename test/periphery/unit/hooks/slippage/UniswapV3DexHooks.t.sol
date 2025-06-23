// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { ISwapRouter } from "src/dependencies/uniswap/v3/interfaces/ISwapRouter.sol";

import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { UniswapV3DexHooks } from "src/periphery/hooks/slippage/UniswapV3DexHooks.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";
import { IUniswapV3DexHooks } from "src/periphery/interfaces/hooks/slippage/IUniswapV3DexHooks.sol";

import { MockUniswapV3DexHooks } from "test/periphery/mocks/hooks/slippage/MockUniswapV3DexHooks.sol";
import { SwapUtils } from "test/periphery/utils/SwapUtils.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract UniswapV3DexHooksTest is BaseTest {
    UniswapV3DexHooks public hooks;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public tokenC;
    ERC20Mock public numeraire;
    OracleRegistry public oracleRegistry;

    address public constant VAULT = address(0xabcdef);
    uint128 public constant MAX_DAILY_LOSS = 100e18;
    uint16 public constant MAX_BPS = 10_000;
    uint16 public constant MAX_SLIPPAGE_100BPS = 100; // 1%
    uint16 public constant SLIPPAGE_10BPS = 10; // 0.1%
    uint24 public constant FEE_30BPS = 30; // 0.3%

    uint256 public constant TOKENS_PRICE_IN_NUMERAIRE = 100e18;
    uint256 public constant TOKEN_A_AMOUNT = 10e18;
    uint256 public constant TOKEN_B_AMOUNT = 5e18;

    function setUp() public override {
        super.setUp();

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        numeraire = new ERC20Mock();
        oracleRegistry = new OracleRegistry(address(this), Authority(address(0)), ORACLE_UPDATE_DELAY);

        // Deploy UniswapV3 Hooks with USDC as numeraire and mine address to have before hooks
        uint160 targetBits = uint160(1); // Set least significant bit
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockUniswapV3DexHooks(address(numeraire))).code);
        hooks = MockUniswapV3DexHooks(address(targetAddress | targetBits));

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

    ////////////////////////////////////////////////////////////
    //            Uniswap V3 - Exact Input Single             //
    ////////////////////////////////////////////////////////////
    function test_exactInputSingle_success() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(tokenA), VAULT, TOKEN_A_AMOUNT);

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: TOKEN_A_AMOUNT,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: TOKENS_PRICE_IN_NUMERAIRE
        });

        uint256 amountOutMinimum = SwapUtils.applyLossToAmount(TOKEN_B_AMOUNT, FEE_30BPS, SLIPPAGE_10BPS);
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountOutMinimum,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: SwapUtils.applyLossToAmount(TOKENS_PRICE_IN_NUMERAIRE, FEE_30BPS, SLIPPAGE_10BPS)
        });

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            fee: FEE_30BPS,
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: TOKEN_A_AMOUNT,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        uint256 lossBefore = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        uint256 amountInNumeraire = oracleRegistry.getQuote(params.amountIn, address(tokenA), address(numeraire));
        uint256 amountOutNumeraire =
            oracleRegistry.getQuote(params.amountOutMinimum, address(tokenB), address(numeraire));
        uint256 lossDuringSwap = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            VAULT, address(tokenA), address(tokenB), amountInNumeraire, amountOutNumeraire, uint128(lossDuringSwap)
        );
        vm.prank(VAULT);
        hooks.exactInputSingle(params);
        vm.snapshotGasLastCall("exactInputSingle - success");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringSwap, "Loss does not match the slippage from the swap");
    }

    function test_exactInputSingle_revertsWith_ExcessiveSlippage() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 inputAmount = TOKEN_A_AMOUNT;
        uint256 minOutputAmount = TOKEN_B_AMOUNT;
        uint256 inputValueInNumeraire = TOKENS_PRICE_IN_NUMERAIRE;

        deal(address(tokenA), VAULT, inputAmount);

        // Pre-hooks quote for input value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: inputAmount,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: inputValueInNumeraire
        });

        uint256 outputValueInNumeraire =
            SwapUtils.applyLossToAmount(inputValueInNumeraire, 0, MAX_SLIPPAGE_100BPS + SLIPPAGE_10BPS);
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: minOutputAmount,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire
        });

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            fee: FEE_30BPS,
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: inputAmount,
            amountOutMinimum: minOutputAmount,
            sqrtPriceLimitX96: 0
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector,
                inputValueInNumeraire - outputValueInNumeraire,
                inputValueInNumeraire,
                MAX_SLIPPAGE_100BPS
            )
        );
        vm.prank(VAULT);
        hooks.exactInputSingle(params);
    }

    function test_exactInputSingle_revertsWith_ExcessiveDailyLoss() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint128 LOW_MAX_DAILY_LOSS = uint128(MAX_DAILY_LOSS / 100_000);
        uint16 HIGH_SLIPPAGE = uint16(MAX_SLIPPAGE_100BPS * 10);

        hooks.setMaxDailyLoss(VAULT, LOW_MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(VAULT, HIGH_SLIPPAGE);

        uint256 inputAmount = TOKEN_A_AMOUNT;
        uint256 minOutputAmount = TOKEN_B_AMOUNT;
        uint256 inputValueInNumeraire = TOKENS_PRICE_IN_NUMERAIRE;

        deal(address(tokenA), VAULT, inputAmount);

        // Pre-hooks quote for input value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: inputAmount,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: inputValueInNumeraire
        });

        uint256 outputValueInNumeraire = SwapUtils.applyLossToAmount(inputValueInNumeraire, 0, MAX_SLIPPAGE_100BPS * 9); // 9%
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: minOutputAmount,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire
        });

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            fee: FEE_30BPS,
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: inputAmount,
            amountOutMinimum: minOutputAmount,
            sqrtPriceLimitX96: 0
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector,
                inputValueInNumeraire - outputValueInNumeraire,
                LOW_MAX_DAILY_LOSS
            )
        );
        vm.prank(VAULT);
        hooks.exactInputSingle(params);
    }

    ////////////////////////////////////////////////////////////
    //                Uniswap V3 - Exact Input                //
    ////////////////////////////////////////////////////////////

    function test_exactInput_success_SingleHop() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        deal(address(tokenA), VAULT, TOKEN_A_AMOUNT);

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: TOKEN_A_AMOUNT,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: TOKENS_PRICE_IN_NUMERAIRE
        });

        uint256 amountOutMinimum = SwapUtils.applyLossToAmount(TOKEN_B_AMOUNT, FEE_30BPS, SLIPPAGE_10BPS);
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountOutMinimum,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: SwapUtils.applyLossToAmount(TOKENS_PRICE_IN_NUMERAIRE, FEE_30BPS, SLIPPAGE_10BPS)
        });

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: SwapUtils.encodePath(address(tokenA), FEE_30BPS, address(tokenB)),
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: TOKEN_A_AMOUNT,
            amountOutMinimum: amountOutMinimum
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        uint256 lossBefore = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        uint256 amountInNumeraire = oracleRegistry.getQuote(params.amountIn, address(tokenA), address(numeraire));
        uint256 amountOutNumeraire =
            oracleRegistry.getQuote(params.amountOutMinimum, address(tokenB), address(numeraire));
        uint256 lossDuringSwap = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            VAULT, address(tokenA), address(tokenB), amountInNumeraire, amountOutNumeraire, uint128(lossDuringSwap)
        );
        vm.prank(VAULT);
        hooks.exactInput(params);
        vm.snapshotGasLastCall("exactInput - success - single-hop");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringSwap, "Loss does not match the slippage from the swap");
    }

    function test_exactInput_success_MultiHop() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~=
        deal(address(tokenA), VAULT, TOKEN_A_AMOUNT);

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: TOKEN_A_AMOUNT,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: TOKENS_PRICE_IN_NUMERAIRE
        });

        uint256 amountOutMinimum = SwapUtils.applyLossToAmount(TOKEN_B_AMOUNT, FEE_30BPS, SLIPPAGE_10BPS);
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountOutMinimum,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: SwapUtils.applyLossToAmount(TOKENS_PRICE_IN_NUMERAIRE, FEE_30BPS, SLIPPAGE_10BPS)
        });

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenC);
        tokens[2] = address(tokenB);

        uint24[] memory fees = new uint24[](2);
        fees[0] = FEE_30BPS;
        fees[1] = FEE_30BPS;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: SwapUtils.encodePath(tokens, fees),
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: TOKEN_A_AMOUNT,
            amountOutMinimum: amountOutMinimum
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        uint256 lossBefore = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        uint256 amountInNumeraire = oracleRegistry.getQuote(params.amountIn, address(tokenA), address(numeraire));
        uint256 amountOutNumeraire =
            oracleRegistry.getQuote(params.amountOutMinimum, address(tokenB), address(numeraire));
        uint256 lossDuringSwap = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            VAULT, address(tokenA), address(tokenB), amountInNumeraire, amountOutNumeraire, uint128(lossDuringSwap)
        );
        vm.prank(VAULT);
        hooks.exactInput(params);
        vm.snapshotGasLastCall("exactInput - success - multi-hop");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringSwap, "Loss does not match the slippage from the swap");
    }

    function test_exactInput_SingleHop_revertsWith_BadPathFormat() public {
        // Create an incorrectly formatted path (missing fee)
        bytes memory badPath = abi.encodePacked(address(tokenA), address(tokenB));

        // Setup swap params with bad path
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: badPath,
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: TOKEN_A_AMOUNT,
            amountOutMinimum: TOKEN_B_AMOUNT
        });

        // Should revert due to bad path format
        vm.prank(VAULT);
        vm.expectRevert(abi.encodeWithSelector(IUniswapV3DexHooks.AeraPeriphery__BadPathFormat.selector));
        hooks.exactInput(params);
    }

    function test_exactInput_MultiHop_revertsWith_BadPathFormat() public {
        // Create an incorrectly formatted multi-hop path (missing fee between B and C)
        bytes memory badPath = bytes.concat(
            abi.encodePacked(address(tokenA), uint24(FEE_30BPS), address(tokenB)),
            abi.encodePacked(address(tokenC)) // Missing fee between B and C
        );

        // Setup swap params with bad multi-hop path
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: badPath,
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: TOKEN_A_AMOUNT,
            amountOutMinimum: TOKEN_B_AMOUNT
        });

        // Should revert due to bad path format
        vm.prank(VAULT);
        vm.expectRevert(abi.encodeWithSelector(IUniswapV3DexHooks.AeraPeriphery__BadPathFormat.selector));
        hooks.exactInput(params);
    }

    function test_exactInput_revertsWith_ExcessiveSlippage() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 inputAmount = TOKEN_A_AMOUNT;
        uint256 minOutputAmount = TOKEN_B_AMOUNT;
        uint256 inputValueInNumeraire = TOKENS_PRICE_IN_NUMERAIRE;

        deal(address(tokenA), VAULT, inputAmount);

        // Pre-hooks quote for input value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: inputAmount,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: inputValueInNumeraire
        });

        uint256 outputValueInNumeraire =
            SwapUtils.applyLossToAmount(inputValueInNumeraire, 0, MAX_SLIPPAGE_100BPS + SLIPPAGE_10BPS);
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: minOutputAmount,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire
        });

        // Setup multi-hop path A -> C -> B
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenC);
        tokens[2] = address(tokenB);

        uint24[] memory fees = new uint24[](2);
        fees[0] = FEE_30BPS;
        fees[1] = FEE_30BPS;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: SwapUtils.encodePath(tokens, fees),
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: inputAmount,
            amountOutMinimum: minOutputAmount
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector,
                inputValueInNumeraire - outputValueInNumeraire,
                inputValueInNumeraire,
                MAX_SLIPPAGE_100BPS
            )
        );
        vm.prank(VAULT);
        hooks.exactInput(params);
    }

    function test_exactInput_revertsWith_ExcessiveDailyLoss() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint128 LOW_MAX_DAILY_LOSS = uint128(MAX_DAILY_LOSS / 100_000);
        uint16 HIGH_SLIPPAGE = uint16(MAX_SLIPPAGE_100BPS * 10);

        hooks.setMaxDailyLoss(VAULT, LOW_MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(VAULT, HIGH_SLIPPAGE);

        uint256 inputAmount = TOKEN_A_AMOUNT;
        uint256 minOutputAmount = TOKEN_B_AMOUNT;
        uint256 inputValueInNumeraire = TOKENS_PRICE_IN_NUMERAIRE;

        deal(address(tokenA), VAULT, inputAmount);

        // Pre-hooks quote for input value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: inputAmount,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: inputValueInNumeraire
        });

        uint256 outputValueInNumeraire = SwapUtils.applyLossToAmount(inputValueInNumeraire, 0, MAX_SLIPPAGE_100BPS * 9); // 9%
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: minOutputAmount,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire
        });

        // Setup multi-hop path A -> C -> B
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenC);
        tokens[2] = address(tokenB);

        uint24[] memory fees = new uint24[](2);
        fees[0] = FEE_30BPS;
        fees[1] = FEE_30BPS;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: SwapUtils.encodePath(tokens, fees),
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountIn: inputAmount,
            amountOutMinimum: minOutputAmount
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector,
                inputValueInNumeraire - outputValueInNumeraire,
                LOW_MAX_DAILY_LOSS
            )
        );
        vm.prank(VAULT);
        hooks.exactInput(params);
    }

    ////////////////////////////////////////////////////////////
    //            Uniswap V3 - Exact Output Single            //
    ////////////////////////////////////////////////////////////

    function test_exactOutputSingle_success() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 amountInMaximum = SwapUtils.applyGainToAmount(TOKEN_A_AMOUNT, FEE_30BPS, SLIPPAGE_10BPS);
        deal(address(tokenA), VAULT, amountInMaximum);

        // Pre-hooks oracle quotes - what the USDC output is worth
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: TOKEN_B_AMOUNT,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: TOKENS_PRICE_IN_NUMERAIRE
        });

        // What the max ETH input is worth - set lower to show loss
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountInMaximum,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: TOKENS_PRICE_IN_NUMERAIRE - 10e18
        });

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            fee: FEE_30BPS,
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountOut: TOKEN_B_AMOUNT,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        uint256 lossBefore = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        uint256 amountInNumeraire = oracleRegistry.getQuote(params.amountInMaximum, address(tokenA), address(numeraire));
        uint256 amountOutNumeraire = oracleRegistry.getQuote(params.amountOut, address(tokenB), address(numeraire));
        uint256 lossDuringSwap = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.prank(VAULT);
        hooks.exactOutputSingle(params);
        vm.snapshotGasLastCall("exactOutputSingle - success");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringSwap, "Loss does not match the slippage from the swap");
    }

    function test_exactOutputSingle_revertsWith_ExcessiveSlippage() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 amountOut = TOKEN_B_AMOUNT;
        uint256 amountInMaximum = TOKEN_A_AMOUNT;
        uint256 outputValueInNumeraire = TOKENS_PRICE_IN_NUMERAIRE;

        deal(address(tokenA), VAULT, amountInMaximum);

        // Pre-hooks quote for output value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountOut,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire
        });

        // Input value that causes excessive slippage
        uint256 inputValueInNumeraire =
            SwapUtils.applyGainToAmount(outputValueInNumeraire, 0, MAX_SLIPPAGE_100BPS + SLIPPAGE_10BPS);
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountInMaximum,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: inputValueInNumeraire
        });

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            fee: FEE_30BPS,
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector,
                inputValueInNumeraire - outputValueInNumeraire,
                inputValueInNumeraire,
                MAX_SLIPPAGE_100BPS
            )
        );
        vm.prank(VAULT);
        hooks.exactOutputSingle(params);
    }

    function test_exactOutputSingle_revertsWith_ExcessiveDailyLoss() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint128 LOW_MAX_DAILY_LOSS = uint128(MAX_DAILY_LOSS / 100_000);
        uint16 HIGH_SLIPPAGE = uint16(MAX_SLIPPAGE_100BPS * 10);

        hooks.setMaxDailyLoss(VAULT, LOW_MAX_DAILY_LOSS); // Set a very low daily loss limit
        hooks.setMaxSlippagePerTrade(VAULT, HIGH_SLIPPAGE); // Set high max slippage, so we can exceed the loss in 1
            // trade

        uint256 outputAmount = TOKEN_B_AMOUNT;
        uint256 amountInMaximum = TOKEN_A_AMOUNT;
        uint256 outputValueInNumeraire = TOKENS_PRICE_IN_NUMERAIRE;

        deal(address(tokenA), VAULT, amountInMaximum);

        // Pre-hooks quote for output value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: outputAmount,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire
        });

        // Set the input to be worth more (creating a loss)
        uint256 expectedLoss = 10e18;
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountInMaximum,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire + expectedLoss // Input worth more than output
         });

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            fee: FEE_30BPS,
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountOut: outputAmount,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector, expectedLoss, LOW_MAX_DAILY_LOSS
            )
        );
        vm.prank(VAULT);
        hooks.exactOutputSingle(params);
    }

    ////////////////////////////////////////////////////////////
    //               Uniswap V3 - Exact Output                //
    ////////////////////////////////////////////////////////////

    function test_exactOutput_success() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 amountInMaximum = SwapUtils.applyGainToAmount(TOKEN_A_AMOUNT, FEE_30BPS * 2, SLIPPAGE_10BPS);
        deal(address(tokenA), VAULT, amountInMaximum);

        // First oracle quote: what the USDC output is worth in numeraire
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: TOKEN_B_AMOUNT,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: TOKENS_PRICE_IN_NUMERAIRE
        });

        // Second oracle quote: what the maximum ETH input is worth in numeraire
        // This should be lower than what we actually use to show a loss
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountInMaximum,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: TOKENS_PRICE_IN_NUMERAIRE - 10e18 // Lower than final quote to show loss
         });

        // Setup multi-hop path A -> C -> B
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenC);
        tokens[2] = address(tokenB);

        uint24[] memory fees = new uint24[](2);
        fees[0] = FEE_30BPS;
        fees[1] = FEE_30BPS;

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: SwapUtils.encodePath(tokens, fees),
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountOut: TOKEN_B_AMOUNT,
            amountInMaximum: amountInMaximum
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Call hooks ~~~~~~~~~~
        uint256 lossBefore = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;

        // Final oracle quote: what the actual ETH input is worth in numeraire
        uint256 actualAmountIn = TOKEN_A_AMOUNT;
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: actualAmountIn,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: TOKENS_PRICE_IN_NUMERAIRE // Higher than initial quote
         });

        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: params.amountInMaximum - actualAmountIn,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: (params.amountInMaximum - actualAmountIn) * 10
        });
        uint256 amountInNumeraire = oracleRegistry.getQuote(params.amountInMaximum, address(tokenA), address(numeraire));
        uint256 amountOutNumeraire = oracleRegistry.getQuote(params.amountOut, address(tokenB), address(numeraire));
        uint256 lossDuringSwap = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.prank(VAULT);
        hooks.exactOutput(params);
        vm.snapshotGasLastCall("exactOutput - success - multi-hop");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringSwap, "Loss does not match the slippage from the swap");
    }

    function test_exactOutput_revertsWith_ExcessiveSlippage() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 outputAmount = TOKEN_B_AMOUNT;
        uint256 amountInMaximum = TOKEN_A_AMOUNT;
        uint256 outputValueInNumeraire = TOKENS_PRICE_IN_NUMERAIRE;

        deal(address(tokenA), VAULT, amountInMaximum);

        // Pre-hooks quote for output value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: outputAmount,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire
        });

        // Input value that causes excessive slippage
        uint256 inputValueInNumeraire =
            SwapUtils.applyGainToAmount(outputValueInNumeraire, 0, MAX_SLIPPAGE_100BPS + SLIPPAGE_10BPS);
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountInMaximum,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: inputValueInNumeraire
        });

        // Setup multi-hop path A -> C -> B
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenC);
        tokens[2] = address(tokenB);

        uint24[] memory fees = new uint24[](2);
        fees[0] = FEE_30BPS;
        fees[1] = FEE_30BPS;

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: SwapUtils.encodePath(tokens, fees),
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountOut: outputAmount,
            amountInMaximum: amountInMaximum
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector,
                inputValueInNumeraire - outputValueInNumeraire,
                inputValueInNumeraire,
                MAX_SLIPPAGE_100BPS
            )
        );
        vm.prank(VAULT);
        hooks.exactOutput(params);
    }

    function test_exactOutput_revertsWith_ExcessiveDailyLoss() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint128 LOW_MAX_DAILY_LOSS = uint128(MAX_DAILY_LOSS / 100_000);
        uint16 HIGH_SLIPPAGE = uint16(MAX_SLIPPAGE_100BPS * 10);

        hooks.setMaxDailyLoss(VAULT, LOW_MAX_DAILY_LOSS); // Set a very low daily loss limit
        hooks.setMaxSlippagePerTrade(VAULT, HIGH_SLIPPAGE); // Set high max slippage, so we can exceed the loss in 1
            // trade

        uint256 outputAmount = TOKEN_B_AMOUNT;
        uint256 amountInMaximum = TOKEN_A_AMOUNT;
        uint256 outputValueInNumeraire = TOKENS_PRICE_IN_NUMERAIRE;

        deal(address(tokenA), VAULT, amountInMaximum);

        // Pre-hooks quote for output value
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: outputAmount,
            baseToken: address(tokenB),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire
        });

        // Set the input to be worth more (creating a loss)
        uint256 expectedLoss = 10e18;
        SwapUtils.mock_OracleRegistry_GetQuote({
            vm: vm,
            registry: address(oracleRegistry),
            baseAmount: amountInMaximum,
            baseToken: address(tokenA),
            quoteToken: address(numeraire),
            quoteAmount: outputValueInNumeraire + expectedLoss // Input worth more than output
         });

        // Setup multi-hop path A -> C -> B
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenC);
        tokens[2] = address(tokenB);

        uint24[] memory fees = new uint24[](2);
        fees[0] = FEE_30BPS;
        fees[1] = FEE_30BPS;

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: SwapUtils.encodePath(tokens, fees),
            recipient: VAULT,
            deadline: vm.getBlockTimestamp() + 100,
            amountOut: outputAmount,
            amountInMaximum: amountInMaximum
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // ~~~~~~~~~~ Execute & Verify ~~~~~~~~~~
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector, expectedLoss, LOW_MAX_DAILY_LOSS
            )
        );
        vm.prank(VAULT);
        hooks.exactOutput(params);
    }
}
