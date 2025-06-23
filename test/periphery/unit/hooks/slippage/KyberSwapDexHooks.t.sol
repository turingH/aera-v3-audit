// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { IAggregationExecutor } from "src/dependencies/kyberswap/interfaces/IAggregationExecutor.sol";
import { IMetaAggregationRouterV2 } from "src/dependencies/kyberswap/interfaces/IMetaAggregationRouterV2.sol";

import { KYBERSWAP_ETH_ADDRESS } from "src/periphery/Constants.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { KyberSwapDexHooks } from "src/periphery/hooks/slippage/KyberSwapDexHooks.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";
import { IKyberSwapDexHooks } from "src/periphery/interfaces/hooks/slippage/IKyberSwapDexHooks.sol";

import { MockKyberSwapDexHooks } from "test/periphery/mocks/hooks/slippage/MockKyberSwapDexHooks.sol";
import { SwapUtils } from "test/periphery/utils/SwapUtils.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract KyberSwapDexHooksTest is BaseTest {
    KyberSwapDexHooks public hooks;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public numeraire;
    OracleRegistry public oracleRegistry;

    address public constant VAULT = address(0xabcdef);
    address public constant KYBERSWAP_EXECUTOR = address(0x0F4A1D7FdF4890bE35e71f3E0Bbc4a0EC377eca3);
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

        // Deploy KyberSwap Hooks with USDC as numeraire and mine address to have before hooks
        uint160 targetBits = uint160(1); // Set least significant bit
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockKyberSwapDexHooks(address(numeraire))).code);
        hooks = MockKyberSwapDexHooks(address(targetAddress | targetBits));

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
    //                    KyberSwap - swap                    //
    ////////////////////////////////////////////////////////////
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

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: VAULT,
            amount: INPUT_AMOUNT,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });

        IMetaAggregationRouterV2.SwapExecutionParams memory execution = IMetaAggregationRouterV2.SwapExecutionParams({
            callTarget: KYBERSWAP_EXECUTOR,
            approveTarget: address(0),
            targetData: hex"",
            desc: desc,
            clientData: hex""
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
        hooks.swap(execution);
        vm.snapshotGasLastCall("swap - success");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringSwap, "Loss does not match the slippage from the swap");
    }

    function test_swap_revertsWith_InputTokenIsETH() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 minOutput = SwapUtils.applyLossToAmount(INPUT_AMOUNT, 0, SLIPPAGE_10BPS);

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(KYBERSWAP_ETH_ADDRESS),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: VAULT,
            amount: INPUT_AMOUNT,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });

        IMetaAggregationRouterV2.SwapExecutionParams memory execution = IMetaAggregationRouterV2.SwapExecutionParams({
            callTarget: KYBERSWAP_EXECUTOR,
            approveTarget: address(0),
            targetData: hex"",
            desc: desc,
            clientData: hex""
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        vm.expectRevert(IBaseSlippageHooks.AeraPeriphery__InputTokenIsETH.selector);
        vm.prank(VAULT);
        hooks.swap(execution);
    }

    function test_swap_revertsWith_OutputTokenIsETH() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 minOutput = SwapUtils.applyLossToAmount(INPUT_AMOUNT, 0, SLIPPAGE_10BPS);

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(KYBERSWAP_ETH_ADDRESS),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: VAULT,
            amount: INPUT_AMOUNT,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });

        IMetaAggregationRouterV2.SwapExecutionParams memory execution = IMetaAggregationRouterV2.SwapExecutionParams({
            callTarget: KYBERSWAP_EXECUTOR,
            approveTarget: address(0),
            targetData: hex"",
            desc: desc,
            clientData: hex""
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        vm.expectRevert(IBaseSlippageHooks.AeraPeriphery__OutputTokenIsETH.selector);
        vm.prank(VAULT);
        hooks.swap(execution);
    }

    function test_swap_revertsWith_FeeReceiversNotEmpty() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 minOutput = SwapUtils.applyLossToAmount(INPUT_AMOUNT, 0, SLIPPAGE_10BPS);
        address[] memory feeReceivers = new address[](1);
        uint256[] memory feeAmounts = new uint256[](1);
        feeReceivers[0] = users.guardian;
        feeAmounts[0] = INPUT_AMOUNT / 1000; // 0.1% fee

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: feeReceivers,
            feeAmounts: feeAmounts,
            dstReceiver: VAULT,
            amount: INPUT_AMOUNT,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });

        IMetaAggregationRouterV2.SwapExecutionParams memory execution = IMetaAggregationRouterV2.SwapExecutionParams({
            callTarget: KYBERSWAP_EXECUTOR,
            approveTarget: address(0),
            targetData: hex"",
            desc: desc,
            clientData: hex""
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        vm.expectRevert(IKyberSwapDexHooks.AeraPeriphery__FeeReceiversNotEmpty.selector);
        vm.prank(VAULT);
        hooks.swap(execution);
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

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: VAULT,
            amount: inputAmount,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });

        IMetaAggregationRouterV2.SwapExecutionParams memory execution = IMetaAggregationRouterV2.SwapExecutionParams({
            callTarget: KYBERSWAP_EXECUTOR,
            approveTarget: address(0),
            targetData: hex"",
            desc: desc,
            clientData: hex""
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // 1) Pre-hooks call
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector,
                inputValue - outputValue,
                inputValue,
                MAX_SLIPPAGE_100BPS
            )
        );
        vm.prank(VAULT);
        hooks.swap(execution);
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

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: VAULT,
            amount: inputAmount,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });

        IMetaAggregationRouterV2.SwapExecutionParams memory execution = IMetaAggregationRouterV2.SwapExecutionParams({
            callTarget: KYBERSWAP_EXECUTOR,
            approveTarget: address(0),
            targetData: hex"",
            desc: desc,
            clientData: hex""
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // 1) Pre-hooks call
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector,
                inputValue - outputValue,
                LOW_MAX_DAILY_LOSS
            )
        );
        vm.prank(VAULT);
        hooks.swap(execution);
    }

    ////////////////////////////////////////////////////////////////
    //                 KyberSwap - swapSimpleMode                 //
    ////////////////////////////////////////////////////////////////
    function test_swapSimpleMode_success() public {
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

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: VAULT,
            amount: INPUT_AMOUNT,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
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
        hooks.swapSimpleMode(IAggregationExecutor(KYBERSWAP_EXECUTOR), desc, hex"", hex"");
        vm.snapshotGasLastCall("swapSimpleMode - success");

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        uint256 lossAfter = hooks.vaultStates(VAULT).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringSwap, "Loss does not match the slippage from the swap");
    }

    function test_swapSimpleMode_revertsWith_FeeReceiversNotEmpty() public {
        // ~~~~~~~~~~ Setup ~~~~~~~~~~
        uint256 minOutput = SwapUtils.applyLossToAmount(INPUT_AMOUNT, 0, SLIPPAGE_10BPS);
        address[] memory feeReceivers = new address[](1);
        uint256[] memory feeAmounts = new uint256[](1);
        feeReceivers[0] = users.guardian;
        feeAmounts[0] = INPUT_AMOUNT / 1000; // 0.1% fee

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: feeReceivers,
            feeAmounts: feeAmounts,
            dstReceiver: VAULT,
            amount: INPUT_AMOUNT,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        vm.expectRevert(IKyberSwapDexHooks.AeraPeriphery__FeeReceiversNotEmpty.selector);
        vm.prank(VAULT);
        hooks.swapSimpleMode(IAggregationExecutor(KYBERSWAP_EXECUTOR), desc, hex"", hex"");
    }

    function test_swapSimpleMode_revertsWith_ExcessiveSlippage() public {
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

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: VAULT,
            amount: inputAmount,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // 1) Pre-hooks call
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector,
                inputValue - outputValue,
                inputValue,
                MAX_SLIPPAGE_100BPS
            )
        );
        vm.prank(VAULT);
        hooks.swapSimpleMode(IAggregationExecutor(KYBERSWAP_EXECUTOR), desc, hex"", hex"");
    }

    function test_swapSimpleMode_revertsWith_ExcessiveDailyLoss() public {
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

        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
            srcToken: IERC20(tokenA),
            dstToken: IERC20(tokenB),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: VAULT,
            amount: inputAmount,
            minReturnAmount: minOutput,
            flags: 0,
            permit: hex""
        });

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        // 1) Pre-hooks call
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector,
                inputValue - outputValue,
                LOW_MAX_DAILY_LOSS
            )
        );
        vm.prank(VAULT);
        hooks.swapSimpleMode(IAggregationExecutor(KYBERSWAP_EXECUTOR), desc, hex"", hex"");
    }
}
