// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { ITokenMessengerV2 } from "src/dependencies/CCTP/interfaces/ITokenMessengerV2.sol";

import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { BaseVaultParameters, Clipboard, FeeVaultParameters, Operation } from "src/core/Types.sol";

import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { OracleRegistry } from "src/periphery/OracleRegistry.sol";

import { IBaseSlippageHooks } from "src/periphery/interfaces/hooks/slippage/IBaseSlippageHooks.sol";
import { MockFeeVaultFactory } from "test/core/mocks/MockFeeVaultFactory.sol";
import { TestForkBaseHooks } from "test/periphery/fork/hooks/TestForkBaseHooks.t.sol";
import { MockCCTPHooks } from "test/periphery/mocks/hooks/slippage/MockCCTPHooks.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract CCTPHooksForkTest is TestForkBaseHooks, MockFeeVaultFactory {
    // Mainnet addresses
    address internal constant CCTP_TOKEN_MESSENGER = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    uint32 internal constant BASE_DOMAIN_ID = 6;
    uint32 internal constant FINALITY_THRESHOLD_STANDARD = 2000;
    uint32 internal constant FINALITY_THRESHOLD_FAST = 1000;

    // Test values
    uint256 internal constant INITIAL_USDC_BALANCE = 100_000 * 10 ** 6;
    uint128 internal constant MAX_DAILY_LOSS = 1000 * 10 ** 18; // 1,000 usdc with 18 decimals due to what oracle
        // returns
    uint16 internal constant MAX_SLIPPAGE = 10; // 0.1%

    // Test contracts
    SingleDepositorVault public vault;
    MockCCTPHooks public hooks;
    OracleRegistry public oracleRegistry;

    bytes32[] internal leaves;

    function setUp() public override {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), 22_287_975);

        super.setUp();

        // Deploy CCTP Hooks with USDC as numeraire and mine address to have before hooks
        uint160 targetBits = uint160(1); // Set least significant bit
        uint160 targetAddress = uint160(vm.randomUint()) & ~uint160(3); // Clear bottom 2 bits
        vm.etch(address(targetAddress | targetBits), address(new MockCCTPHooks(USDC)).code);
        hooks = MockCCTPHooks(address(targetAddress | targetBits));

        // Deploy and set up oracle registry with real Chainlink oracle
        vm.startPrank(users.owner);

        oracleRegistry = new OracleRegistry(address(this), Authority(address(0)), 15 days);

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

        // Set up hooks
        vm.startPrank(users.owner);
        vault.acceptOwnership();
        vault.setGuardianRoot(users.guardian, RANDOM_BYTES32);
        hooks.setOracleRegistry(address(vault), address(oracleRegistry));
        hooks.setMaxDailyLoss(address(vault), MAX_DAILY_LOSS);
        hooks.setMaxSlippagePerTrade(address(vault), MAX_SLIPPAGE);
        vm.stopPrank();

        // Fund vault with USDC
        deal(USDC, address(vault), INITIAL_USDC_BALANCE);

        // Setup merkle tree for allowed operations
        leaves = new bytes32[](2);

        // Leaf for bridge
        leaves[0] = MerkleHelper.getLeaf({
            target: CCTP_TOKEN_MESSENGER,
            selector: ITokenMessengerV2.depositForBurn.selector,
            hasValue: false,
            configurableHooksOffsets: new uint16[](0),
            hooks: address(hooks),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                BASE_DOMAIN_ID, // destination domain id
                address(vault), // allowed recipient
                USDC // bridge token
            )
        });

        // Leaf for approving tokens
        leaves[1] = MerkleHelper.getLeaf({
            target: USDC,
            selector: IERC20.approve.selector,
            hasValue: false,
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            hooks: address(0),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(
                CCTP_TOKEN_MESSENGER // allowed spender
            )
        });

        vm.prank(users.owner);
        vault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        vm.label(address(vault), "VAULT");
        vm.label(address(hooks), "CCTP_HOOKS");
        vm.label(address(oracleRegistry), "ORACLE_REGISTRY");
        vm.label(address(CCTP_TOKEN_MESSENGER), "CCTP_TOKEN_MESSENGER");
        vm.label(address(USDC), "USDC");
        vm.label(address(CHAINLINK_USDC_USD), "CHAINLINK_USDC_USD_ORACLE");
    }

    function test_fork_standardTransfer_success() public {
        // Approve CCTP_TOKEN_MESSENGER to spend USDC
        Operation[] memory ops = new Operation[](2);
        ops[0] = Operation({
            target: USDC,
            data: abi.encodeWithSelector(IERC20.approve.selector, CCTP_TOKEN_MESSENGER, INITIAL_USDC_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        bytes memory standardTransferData = abi.encodeWithSelector(
            ITokenMessengerV2.depositForBurn.selector,
            INITIAL_USDC_BALANCE,
            BASE_DOMAIN_ID,
            bytes32(uint256(uint160(address(vault)))),
            USDC,
            bytes32(0),
            0,
            FINALITY_THRESHOLD_STANDARD
        );

        ops[1] = Operation({
            target: CCTP_TOKEN_MESSENGER,
            data: standardTransferData,
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
            IERC20(USDC).balanceOf(address(vault)), INITIAL_USDC_BALANCE, "USDC balance should be INITIAL_USDC_BALANCE"
        );
        uint256 usdcTotalSupply = IERC20(USDC).totalSupply();

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(ops));

        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC balance should be 0");
        assertEq(
            usdcTotalSupply - IERC20(USDC).totalSupply(),
            INITIAL_USDC_BALANCE,
            "INITIAL_USDC_BALANCE should be burned on the source chain"
        );
        assertEq(
            hooks.vaultStates(address(vault)).cumulativeDailyLossInNumeraire,
            0,
            "Loss should be zero for standard transfers"
        );
    }

    function test_fork_fastTransfer_success() public {
        // Approve CCTP_TOKEN_MESSENGER to spend USDC
        Operation[] memory ops = new Operation[](2);
        ops[0] = Operation({
            target: USDC,
            data: abi.encodeWithSelector(IERC20.approve.selector, CCTP_TOKEN_MESSENGER, INITIAL_USDC_BALANCE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        uint256 maxFee = 1;
        bytes memory standardTransferData = abi.encodeWithSelector(
            ITokenMessengerV2.depositForBurn.selector,
            INITIAL_USDC_BALANCE,
            BASE_DOMAIN_ID,
            bytes32(uint256(uint160(address(vault)))),
            USDC,
            bytes32(0),
            maxFee,
            FINALITY_THRESHOLD_FAST
        );

        ops[1] = Operation({
            target: CCTP_TOKEN_MESSENGER,
            data: standardTransferData,
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
            IERC20(USDC).balanceOf(address(vault)), INITIAL_USDC_BALANCE, "USDC balance should be INITIAL_USDC_BALANCE"
        );
        uint256 usdcTotalSupply = IERC20(USDC).totalSupply();

        vm.expectEmit(true, true, true, true);
        emit IBaseSlippageHooks.TradeSlippageChecked(
            address(vault), USDC, USDC, INITIAL_USDC_BALANCE, INITIAL_USDC_BALANCE - maxFee, uint128(maxFee)
        );
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(ops));

        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "USDC balance should be 0");
        assertEq(
            usdcTotalSupply - IERC20(USDC).totalSupply(),
            INITIAL_USDC_BALANCE,
            "INITIAL_USDC_BALANCE should be burned on the source chain"
        );
        assertEq(
            hooks.vaultStates(address(vault)).cumulativeDailyLossInNumeraire,
            maxFee,
            "Loss should equal the fee in fast transfers"
        );
    }
}
