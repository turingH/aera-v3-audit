// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { IOdosRouterV2 } from "src/dependencies/odos/interfaces/IOdosRouterV2.sol";

// solhint-disable-next-line no-unused-import
import { SELECTOR_SIZE, WORD_SIZE } from "src/core/Constants.sol";
import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { BaseVaultParameters, Clipboard, FeeVaultParameters, Operation } from "src/core/Types.sol";

import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { IOracle } from "src/dependencies/oracles/IOracle.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";

import { MockFeeVaultFactory } from "test/core/mocks/MockFeeVaultFactory.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { TestForkBaseHooks } from "test/periphery/fork/hooks/TestForkBaseHooks.t.sol";
import { MockChainlink7726Adapter } from "test/periphery/mocks/MockChainlink7726Adapter.sol";
import { MockOdosV2DexHooks } from "test/periphery/mocks/hooks/slippage/MockOdosV2DexHooks.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract OdosV2DexHooksForkTest is TestForkBaseHooks, MockFeeVaultFactory {
    // Mainnet addresses
    address internal constant ODOS_ROUTER = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    // hardcoded to this address because odos api was called with it
    address payable internal constant _BASE_VAULT = payable(0xE8496bB953d4a9866e5890bb9eCE401e4C07d633);

    // Test values
    uint256 internal constant INITIAL_WETH_BALANCE = 1 ether;
    uint128 internal constant MAX_DAILY_LOSS = 1000 * 10 ** 18; // 1,000 usdc with 18 decimals due to what oracle
        // returns
    uint16 internal constant SLIPPAGE_100BPS = 100; // 1%
    uint16 internal constant MAX_SLIPPAGE = 300; // 3%
    uint24 internal constant FEE_80BPS = 80; // 0.8%

    // Test contracts
    SingleDepositorVault public vault;
    MockOdosV2DexHooks public hooks;
    OracleRegistry public oracleRegistry;

    bytes32[] internal leaves;

    // Path and block number for it can be generated with `script/util/odos_path_generator.sh`
    // Example usage: `script/util/odos_path_generator.sh --input-token 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    // --output-token 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 --input-amount 1000000000000000000 --slippage 1 --vault
    // 0xE8496bB953d4a9866e5890bb9eCE401e4C07d633 --rpc-url $YOUR_RPC_URL`
    uint256 internal constant BLOCK_NUMBER = 21_917_405;

    // solhint-disable-start max-line-length
    bytes internal SWAP_DATA_WETH_USDC =
        hex"3b635ce4000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000009fdc82cfe97c6cb8fe89e23625b4746cbe8cabaf000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000009f43add5000000000000000000000000000000000000000000000000000000009dabf655000000000000000000000000e8496bb953d4a9866e5890bb9ece401e4c07d63300000000000000000000000000000000000000000000000000000000000001400000000000000000000000009fdc82cfe97c6cb8fe89e23625b4746cbe8cabaf00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000048010203000d0101010200ff000000000000000000000000000000000000000000e0554a476a092703abdb3ef35c80e0d76d32939fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000";
    // solhint-disable-end max-line-length

    function setUp() public override {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), BLOCK_NUMBER);

        super.setUp();

        // Deploy DexHooks with USDC as numeraire and mine address to have both before and after hooks
        uint160 targetBits = uint160(1); // Set least significant bit - which makes this a before hook only
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockOdosV2DexHooks(USDC)).code);
        hooks = MockOdosV2DexHooks(address(targetAddress | targetBits));

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
        deployCodeTo("SingleDepositorVault", _BASE_VAULT);
        vault = SingleDepositorVault(_BASE_VAULT);

        // Set up dex hooks
        vm.startPrank(users.owner);
        vault.acceptOwnership();
        hooks.setOracleRegistry(address(vault), address(oracleRegistry));
        hooks.setMaxDailyLoss(address(vault), MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(address(vault), MAX_SLIPPAGE);
        vault.setGuardianRoot(users.guardian, RANDOM_BYTES32);
        vm.stopPrank();

        // Fund vault with WETH
        deal(WETH, address(vault), INITIAL_WETH_BALANCE);

        // Setup merkle tree for allowed operations
        leaves = new bytes32[](2);

        leaves[0] = MerkleHelper.getLeaf({
            target: ODOS_ROUTER,
            selector: IOdosRouterV2.swap.selector,
            hasValue: false,
            configurableHooksOffsets: new uint16[](0),
            hooks: address(hooks),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                WETH, // allowed inputToken
                USDC, // allowed outputToken
                _BASE_VAULT // allowed outputReceiver
            )
        });
        leaves[1] = MerkleHelper.getLeaf({
            target: WETH,
            selector: IERC20.approve.selector,
            hasValue: false,
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            hooks: address(0),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                ODOS_ROUTER // allowed spender
            )
        });

        vm.prank(users.owner);
        vault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        vm.label(address(vault), "VAULT");
        vm.label(address(hooks), "DEX_HOOKS");
        vm.label(address(oracleRegistry), "ORACLE_REGISTRY");
        vm.label(address(ODOS_ROUTER), "ODOS_ROUTER");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");
        vm.label(address(CHAINLINK_ETH_USD), "CHAINLINK_ETH_USD_ORACLE");
        vm.label(address(CHAINLINK_USDC_USD), "CHAINLINK_USDC_USD_ORACLE");
    }

    function test_fork_swap_success() public {
        // ~~~~~~~~~~ Execute ~~~~~~~~~~
        uint256 inputAmount;
        uint256 outputMin;
        bytes memory swapData = SWAP_DATA_WETH_USDC;

        // The Odos router swap function has this layout:
        // function swap(
        //     address inputToken,
        //     uint256 inputAmount,
        //     address inputReceiver,
        //     address outputToken,
        //     uint256 outputQuote,
        //     uint256 outputMin,
        //     address outputReceiver,
        //     ...
        // )
        assembly {
            let ptr := add(swapData, SELECTOR_SIZE) // skip selector
            inputAmount := mload(add(ptr, mul(2, WORD_SIZE))) // second word
            outputMin := mload(add(ptr, mul(6, WORD_SIZE))) // sixth word
        }

        // Approve ODOS_ROUTER to spend WETH
        Operation[] memory ops = new Operation[](2);
        ops[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, ODOS_ROUTER, INITIAL_WETH_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        ops[1] = Operation({
            target: ODOS_ROUTER,
            data: SWAP_DATA_WETH_USDC,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(hooks),
            value: 0
        });

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC balance should be 0");
        assertEq(
            IERC20(WETH).balanceOf(address(vault)), INITIAL_WETH_BALANCE, "WETH balance should be INITIAL_WETH_BALANCE"
        );
        uint256 lossBefore = hooks.vaultStates(address(vault)).cumulativeDailyLossInNumeraire;
        uint256 amountInNumeraire = _convertToNumeraire(address(oracleRegistry), inputAmount, WETH);
        uint256 amountOutNumeraire = _convertToNumeraire(address(oracleRegistry), outputMin, USDC);
        uint256 lossDuringTrade = _calculateLoss(amountInNumeraire, amountOutNumeraire);

        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            address(vault), WETH, USDC, amountInNumeraire, amountOutNumeraire, uint128(lossDuringTrade)
        );
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(ops));

        assertGt(IERC20(USDC).balanceOf(address(vault)), 0, "USDC balance should be greater than expected output");
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH balance should be 0");

        uint256 lossAfter = hooks.vaultStates(address(vault)).cumulativeDailyLossInNumeraire;
        assertEq(lossAfter, lossBefore + lossDuringTrade, "Loss does not match the slippage from the swap");
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
