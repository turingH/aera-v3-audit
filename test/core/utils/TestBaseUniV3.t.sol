// SPDX-License-Identifier: UNLICENSED
// solhint-disable no-inline-assembly
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";

import { UniV3Library } from "test/dependencies/UniV3Library.sol";
import { INonfungiblePositionManager } from "test/dependencies/interfaces/INonfungiblePositionManager.sol";
import { INonfungibleTokenPositionDescriptor } from
    "test/dependencies/interfaces/INonfungibleTokenPositionDescriptor.sol";
import { ISwapRouter } from "test/dependencies/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "test/dependencies/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "test/dependencies/interfaces/IUniswapV3Pool.sol";
import { IWETH } from "test/dependencies/interfaces/IWETH.sol";

abstract contract TestBaseUniV3 is Test {
    IWETH public weth;
    ISwapRouter public uniV3SwapRouter;
    IUniswapV3Factory public uniV3Factory;
    INonfungiblePositionManager public uniV3PositionManager;
    INonfungibleTokenPositionDescriptor public uniV3PositionDescriptor;

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;

    uint128 internal constant INITIAL_LIQUIDITY = 1e23;

    int256 internal constant TICK_SPACING = 200;
    int24 internal constant MIN_TICK = int24(-887_272 / TICK_SPACING * TICK_SPACING);
    int24 internal constant MAX_TICK = -MIN_TICK;

    uint160 internal immutable MIN_TICK_SQRT_PRICE = UniV3Library.getSqrtRatioAtTick(MIN_TICK);
    uint160 internal immutable MAX_TICK_SQRT_PRICE = UniV3Library.getSqrtRatioAtTick(MAX_TICK);

    int24 internal constant STARTING_TICK = 1000;

    uint24 internal constant DEFAULT_FEE = 10_000;

    address internal constant NFT_DESCRIPTOR_ADDRESS = 0x42B24A95702b9986e82d421cC3568932790A48Ec;
    address internal constant UNISWAP_V3_ROUTER_MAINNET = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint16 internal constant AMOUNT_INOUT_WORDS = 5;

    function setUp() public virtual {
        address newWeth = _deployWeth();
        address newV3Factory = _deployUniswapV3Factory();

        address newSwapRouter = _deployUniswapV3SwapRouter(newV3Factory, newWeth);
        address newPositionDescriptor = _deployPositionDescriptor(newWeth);
        address newPositionManager = _deployUniswapV3PositionManager(newV3Factory, newWeth, newPositionDescriptor);

        weth = IWETH(newWeth);
        uniV3SwapRouter = ISwapRouter(newSwapRouter);
        uniV3Factory = IUniswapV3Factory(newV3Factory);
        uniV3PositionManager = INonfungiblePositionManager(newPositionManager);
        uniV3PositionDescriptor = INonfungibleTokenPositionDescriptor(newPositionDescriptor);

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        vm.label(newSwapRouter, "UNI_SWAP_ROUTER");
        vm.label(newPositionDescriptor, "UNI_POSITION_DESCRIPTOR");
        vm.label(newPositionManager, "UNI_POSITION_MANAGER");
        vm.label(newWeth, "UNI_WETH");
        vm.label(newV3Factory, "UNI_V3_FACTORY");
        vm.label(UNISWAP_V3_ROUTER_MAINNET, "UNISWAP_V3_ROUTER_MAINNET");
    }

    function _deployNFTDescriptor() internal {
        bytes memory bytecode = abi.encodePacked(vm.getCode("test/dependencies/artifacts/uniswap/NFTDescriptor.json"));
        address deployed;
        assembly ("memory-safe") {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        // Set the bytecode of an arbitrary address
        vm.etch(NFT_DESCRIPTOR_ADDRESS, deployed.code);
    }

    function _deployUniswapV3Factory() internal returns (address newUniswapV3Factory) {
        bytes memory bytecode =
            abi.encodePacked(vm.getCode("test/dependencies/artifacts/uniswap/UniswapV3Factory.json"));

        assembly ("memory-safe") {
            newUniswapV3Factory := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function _deployUniswapV3SwapRouter(address newV3Factory, address newWeth)
        internal
        returns (address newUniswapV3SwapRouter)
    {
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("test/dependencies/artifacts/uniswap/SwapRouter.json"), abi.encode(newV3Factory, newWeth)
        );

        assembly ("memory-safe") {
            newUniswapV3SwapRouter := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function _deployPositionDescriptor(address newWeth) internal returns (address newUniswapV3Position) {
        _deployNFTDescriptor();

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("test/dependencies/artifacts/uniswap/NonfungibleTokenPositionDescriptor.json"),
            abi.encode(newWeth)
        );

        assembly ("memory-safe") {
            newUniswapV3Position := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function _deployUniswapV3PositionManager(address newV3Factory, address newWeth, address newTokenDescriptor)
        internal
        returns (address newUniswapV3SwapRouter)
    {
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("test/dependencies/artifacts/uniswap/NonfungiblePositionManager.json"),
            abi.encode(newV3Factory, newWeth, newTokenDescriptor)
        );

        assembly ("memory-safe") {
            newUniswapV3SwapRouter := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function _deployWeth() internal returns (address newWeth) {
        bytes memory bytecode = abi.encodePacked(vm.getCode("test/dependencies/artifacts/uniswap/WETH9.json"));

        assembly ("memory-safe") {
            newWeth := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function _createUniV3PoolAndAddLiquidity(address token0, address token1, uint128 liquidity, address recipient)
        internal
    {
        address pool = uniV3Factory.createPool(token0, token1, DEFAULT_FEE);
        uint160 sqrtPriceX96 = UniV3Library.getSqrtRatioAtTick(STARTING_TICK);
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        (uint256 amount0, uint256 amount1) =
            UniV3Library.getAmountsForLiquidity(sqrtPriceX96, MIN_TICK_SQRT_PRICE, MAX_TICK_SQRT_PRICE, liquidity);

        ERC20Mock(token0).mint(address(this), amount0);
        ERC20Mock(token0).approve(address(uniV3PositionManager), amount0);
        ERC20Mock(token1).mint(address(this), amount1);
        ERC20Mock(token1).approve(address(uniV3PositionManager), amount1);

        uniV3PositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: DEFAULT_FEE,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 1,
                amount1Min: 1,
                recipient: recipient,
                deadline: vm.getBlockTimestamp()
            })
        );
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        IERC20(tokenIn).approve(address(uniV3SwapRouter), amountIn);

        address pool = uniV3Factory.getPool(tokenIn, tokenOut, DEFAULT_FEE);

        address token0 = IUniswapV3Pool(pool).token0();

        return uniV3SwapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: DEFAULT_FEE,
                recipient: address(this),
                deadline: vm.getBlockTimestamp(),
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: token0 == tokenIn
                    ? UniV3Library.getSqrtRatioAtTick(MAX_TICK)
                    : UniV3Library.getSqrtRatioAtTick(MIN_TICK)
            })
        );
    }

    function _getInputSwapParams(address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 amountIn)
        internal
        view
        returns (ISwapRouter.ExactInputSingleParams memory)
    {
        return ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: recipient,
            deadline: vm.getBlockTimestamp() + 1000,
            amountIn: amountIn,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });
    }

    function _getOutputSwapParams(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum
    ) internal view returns (ISwapRouter.ExactOutputSingleParams memory) {
        return ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: recipient,
            deadline: vm.getBlockTimestamp() + 1000,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });
    }

    /*     function _createSwapOperations(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        returns (Operation[] memory operations)
    {
        address pool = uniV3Factory.getPool(tokenIn, tokenOut, DEFAULT_FEE);
        address token0 = IUniswapV3Pool(pool).token0();

        operations = new Operation[](2);
        operations[0] = Operation({
            target: tokenIn,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(uniV3SwapRouter), amountIn),
            proof: new bytes32[](0)
        });

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: DEFAULT_FEE,
            recipient: address(this),
            deadline: vm.getBlockTimestamp(),
            amountIn: amountIn,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: token0 == tokenIn
                ? UniV3Library.getSqrtRatioAtTick(MIN_TICK)
                : UniV3Library.getSqrtRatioAtTick(MAX_TICK)
        });

        operations[1] = Operation({
            target: address(uniV3SwapRouter),
            data: abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params),
            proof: new bytes32[](0)
        });
    } */
}
