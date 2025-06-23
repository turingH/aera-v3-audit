// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { BaseVaultParameters, Clipboard, FeeVaultParameters, Operation } from "src/core/Types.sol";

import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { IOracle } from "src/dependencies/oracles/IOracle.sol";
import { MilkmanRouter } from "src/periphery/MilkmanRouter.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { IMilkmanRouter } from "src/periphery/interfaces/IMilkmanRouter.sol";

import { MockFeeVaultFactory } from "test/core/mocks/MockFeeVaultFactory.sol";
import { TestForkBaseHooks } from "test/periphery/fork/hooks/TestForkBaseHooks.t.sol";
import { MockChainlink7726Adapter } from "test/periphery/mocks/MockChainlink7726Adapter.sol";

import { MockMilkmanHooks } from "test/periphery/mocks/hooks/slippage/MockMilkmanHooks.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract MilkmanHooksForkTest is TestForkBaseHooks, MockFeeVaultFactory {
    // Mainnet addresses
    address internal constant ROOT_MILKMAN = 0x060373D064d0168931dE2AB8DDA7410923d06E88; // `cowdao-grants/milkman`
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // Test values
    uint256 internal constant INITIAL_WETH_BALANCE = 1 ether;
    uint128 internal constant MAX_DAILY_LOSS = 1000 * 10 ** 18; // 1,000 usdc with 18 decimals due to what oracle
        // returns
    uint16 internal constant MAX_SLIPPAGE = 300; // 3%
    bytes32 internal constant APP_DATA = bytes32(keccak256("APP_DATA"));

    // keccak256("SwapRequested(address,address,uint256,address,address,address,bytes32,address,bytes)")
    bytes32 public constant MILKMAN_SWAP_REQUESTED_TOPIC =
        0xd20d03b4c57639fcde566f564cb04ab0d275bc2e226987aaf7d705a2c9346435;

    // Test contracts
    SingleDepositorVault public vault;
    MilkmanRouter public router;
    MockMilkmanHooks public hooks;
    OracleRegistry public oracleRegistry;

    bytes32[] internal leaves;

    function setUp() public override {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), 21_000_000);

        super.setUp();

        // Deploy DexHooks with USDC as numeraire and mine address to have both before and after hooks
        uint160 targetBits = uint160(1); // Set least significant bit - which makes this a before hook only
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockMilkmanHooks(USDC)).code);
        hooks = MockMilkmanHooks(address(targetAddress | targetBits));

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
        vault.setGuardianRoot(users.guardian, RANDOM_BYTES32);
        hooks.setOracleRegistry(address(vault), address(oracleRegistry));
        hooks.setMaxDailyLoss(address(vault), MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(address(vault), MAX_SLIPPAGE);
        vm.stopPrank();

        // Deploy MilkmanRouter
        router = new MilkmanRouter(address(vault), ROOT_MILKMAN);

        // Fund vault with WETH
        deal(WETH, address(vault), INITIAL_WETH_BALANCE);

        // Setup merkle tree for allowed operations
        leaves = new bytes32[](2);
        leaves[0] = MerkleHelper.getLeaf({
            target: address(router),
            selector: IMilkmanRouter.requestSell.selector,
            hasValue: false,
            configurableHooksOffsets: new uint16[](0),
            hooks: address(hooks),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                WETH, // allowed inputToken
                USDC // allowed outputToken
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
                address(router) // allowed spender
            )
        });

        vm.prank(users.owner);
        vault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        vm.label(address(vault), "VAULT");
        vm.label(address(hooks), "MILKMAN_HOOKS");
        vm.label(address(oracleRegistry), "ORACLE_REGISTRY");
        vm.label(address(router), "MILKMAN_ROUTER");
        vm.label(address(ROOT_MILKMAN), "ROOT_MILKMAN");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");
        vm.label(address(CHAINLINK_ETH_USD), "CHAINLINK_ETH_USD_ORACLE");
        vm.label(address(CHAINLINK_USDC_USD), "CHAINLINK_USDC_USD_ORACLE");
    }

    function test_fork_requestSell_success() public {
        // ~~~~~~~~~~ Execute ~~~~~~~~~~
        Operation[] memory ops = new Operation[](2);
        ops[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(router), INITIAL_WETH_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        ops[1] = Operation({
            target: address(router),
            data: abi.encodeWithSelector(
                IMilkmanRouter.requestSell.selector,
                INITIAL_WETH_BALANCE,
                WETH,
                USDC,
                APP_DATA,
                address(hooks),
                abi.encode(address(vault))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(hooks),
            value: 0
        });

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        assertEq(
            IERC20(WETH).balanceOf(address(vault)), INITIAL_WETH_BALANCE, "WETH balance should be INITIAL_WETH_BALANCE"
        );

        vm.recordLogs();
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(ops));

        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH balance should be 0");
    }
}
