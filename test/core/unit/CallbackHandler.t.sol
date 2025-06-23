// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { Approval, BaseVaultParameters, CallbackData, Clipboard, Operation, ReturnValueType } from "src/core/Types.sol";

import { NO_CALLBACK_DATA } from "src/core/Constants.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";
import { ICallbackHandler } from "src/core/interfaces/ICallbackHandler.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";
import { IFlashLoanRecipient } from "test/core/mocks/IFlashLoanRecipient.sol";

import { MockBaseVaultFactory } from "test/core/mocks/MockBaseVaultFactory.sol";
import { MockCallbackHandler } from "test/core/mocks/MockCallbackHandler.sol";
import { MockFlashLoanProvider } from "test/core/mocks/MockFlashLoanProvider.sol";
import { BaseMerkleTree } from "test/utils/BaseMerkleTree.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract CallbackHandlerTest is BaseTest, BaseMerkleTree, MockBaseVaultFactory {
    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;
    ERC20Mock internal tokenC;
    MockCallbackHandler internal vault;
    MockFlashLoanProvider internal flashloanProvider;

    function setUp() public override {
        super.setUp();

        flashloanProvider = new MockFlashLoanProvider{ salt: "flashloanProvider" }();

        vault = MockCallbackHandler(BASE_VAULT);

        tokenA = new ERC20Mock{ salt: "tokenA" }();
        tokenB = new ERC20Mock{ salt: "tokenB" }();
        tokenC = new ERC20Mock{ salt: "tokenC" }();
        tokenA.mint(address(flashloanProvider), 100e18);
        tokenB.mint(address(flashloanProvider), 100e18);
        tokenC.mint(address(flashloanProvider), 100e18);

        leaves.push(_getSimpleLeaf(address(tokenA), IERC20.approve.selector));
        leaves.push(_getSimpleLeaf(address(tokenB), IERC20.approve.selector));
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashloanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashloanProvider),
                    selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                    calldataOffset: _calculateFlashLoanOffset(1, 1)
                }),
                extractedData: ""
            })
        );
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashloanProvider),
                selector: MockFlashLoanProvider.emptyCallback.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashloanProvider),
                    selector: IFlashLoanRecipient.emptyCallback.selector,
                    calldataOffset: NO_CALLBACK_DATA
                }),
                extractedData: ""
            })
        );
        leaves.push(_getSimpleLeaf(address(tokenC), IERC20.approve.selector));
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashloanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(0xabcd),
                    selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                    calldataOffset: _calculateFlashLoanOffset(1, 1)
                }),
                extractedData: ""
            })
        );
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashloanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashloanProvider),
                    selector: bytes4(0),
                    calldataOffset: _calculateFlashLoanOffset(1, 1)
                }),
                extractedData: ""
            })
        );
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashloanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashloanProvider),
                    selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                    calldataOffset: _calculateFlashLoanOffset(3, 3)
                }),
                extractedData: ""
            })
        );

        setGuardian(users.guardian);

        // Generate merkle root from leaves
        root = MerkleHelper.getRoot(leaves);

        setBaseVaultParameters(
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            })
        );
        deployCodeTo("MockCallbackHandler.sol", "", BASE_VAULT);
        vault = MockCallbackHandler(BASE_VAULT);

        vm.prank(users.owner);
        vault.acceptOwnership();
        vm.prank(users.owner);
        vault.setGuardianRoot(users.guardian, root);

        // Label addresses for better trace output
        vm.label(address(tokenA), "Token A");
        vm.label(address(tokenB), "Token B");
        vm.label(address(tokenC), "Token C");
        vm.label(address(flashloanProvider), "Flashloan Provider");
    }

    ////////////////////////////////////////////////////////////
    //                     allowCallback                      //
    ////////////////////////////////////////////////////////////

    function test_allowCallback_success() external {
        address caller = address(uint160(1));
        bytes4 selector = bytes4(uint32(2));
        uint16 offsetIn = uint16(3);

        uint256 _callbackData = vault.packCallbackData(caller, selector, offsetIn);

        /* Note: in `forge test --isolate`, calling allowCallback() and getAllowedCallback()
        *  separately causes the transient slot to be empty because `--isolate` runs the test
        *  on a clean EVM state for each external call for each external call. This is a workaround to test saving and
        *  fetching the slot closely to how it would be done in production, which is actually in the same `submit` call.
        */
        // vault.allowCallback(_callbackData);
        // (address _allowedCaller, bytes4 _allowedSelector, uint16 _allowedOffset) = vault.getAllowedCallback();
        (address _allowedCaller, bytes4 _allowedSelector, uint16 _allowedOffset) =
            vault.allowCallbackAndGetAllowedCallback(root, _callbackData);
        vm.snapshotGasLastCall("allowCallback - success");

        assertEq(caller, _allowedCaller, "Callers aren't equal");
        assertEq(selector, _allowedSelector, "Selectors aren't equal");
        assertEq(offsetIn, _allowedOffset, "Offsets aren't equal");
    }

    function test_fuzz_allowCallback_success(address caller, bytes4 selector, uint16 offset) external {
        uint256 _callbackData = vault.packCallbackData(caller, selector, offset);

        /* Note: in `forge test --isolate`, calling allowCallback() and getAllowedCallback()
        *  separately causes the transient slot to be empty because `--isolate` runs the test
        *  on a clean EVM state for each external call for each external call. This is a workaround to test saving and
        *  fetching the slot closely to how it would be done in production, which is actually in the same `submit` call.
        */
        // vault.allowCallback(_callbackData);
        // (address _allowedCaller, bytes4 _allowedSelector, uint16 _allowedOffset) = vault.getAllowedCallback();
        (address _allowedCaller, bytes4 _allowedSelector, uint16 _allowedOffset) =
            vault.allowCallbackAndGetAllowedCallback(root, _callbackData);

        assertEq(caller, _allowedCaller, "Callers aren't equal");
        assertEq(selector, _allowedSelector, "Selectors aren't equal");
        assertEq(offset, _allowedOffset, "Offsets aren't equal");
    }

    ////////////////////////////////////////////////////////////
    //                   callbackApprovals                    //
    ////////////////////////////////////////////////////////////

    function test_callbackApprovals_success() external {
        uint256 arrayLength = 50;

        address[] memory spenders = new address[](arrayLength);
        address[] memory tokens = new address[](arrayLength);

        for (uint256 i; i < arrayLength; ++i) {
            spenders[i] = address(uint160(i * 2));
            tokens[i] = address(uint160(i * 3));
        }

        Approval[] memory approvals = new Approval[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            approvals[i] = Approval({ token: tokens[i], spender: spenders[i] });
        }

        /* Note: in `forge test --isolate`, calling storeCallbackApprovals() and getCallbackApprovals()
        *  separately causes the transient slot to be empty because `--isolate` runs the test
        *  on a clean EVM state for each external call. This is a workaround to test saving and fetching the slot
        *  closely to how it would be done in production, which is actually in the same `submit` call.
        */
        Approval[] memory savedApprovals = vault.storeAndFetchCallbackApprovals(approvals, approvals.length);
        vm.snapshotGasLastCall("callbackApprovals - success");

        assertEq(savedApprovals.length, approvals.length, "Approvals' lengths aren't equal");
        for (uint256 i = 0; i < savedApprovals.length; i++) {
            assertEq(approvals[i].token, savedApprovals[i].token, "Tokens aren't equal");
            assertEq(approvals[i].spender, savedApprovals[i].spender, "Spenders aren't equal");
        }
    }

    function test_fuzz_callbackApprovals_success_noExisting(Approval[] memory approvals, uint256 seed) external {
        vm.assume(seed != 0);
        uint256 length = approvals.length % seed;

        /* Note: in `forge test --isolate`, calling storeCallbackApprovals() and getCallbackApprovals()
        *  separately causes the transient slot to be empty because `--isolate` runs the test
        *  on a clean EVM state for each external call. This is a workaround to test saving and fetching the slot
        *  closely to how it would be done in production, which is actually in the same `submit` call.
        */
        Approval[] memory savedApprovals = vault.storeAndFetchCallbackApprovals(approvals, length);

        assertEq(savedApprovals.length, length, "Approvals' lengths aren't equal");
        for (uint256 i = 0; i < length; i++) {
            assertEq(approvals[i].token, savedApprovals[i].token, "Tokens aren't equal");
            assertEq(approvals[i].spender, savedApprovals[i].spender, "Spenders aren't equal");
        }
    }

    function test_fuzz_callbackApprovals_success_append(
        Approval[] memory approvals1,
        Approval[] memory approvals2,
        uint256 seed
    ) external {
        vm.assume(seed != 0);
        uint256 length1 = approvals1.length % seed;
        uint256 length2 = approvals2.length % seed;

        Approval[] memory savedApprovals =
            vault.storeTwiceAndFetchCallbackApprovals(approvals1, length1, approvals2, length2);

        assertEq(savedApprovals.length, length1 + length2, "Approvals' lengths aren't equal");
        for (uint256 i = 0; i < length1; i++) {
            assertEq(approvals1[i].token, savedApprovals[i].token, "Tokens aren't equal");
            assertEq(approvals1[i].spender, savedApprovals[i].spender, "Spenders aren't equal");
        }
        for (uint256 i = 0; i < length2; i++) {
            assertEq(approvals2[i].token, savedApprovals[i + length1].token, "Tokens aren't equal");
            assertEq(approvals2[i].spender, savedApprovals[i + length1].spender, "Spenders aren't equal");
        }
    }

    ////////////////////////////////////////////////////////////
    //                     handleCallback                     //
    ////////////////////////////////////////////////////////////

    function test_handleCallbackOperations_revertsWith_UnauthorizedCallback_badSelector() external {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = tokenA;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 40e18;

        Operation[] memory subOperations = new Operation[](1);
        subOperations[0] = Operation({
            target: address(tokenA),
            data: abi.encodeCall(IERC20.approve, (address(flashloanProvider), amounts[0])),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedSubops = Encoder.encodeOperations(subOperations);

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(flashloanProvider),
            data: abi.encodeCall(MockFlashLoanProvider.makeFlashLoan, (tokens, amounts, encodedSubops)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashloanProvider),
                selector: bytes4(0),
                calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 6),
            hooks: address(0),
            value: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseVault.Aera__SubmissionFailed.selector,
                0,
                abi.encodeWithSelector(ICallbackHandler.Aera__UnauthorizedCallback.selector)
            )
        );
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));
    }

    function test_handleCallbackOperations_revertsWith_UnauthorizedCallback_badCaller() external {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = tokenA;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 40e18;

        Operation[] memory subOperations = new Operation[](1);
        subOperations[0] = Operation({
            target: address(tokenA),
            data: abi.encodeCall(IERC20.approve, (address(flashloanProvider), amounts[0])),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedSubops = Encoder.encodeOperations(subOperations);

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(flashloanProvider),
            data: abi.encodeCall(MockFlashLoanProvider.makeFlashLoan, (tokens, amounts, encodedSubops)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(0xabcd),
                selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 5),
            hooks: address(0),
            value: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseVault.Aera__SubmissionFailed.selector,
                0,
                abi.encodeWithSelector(ICallbackHandler.Aera__UnauthorizedCallback.selector)
            )
        );
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));
    }

    function test_handleCallbackOperations_revertsWith_BadInOffset() external {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = tokenA;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 40e18;

        Operation[] memory subOperations = new Operation[](1);
        subOperations[0] = Operation({
            target: address(tokenA),
            data: abi.encodeCall(IERC20.approve, (address(flashloanProvider), amounts[0])),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedSubops = Encoder.encodeOperations(subOperations);

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(flashloanProvider),
            data: abi.encodeCall(MockFlashLoanProvider.makeFlashLoan, (tokens, amounts, encodedSubops)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashloanProvider),
                selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length) + 1
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        vm.expectRevert();
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));
    }

    function test_handleCallbackOperations_callback_empty() external {
        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(flashloanProvider),
            data: abi.encodeCall(MockFlashLoanProvider.emptyCallback, ()),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashloanProvider),
                selector: IFlashLoanRecipient.emptyCallback.selector,
                calldataOffset: NO_CALLBACK_DATA
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("handleCallback - success - empty");
    }

    function test_handleCallbackOperations_success() external {
        IERC20[] memory tokens = new IERC20[](3);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 40e18;
        amounts[1] = 25e18;
        amounts[2] = 5e18;
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        tokens[2] = tokenC;

        Operation[] memory subOperations = new Operation[](3);
        subOperations[0].target = address(tokenA);
        subOperations[0].data = abi.encodeCall(IERC20.approve, (address(flashloanProvider), amounts[0]));
        subOperations[0].proof = MerkleHelper.getProof(leaves, 0);
        subOperations[1].target = address(tokenB);
        subOperations[1].data = abi.encodeCall(IERC20.approve, (address(flashloanProvider), amounts[1]));
        subOperations[1].proof = MerkleHelper.getProof(leaves, 1);
        subOperations[2].target = address(tokenC);
        subOperations[2].data = abi.encodeCall(IERC20.approve, (address(flashloanProvider), amounts[2]));
        subOperations[2].proof = MerkleHelper.getProof(leaves, 4);
        bytes memory encodedSubops =
            Encoder.encodeCallbackOperations(subOperations, ReturnValueType.NO_RETURN, new bytes(0));

        Operation[] memory operations = new Operation[](1);
        operations[0].target = address(flashloanProvider);
        operations[0].data = abi.encodeCall(MockFlashLoanProvider.makeFlashLoan, (tokens, amounts, encodedSubops));
        operations[0].callbackData = CallbackData({
            caller: address(flashloanProvider),
            selector: IFlashLoanRecipient.receiveFlashLoan.selector,
            calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length)
        });
        operations[0].proof = MerkleHelper.getProof(leaves, 7);

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("handleCallback - success - flashloan");
    }

    ////////////////////////////////////////////////////////////
    //                 storeCallbackApprovals                 //
    ////////////////////////////////////////////////////////////

    function test_storeCallbackApprovals_success() external {
        Approval[] memory approvals = new Approval[](5);
        approvals[0] = Approval({ token: address(tokenA), spender: address(flashloanProvider) });

        Approval[] memory fetchedApprovals = vault.storeAndFetchCallbackApprovals(approvals, 1);
        vm.snapshotGasLastCall("storeCallbackApprovals - success");

        assertEq(fetchedApprovals.length, 1, "Approvals' lengths aren't equal");
        assertEq(fetchedApprovals[0].token, address(tokenA), "Tokens aren't equal");
        assertEq(fetchedApprovals[0].spender, address(flashloanProvider), "Spenders aren't equal");
    }

    function _calculateFlashLoanOffset(uint256 tokensLength, uint256 amountsLength)
        internal
        pure
        returns (uint16 offset)
    {
        offset = uint16(
            4 // selector
                + (3 * 32) // dynamic array pointers
                + 32 + (tokensLength * 32) // tokens array
                + 32 + (amountsLength * 32) // amounts array
                + 32 // encoded operations pointer
        );
    }
}
