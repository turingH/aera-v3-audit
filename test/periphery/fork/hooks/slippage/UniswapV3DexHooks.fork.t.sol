// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";

import { Authority } from "@solmate/auth/Auth.sol";
import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { TestForkBaseHooks } from "test/periphery/fork/hooks/TestForkBaseHooks.t.sol";

import { BaseVaultParameters, Clipboard, FeeVaultParameters, Operation } from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";
import { IOracle } from "src/dependencies/oracles/IOracle.sol";

import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { ISwapRouter } from "src/dependencies/uniswap/v3/interfaces/ISwapRouter.sol";
import { Encoder } from "test/core/utils/Encoder.sol";
import { MockChainlink7726Adapter } from "test/periphery/mocks/MockChainlink7726Adapter.sol";

import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

import { MockFeeVaultFactory } from "test/core/mocks/MockFeeVaultFactory.sol";

import { MockUniswapV3DexHooks } from "test/periphery/mocks/hooks/slippage/MockUniswapV3DexHooks.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract UniswapV3DexHooksForkTest is TestForkBaseHooks, MockFeeVaultFactory {
    // Constants for mainnet addresses
    address internal constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    uint24 internal constant POOL_FEE = 500; // 0.05% fee tier
    uint24 internal constant POOL_FEE_50BPS = 50; // 0.5% fee
    uint256 internal constant SLIPPAGE_100BPS = 100; // 1% slippage

    // Test contracts
    SingleDepositorVault public vault;
    MockUniswapV3DexHooks public dexHooks;
    ISwapRouter public router;
    OracleRegistry public oracleRegistry;

    // Test values
    uint256 internal constant INITIAL_WETH_BALANCE = 10 ether;
    uint128 internal constant MAX_DAILY_LOSS = 1000 * 10 ** 18; // 1,000 usdc with 18 decimals due to what oracle
        // returns
    uint16 internal constant MAX_SLIPPAGE = 300; // 3%

    bytes32[] internal leaves;

    function setUp() public override {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), 21_000_000);

        super.setUp();

        // Deploy DexHooks with USDC as numeraire and mine address to have both before and after hooks
        uint160 targetBits = uint160(1); // Set least significant bit - which makes this a before hook only
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockUniswapV3DexHooks(USDC)).code);
        dexHooks = MockUniswapV3DexHooks(address(targetAddress | targetBits));

        router = ISwapRouter(UNIV3_ROUTER);

        // Deploy and set up oracle registry with real Chainlink oracle
        vm.startPrank(users.owner);

        MockChainlink7726Adapter mockChainlink7726Adapter = new MockChainlink7726Adapter();
        mockChainlink7726Adapter.setFeed(WETH, USDC, CHAINLINK_ETH_USD);

        oracleRegistry = new OracleRegistry(users.owner, Authority(address(0)), ORACLE_UPDATE_DELAY);
        oracleRegistry.addOracle(WETH, USDC, IOracle(address(mockChainlink7726Adapter)));
        vm.stopPrank();

        setGuardian(users.guardian);
        setBaseVaultParameters(
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            })
        );
        setFeeVaultParameters(
            FeeVaultParameters({ feeCalculator: mockFeeCalculator, feeToken: feeToken, feeRecipient: users.feeRecipient })
        );
        vault = new SingleDepositorVault();

        // Set up dex hooks
        vm.startPrank(users.owner);
        vault.acceptOwnership();
        dexHooks.setOracleRegistry(address(vault), address(oracleRegistry));
        dexHooks.setMaxDailyLoss(address(vault), MAX_DAILY_LOSS);
        dexHooks.setMaxSlippagePerTrade(address(vault), MAX_SLIPPAGE);
        vault.setGuardianRoot(users.guardian, RANDOM_BYTES32);
        vm.stopPrank();

        // Fund vault with WETH
        deal(WETH, address(vault), INITIAL_WETH_BALANCE);

        // Set up merkle tree for allowed operations
        leaves = new bytes32[](5);

        // Leaf for exactInputSingle
        leaves[0] = MerkleHelper.getLeaf({
            target: UNIV3_ROUTER,
            selector: ISwapRouter.exactInputSingle.selector,
            hasValue: false,
            configurableHooksOffsets: new uint16[](0),
            hooks: address(dexHooks),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                WETH, // allowed tokenIn
                USDC, // allowed tokenOut
                address(vault) // allowed recipient
            )
        });

        // Leaf for exactOutputSingle
        leaves[1] = MerkleHelper.getLeaf({
            target: UNIV3_ROUTER,
            selector: ISwapRouter.exactOutputSingle.selector,
            hasValue: false,
            configurableHooksOffsets: new uint16[](0),
            hooks: address(dexHooks),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                WETH, // allowed tokenIn
                USDC, // allowed tokenOut
                address(vault) // allowed recipient
            )
        });

        // Leaf for exactInput
        leaves[2] = MerkleHelper.getLeaf({
            target: UNIV3_ROUTER,
            selector: ISwapRouter.exactInput.selector,
            hasValue: false,
            configurableHooksOffsets: new uint16[](0),
            hooks: address(dexHooks),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                WETH, // allowed tokenIn
                USDC, // allowed tokenOut
                address(vault) // allowed recipient
            )
        });

        // Leaf for exactOutput
        leaves[3] = MerkleHelper.getLeaf({
            target: UNIV3_ROUTER,
            selector: ISwapRouter.exactOutput.selector,
            hasValue: false,
            configurableHooksOffsets: new uint16[](0),
            hooks: address(dexHooks),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                WETH, // allowed tokenIn
                USDC, // allowed tokenOut
                address(vault) // allowed recipient
            )
        });

        // Leaf for approving tokens
        leaves[4] = MerkleHelper.getLeaf({
            target: WETH,
            selector: IERC20.approve.selector,
            hasValue: false,
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            hooks: address(0),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                address(router) // allowed spender
            )
        });

        vm.prank(users.owner);
        vault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        vm.label(address(vault), "VAULT");
        vm.label(address(dexHooks), "DEX_HOOKS");
        vm.label(address(oracleRegistry), "ORACLE_REGISTRY");
        vm.label(address(router), "UNI_V3_ROUTER");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");
        vm.label(address(CHAINLINK_ETH_USD), "CHAINLINK_ETH_USD_ORACLE");
        vm.label(address(CHAINLINK_USDC_USD), "CHAINLINK_USDC_USD_ORACLE");
    }

    ////////////////////////////////////////////////////////////
    //            Uniswap V3 - Exact Input Single             //
    ////////////////////////////////////////////////////////////
    function test_fork_exactInputSingle_success() public {
        uint256 amountOutMinimum =
            _getExpectedUsdcOutput(address(oracleRegistry), WETH, USDC, INITIAL_WETH_BALANCE, SLIPPAGE_100BPS);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: POOL_FEE,
            recipient: address(vault),
            deadline: vm.getBlockTimestamp() + 1000,
            amountIn: INITIAL_WETH_BALANCE,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        Operation[] memory ops = new Operation[](2);
        ops[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), INITIAL_WETH_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });
        ops[1] = Operation({
            target: UNIV3_ROUTER,
            data: abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(dexHooks),
            value: 0
        });

        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC balance should be 0");
        assertEq(
            IERC20(WETH).balanceOf(address(vault)), INITIAL_WETH_BALANCE, "WETH balance should be INITIAL_WETH_BALANCE"
        );
        uint256 lossBefore = dexHooks.vaultStates(address(vault)).cumulativeDailyLossInNumeraire;
        uint256 amountInNumeraire = _convertToNumeraire(address(oracleRegistry), params.amountIn, WETH);
        uint256 amountOutNumeraire = _convertToNumeraire(address(oracleRegistry), params.amountOutMinimum, USDC);
        uint256 lossDuringTrade = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            address(vault), WETH, USDC, amountInNumeraire, amountOutNumeraire, uint128(lossDuringTrade)
        );
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(ops));

        assertGt(
            IERC20(USDC).balanceOf(address(vault)),
            amountOutMinimum,
            "USDC balance should be greater than amountOutMinimum"
        );
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH balance should be 0");

        uint256 lossAfter = dexHooks.vaultStates(address(vault)).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringTrade, "Loss does not match the slippage from the swap");
    }

    function test_fork_exactInputSingle_revertsWith_ExcessiveSlippage() public {
        vm.prank(users.owner);
        dexHooks.setMaxSlippagePerTrade(address(vault), uint16(1)); // 0.01% slippage, which will trigger the revert

        uint256 amountOutMinimum =
            _getExpectedUsdcOutput(address(oracleRegistry), WETH, USDC, INITIAL_WETH_BALANCE, SLIPPAGE_100BPS);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: POOL_FEE,
            recipient: address(vault),
            deadline: vm.getBlockTimestamp() + 1000,
            amountIn: INITIAL_WETH_BALANCE,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        Operation[] memory ops = new Operation[](2);
        ops[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), INITIAL_WETH_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });
        ops[1] = Operation({
            target: UNIV3_ROUTER,
            data: abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(dexHooks),
            value: 0
        });

        // Note: because the error is in the beforeOperationHooks, it will be caught by the vault and re-thrown
        // as an `Aera__BeforeOperationHooksFailed` error. As we cannot know the actual slippage for sure, this is
        // a workaround which allows us to check the inner error's selector
        vm.prank(users.guardian);
        try vault.submit(Encoder.encodeOperations(ops)) {
            fail();
        } catch (bytes memory err) {
            assertEq(bytes4(err), IBaseVault.Aera__BeforeOperationHooksFailed.selector, "Wrong outer error");
            _checkInnerHooksError(err, IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector);
        }
    }

    function test_fork_exactInputSingle_revertsWith_ExcessiveDailyLoss() public {
        vm.prank(users.owner);
        dexHooks.setMaxDailyLoss(address(vault), 1 * 10 ** 6); // 1 USDC in decimals

        uint256 amountOutMinimum =
            _getExpectedUsdcOutput(address(oracleRegistry), WETH, USDC, INITIAL_WETH_BALANCE, SLIPPAGE_100BPS);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: POOL_FEE,
            recipient: address(vault),
            deadline: vm.getBlockTimestamp() + 1000,
            amountIn: INITIAL_WETH_BALANCE,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        Operation[] memory ops = new Operation[](2);
        ops[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), INITIAL_WETH_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });
        ops[1] = Operation({
            target: UNIV3_ROUTER,
            data: abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(dexHooks),
            value: 0
        });

        // Note: because the error is in the beforeOperationHooks, it will be caught by the vault and re-thrown
        // as an `Aera__BeforeOperationHooksFailed` error. As we cannot know the actual loss for sure, this is
        // a workaround which allows us to check the inner error's selector
        vm.prank(users.guardian);
        try vault.submit(Encoder.encodeOperations(ops)) {
            fail();
        } catch (bytes memory err) {
            assertEq(bytes4(err), IBaseVault.Aera__BeforeOperationHooksFailed.selector, "Wrong outer error");
            _checkInnerHooksError(err, IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector);
        }
    }

    ////////////////////////////////////////////////////////////
    //            Uniswap V3 - Exact Output Single            //
    ////////////////////////////////////////////////////////////
    function test_fork_exactOutputSingle_success() public {
        uint256 amountOut =
            _getExpectedUsdcOutput(address(oracleRegistry), WETH, USDC, INITIAL_WETH_BALANCE, SLIPPAGE_100BPS);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: POOL_FEE,
            recipient: address(vault),
            deadline: vm.getBlockTimestamp() + 1000,
            amountOut: amountOut,
            amountInMaximum: INITIAL_WETH_BALANCE,
            sqrtPriceLimitX96: 0
        });

        Operation[] memory ops = new Operation[](3);
        ops[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), INITIAL_WETH_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });
        ops[1] = Operation({
            target: UNIV3_ROUTER,
            data: abi.encodeWithSelector(ISwapRouter.exactOutputSingle.selector, params),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(dexHooks),
            value: 0
        });
        ops[2] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), 0),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });

        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC balance should be 0");
        assertEq(
            IERC20(WETH).balanceOf(address(vault)), INITIAL_WETH_BALANCE, "WETH balance should be INITIAL_WETH_BALANCE"
        );
        uint256 lossBefore = dexHooks.vaultStates(address(vault)).cumulativeDailyLossInNumeraire;
        uint256 amountInNumeraire = _convertToNumeraire(address(oracleRegistry), params.amountInMaximum, WETH);
        uint256 amountOutNumeraire = _convertToNumeraire(address(oracleRegistry), params.amountOut, USDC);
        uint256 lossDuringTrade = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            address(vault), WETH, USDC, amountInNumeraire, amountOutNumeraire, uint128(lossDuringTrade)
        );
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(ops));

        assertEq(IERC20(USDC).balanceOf(address(vault)), amountOut, "USDC balance should match expected output");
        assertLt(IERC20(WETH).balanceOf(address(vault)), INITIAL_WETH_BALANCE, "WETH balance should decrease");

        uint256 lossAfter = dexHooks.vaultStates(address(vault)).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringTrade, "Loss does not match the slippage from the swap");
    }

    function test_fork_exactOutputSingle_revertsWith_ExcessiveSlippage() public {
        vm.prank(users.owner);
        dexHooks.setMaxSlippagePerTrade(address(vault), 1);

        uint256 amountOut =
            _getExpectedUsdcOutput(address(oracleRegistry), WETH, USDC, INITIAL_WETH_BALANCE, SLIPPAGE_100BPS);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: POOL_FEE,
            recipient: address(vault),
            deadline: vm.getBlockTimestamp() + 1000,
            amountOut: amountOut,
            amountInMaximum: INITIAL_WETH_BALANCE,
            sqrtPriceLimitX96: 0
        });

        Operation[] memory ops = new Operation[](3);
        ops[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), INITIAL_WETH_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });
        ops[1] = Operation({
            target: UNIV3_ROUTER,
            data: abi.encodeWithSelector(ISwapRouter.exactOutputSingle.selector, params),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(dexHooks),
            value: 0
        });
        ops[2] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), 0),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });

        // Note: because the error is in the beforeOperationHooks, it will be caught by the vault and re-thrown
        // as an `Aera__BeforeOperationHooksFailed` error. As we cannot know the actual slippage for sure, this is
        // a workaround which allows us to check the inner error's selector
        vm.prank(users.guardian);
        try vault.submit(Encoder.encodeOperations(ops)) {
            fail();
        } catch (bytes memory err) {
            // Check errors
            assertEq(bytes4(err), IBaseVault.Aera__BeforeOperationHooksFailed.selector, "Wrong outer error");
            _checkInnerHooksError(err, IBaseSlippageHooks.AeraPeriphery__ExcessiveSlippage.selector);
        }
    }

    function test_fork_exactOutputSingle_revertsWith_ExcessiveDailyLoss() public {
        vm.startPrank(users.owner);
        dexHooks.setMaxDailyLoss(address(vault), 1 * 10 ** 6);
        dexHooks.setMaxSlippagePerTrade(address(vault), MAX_SLIPPAGE * 2);
        vm.stopPrank();

        uint256 amountInMaximum = INITIAL_WETH_BALANCE;
        uint256 amountOut = _getExpectedUsdcOutput(address(oracleRegistry), WETH, USDC, amountInMaximum, MAX_SLIPPAGE);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: 3000, // 0.3% fee
            recipient: address(vault),
            deadline: vm.getBlockTimestamp() + 1000,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        Operation[] memory ops = new Operation[](3);
        ops[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), INITIAL_WETH_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });
        ops[1] = Operation({
            target: UNIV3_ROUTER,
            data: abi.encodeWithSelector(ISwapRouter.exactOutputSingle.selector, params),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(dexHooks),
            value: 0
        });
        ops[2] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), 0),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });

        // Note: because the error is in the beforeOperationHooks, it will be caught by the vault and re-thrown
        // as an `Aera__BeforeOperationHooksFailed` error. As we cannot know the actual loss for sure, this is
        // a workaround which allows us to check the inner error's selector
        vm.prank(users.guardian);
        try vault.submit(Encoder.encodeOperations(ops)) {
            fail();
        } catch (bytes memory err) {
            // Check errors
            assertEq(bytes4(err), IBaseVault.Aera__BeforeOperationHooksFailed.selector, "Wrong outer error");
            _checkInnerHooksError(err, IBaseSlippageHooks.AeraPeriphery__ExcessiveDailyLoss.selector);
        }
    }

    function _convertToNumeraire(address oracleRegistry_, uint256 amount, address token)
        internal
        view
        returns (uint256)
    {
        if (token == USDC) return amount;
        return IOracle(oracleRegistry_).getQuote(amount, token, USDC);
    }
}
