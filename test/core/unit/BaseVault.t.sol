// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Address } from "@oz/utils/Address.sol";
import { Pausable } from "@oz/utils/Pausable.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { NO_CALLBACK_DATA, SELECTOR_SIZE, WORD_SIZE } from "src/core/Constants.sol";
import {
    BaseVaultParameters, CallbackData, Clipboard, HookCallType, Operation, ReturnValueType
} from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";

import { BaseVault } from "src/core/BaseVault.sol";
import { IAuth2Step } from "src/core/interfaces/IAuth2Step.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { IERC20WithAllowance } from "src/dependencies/openzeppelin/token/ERC20/IERC20WithAllowance.sol";
import { ERC20WithAllowanceMock } from "test/core/mocks/ERC20WithAllowanceMock.sol";
import { ERC721Mock } from "test/core/mocks/ERC721Mock.sol";

import { ICallbackRecipient } from "test/core/mocks/ICallbackRecipient.sol";
import { IFlashLoanRecipient } from "test/core/mocks/IFlashLoanRecipient.sol";

import { MockBaseVault } from "test/core/mocks/MockBaseVault.sol";
import { MockBaseVaultFactory } from "test/core/mocks/MockBaseVaultFactory.sol";
import { MockCallbackProvider } from "test/core/mocks/MockCallbackProvider.sol";
import { MockDynamicReturnValueReturner } from "test/core/mocks/MockDynamicReturnValueReturner.sol";
import { MockFlashLoanProvider } from "test/core/mocks/MockFlashLoanProvider.sol";
import { Encoder } from "test/core/utils/Encoder.sol";
import { LibPRNG } from "test/core/utils/LibPRNG.sol";
import { BaseMerkleTree } from "test/utils/BaseMerkleTree.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract BaseVaultTest is BaseTest, BaseMerkleTree, MockBaseVaultFactory {
    using LibPRNG for LibPRNG.PRNG;

    BaseVault internal baseVault;
    ERC20Mock internal token1;
    ERC20Mock internal token2;
    ERC20WithAllowanceMock internal tokenWithAllowance;
    MockFlashLoanProvider internal flashLoanProvider;
    MockCallbackProvider internal callbackProvider;

    bytes internal transferCalldata;

    address internal immutable TARGET = makeAddr("target");

    function setUp() public override {
        super.setUp();

        transferCalldata = abi.encodeWithSelector(IERC20.transfer.selector, users.alice, ONE);

        token1 = new ERC20Mock();
        token2 = new ERC20Mock();
        tokenWithAllowance = new ERC20WithAllowanceMock("Token With Allowance", "TWA");

        callbackProvider = new MockCallbackProvider();
        flashLoanProvider = new MockFlashLoanProvider();
        token1.mint(address(flashLoanProvider), 10_000e18);
        token2.mint(address(flashLoanProvider), 10_000e18);

        // populate with 2 leaves and deploy to avoid reverts and code duplication
        leaves.push(_getSimpleLeaf(address(token1), IERC20.transfer.selector));
        leaves.push(_getSimpleLeaf(address(token2), IERC20.transfer.selector));

        setGuardian(users.guardian);

        setBaseVaultParameters(
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            })
        );
        deployCodeTo("BaseVault.sol", "", BASE_VAULT);
        baseVault = BaseVault(BASE_VAULT);
        vm.prank(users.owner);
        baseVault.acceptOwnership();
        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));
    }

    ////////////////////////////////////////////////////////////
    //                       deployment                       //
    ////////////////////////////////////////////////////////////
    function test_deployment_success() public {
        setBaseVaultParameters(
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0xabcd)),
                submitHooks: ISubmitHooks(address(0xabcd)),
                whitelist: IWhitelist(WHITELIST)
            })
        );

        vm.expectEmit(true, true, false, true);
        emit IAuth2Step.OwnershipTransferStarted(address(this), users.owner);
        vm.expectEmit(true, true, false, true);
        emit Auth.AuthorityUpdated(address(this), Authority(address(0xabcd)));
        vm.expectEmit(true, false, false, true);
        emit IBaseVault.SubmitHooksSet(address(0xabcd));
        BaseVault newBaseVault = new BaseVault();

        assertEq(newBaseVault.pendingOwner(), users.owner);
        assertEq(address(newBaseVault.submitHooks()), address(0xabcd));
        assertEq(address(newBaseVault.authority()), address(0xabcd));
        assertEq(address(newBaseVault.owner()), address(this));
    }

    ////////////////////////////////////////////////////////////
    //                        receive                         //
    ////////////////////////////////////////////////////////////

    function test_receive_success() public {
        uint256 _msgValue = 1 ether;
        deal(users.guardian, _msgValue);

        assertEq(address(baseVault).balance, 0);

        vm.prank(users.guardian);
        Address.sendValue(payable(address(baseVault)), _msgValue);

        assertEq(address(baseVault).balance, _msgValue);
    }

    ////////////////////////////////////////////////////////////
    //                    setGuardianRoot                     //
    ////////////////////////////////////////////////////////////

    function test_setGuardianRoot_success() public {
        address newGuardian = address(0x1234);

        vm.mockCall(
            address(WHITELIST), abi.encodeWithSelector(IWhitelist.isWhitelisted.selector, newGuardian), abi.encode(true)
        );

        vm.prank(users.owner);
        vm.expectEmit(false, false, false, true, address(baseVault));
        emit IBaseVault.GuardianRootSet(newGuardian, RANDOM_BYTES32);
        baseVault.setGuardianRoot(newGuardian, RANDOM_BYTES32);

        assertEq(baseVault.getGuardianRoot(newGuardian), RANDOM_BYTES32);
        vm.snapshotGasLastCall("setGuardianRoot - success");
    }

    function test_setGuardianRoot_revertsWith_unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        baseVault.setGuardianRoot(address(0), RANDOM_BYTES32);
    }

    function test_setGuardianRoot_revertsWith_ZeroAddressGuardian() public {
        vm.prank(users.owner);
        vm.expectRevert(IBaseVault.Aera__ZeroAddressGuardian.selector);
        baseVault.setGuardianRoot(address(0), RANDOM_BYTES32);
    }

    function test_setGuardianRoot_revertsWith_GuardianNotWhitelisted() public {
        address newGuardian = makeAddr("new_guardian");

        vm.mockCall(
            address(WHITELIST),
            abi.encodeWithSelector(IWhitelist.isWhitelisted.selector, newGuardian),
            abi.encode(false)
        );

        vm.prank(users.owner);
        vm.expectRevert(IBaseVault.Aera__GuardianNotWhitelisted.selector);
        baseVault.setGuardianRoot(newGuardian, RANDOM_BYTES32);
    }

    function test_setGuardianRoot_revertsWith_ZeroAddressMerkleRoot() public {
        vm.prank(users.owner);
        vm.expectRevert(IBaseVault.Aera__ZeroAddressMerkleRoot.selector);
        baseVault.setGuardianRoot(users.guardian, bytes32(0));
    }

    ////////////////////////////////////////////////////////////
    //                    removeGuardian                      //
    ////////////////////////////////////////////////////////////

    function test_removeGuardian_success() public {
        address newGuardian = address(0x1234);

        vm.prank(users.owner);
        vm.expectEmit(true, true, false, false);
        emit IBaseVault.GuardianRootSet(newGuardian, bytes32(0));
        baseVault.removeGuardian(newGuardian);

        assertEq(baseVault.getGuardianRoot(newGuardian), bytes32(0));
        vm.snapshotGasLastCall("removeGuardian - success");
    }

    function test_removeGuardian_revertsWith_unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        baseVault.removeGuardian(address(0));
    }

    ////////////////////////////////////////////////////////////
    //                         Pause                          //
    ////////////////////////////////////////////////////////////

    function test_pause_success_owner() public {
        vm.prank(users.owner);
        vm.expectEmit(false, false, false, true, address(baseVault));
        emit Pausable.Paused(users.owner);
        baseVault.pause();
        vm.snapshotGasLastCall("pause - success - owner");
    }

    function test_pause_success_guardian() public {
        vm.prank(users.guardian);
        vm.expectEmit(false, false, false, true, address(baseVault));
        emit Pausable.Paused(users.guardian);
        baseVault.pause();
        vm.snapshotGasLastCall("pause - success - guardian");
    }

    function test_pause_revertsWith_CallerIsNotAuthOrGuardian() public {
        vm.expectRevert(IBaseVault.Aera__CallerIsNotAuthOrGuardian.selector);
        baseVault.pause();
    }

    ////////////////////////////////////////////////////////////
    //                        Unpause                         //
    ////////////////////////////////////////////////////////////

    function test_unpause_success_owner() public {
        vm.prank(users.owner);
        baseVault.pause();

        vm.prank(users.owner);
        vm.expectEmit(false, false, false, true, address(baseVault));
        emit Pausable.Unpaused(users.owner);
        baseVault.unpause();
        vm.snapshotGasLastCall("unpause - success - owner");
    }

    function test_unpause_revertsWith_unauthorized() public {
        vm.prank(users.owner);
        baseVault.pause();

        vm.expectRevert("UNAUTHORIZED");
        baseVault.unpause();
    }

    ////////////////////////////////////////////////////////////
    //                   getActiveGuardians                   //
    ////////////////////////////////////////////////////////////

    function test_getActiveGuardians_success() public {
        address[] memory expectedGuardians = new address[](2);
        expectedGuardians[0] = users.guardian;
        expectedGuardians[1] = users.alice;

        // Set the guardian as whitelisted
        vm.startPrank(users.owner);
        for (uint256 i = 0; i < expectedGuardians.length; i++) {
            address newGuardian = expectedGuardians[i];
            vm.mockCall(
                address(WHITELIST),
                abi.encodeWithSelector(IWhitelist.isWhitelisted.selector, newGuardian),
                abi.encode(true)
            );
            baseVault.setGuardianRoot(newGuardian, RANDOM_BYTES32);
        }
        vm.stopPrank();

        // Get the active guardians
        address[] memory activeGuardians = baseVault.getActiveGuardians();
        assertEq(activeGuardians.length, expectedGuardians.length, "The number of active guardians should be correct");
        for (uint256 i = 0; i < expectedGuardians.length; i++) {
            assertEq(activeGuardians[i], expectedGuardians[i], "The active guardian should be the correct address");
        }
    }

    ////////////////////////////////////////////////////////////
    //                    getGuardianRoot                     //
    ////////////////////////////////////////////////////////////

    function test_getGuardianRoot_success() public {
        // Set the guardian as whitelisted
        vm.startPrank(users.owner);
        vm.mockCall(
            address(WHITELIST),
            abi.encodeWithSelector(IWhitelist.isWhitelisted.selector, users.guardian),
            abi.encode(true)
        );
        baseVault.setGuardianRoot(users.guardian, RANDOM_BYTES32);
        vm.stopPrank();

        // Get the guardian root
        bytes32 guardianRoot = baseVault.getGuardianRoot(users.guardian);
        assertEq(guardianRoot, RANDOM_BYTES32, "The guardian root should be correct");
    }

    ////////////////////////////////////////////////////////////
    //                         Submit                         //
    ////////////////////////////////////////////////////////////

    function test_fuzz_submit_success(bytes4 selector, bytes memory data) public {
        vm.assume(!_isAllowanceSelector(selector));

        leaves.push(_getSimpleLeaf(TARGET, selector));

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        bytes memory dataWithSelector = abi.encodeWithSelector(selector, data);
        vm.mockCall(TARGET, dataWithSelector, hex"c0de");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TARGET,
            data: dataWithSelector,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - guardian with no return");
    }

    function test_fuzz_submit_success_withPipe(bytes4 selector1, bytes4 selector2, bytes32 response, bytes memory data)
        public
    {
        vm.assume(!_isAllowanceSelector(selector1));
        vm.assume(!_isAllowanceSelector(selector2));
        vm.assume(selector1 != selector2);

        leaves.push(_getSimpleLeaf(TARGET, selector1));
        leaves.push(_getSimpleLeaf(TARGET, selector2));

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        bytes memory dataWithSelector1 = abi.encodeWithSelector(selector1, data);
        vm.mockCall(TARGET, dataWithSelector1, abi.encode(response));
        vm.mockCall(TARGET, abi.encodeWithSelector(selector2, response), hex"c0de");

        Operation[] memory operations = new Operation[](2);
        operations[0] = Operation({
            target: TARGET,
            data: dataWithSelector1,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });
        operations[1] = Operation({
            target: TARGET,
            data: abi.encodeWithSelector(selector2, bytes32(0)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - with pipe");
    }

    function test_fuzz_submit_success_withStaticCall(
        bytes4 selector1,
        bytes4 selector2,
        bytes32 response,
        bytes memory data
    ) public {
        vm.assume(!_isAllowanceSelector(selector1));
        vm.assume(!_isAllowanceSelector(selector2));
        vm.assume(selector1 != selector2);

        leaves.push(_getSimpleLeaf(TARGET, selector2));

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        bytes memory dataWithSelector1 = abi.encodeWithSelector(selector1, data);
        vm.mockCall(TARGET, dataWithSelector1, abi.encode(response));
        vm.mockCall(TARGET, abi.encodeWithSelector(selector2, response), hex"c0de");

        Operation[] memory operations = new Operation[](2);
        operations[0] = Operation({
            target: TARGET,
            data: dataWithSelector1,
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });
        operations[1] = Operation({
            target: TARGET,
            data: abi.encodeWithSelector(selector2, bytes32(0)),
            clipboards: Encoder.makeClipboardArray(0, 0, 0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - with static call");
    }

    function test_fuzz_submit_revertsWith_SubmissionFailed(bytes4 selector, bytes memory data) public {
        leaves.push(_getSimpleLeaf(TARGET, selector));

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        bytes memory dataWithSelector = abi.encodeWithSelector(selector, data);
        vm.mockCallRevert(TARGET, dataWithSelector, hex"c0de");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TARGET,
            data: dataWithSelector,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);

        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__SubmissionFailed.selector, 0, hex"c0de"));
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_fuzz_submit_staticCall_revertsWith_SubmissionFailed(bytes4 selector, bytes memory data) public {
        bytes memory dataWithSelector = abi.encodeWithSelector(selector, data);
        vm.mockCallRevert(TARGET, dataWithSelector, hex"c0de");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TARGET,
            data: dataWithSelector,
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);

        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__SubmissionFailed.selector, 0, hex"c0de"));
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_revertsWith_CallerIsNotGuardian() public {
        vm.mockCall(users.guardian, abi.encode("c0de"), hex"c0de");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: users.guardian,
            data: hex"c0de",
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        vm.expectRevert(IBaseVault.Aera__CallerIsNotGuardian.selector);
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_revertsWith_AllowanceIsNotZero_Approve() public {
        leaves.push(_getSimpleLeaf(address(token1), IERC20.approve.selector));

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        bytes memory dataWithSelector = abi.encodeWithSelector(IERC20.approve.selector, users.alice, ONE);

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(token1),
            data: dataWithSelector,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);

        vm.expectRevert(
            abi.encodeWithSelector(IBaseVault.Aera__AllowanceIsNotZero.selector, address(token1), users.alice)
        );
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_revertsWith_AllowanceIsNotZero_IncreaseAllowance() public {
        leaves.push(_getSimpleLeaf(address(tokenWithAllowance), IERC20WithAllowance.increaseAllowance.selector));

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(tokenWithAllowance),
            data: abi.encodeWithSelector(IERC20WithAllowance.increaseAllowance.selector, users.alice, ONE),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseVault.Aera__AllowanceIsNotZero.selector, address(tokenWithAllowance), users.alice
            )
        );
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_revertsWith_ExpectedCallbackNotReceived() public {
        leaves.push(_getSimpleLeaf(address(token1), IERC20.approve.selector));
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashLoanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashLoanProvider),
                    selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                    calldataOffset: _calculateFlashLoanOffset(1, 1)
                }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        // Set up tokens and amounts for flash loan
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        // Create operation that expects a callback but won't receive one
        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(flashLoanProvider),
            data: abi.encodeWithSelector(MockFlashLoanProvider.makeFlashLoan.selector, tokens, amounts, new bytes(0)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashLoanProvider),
                selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        // Mock the flash loan provider to NOT make the callback
        vm.mockCall(
            address(flashLoanProvider),
            abi.encodeWithSelector(MockFlashLoanProvider.makeFlashLoan.selector, tokens, amounts, new bytes(0)),
            abi.encode()
        );

        // The transaction should revert with Aera__ExpectedCallbackNotReceived
        vm.prank(users.guardian);
        vm.expectRevert(IBaseVault.Aera__ExpectedCallbackNotReceived.selector);
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_callback_noPipe() public {
        leaves.push(_getSimpleLeaf(address(token1), IERC20.approve.selector));
        leaves.push(_getSimpleLeaf(address(token2), IERC20.approve.selector));
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashLoanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashLoanProvider),
                    selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                    calldataOffset: _calculateFlashLoanOffset(2, 2)
                }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        // Set up tokens and amounts for flash loan
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 2e18;

        // Create approval operations for the callback
        Operation[] memory callbackOps = new Operation[](2);
        callbackOps[0] = Operation({
            target: address(tokens[0]),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(flashLoanProvider), amounts[0]),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });
        callbackOps[1] = Operation({
            target: address(tokens[1]),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(flashLoanProvider), amounts[1]),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedCallbackOps =
            Encoder.encodeCallbackOperations(callbackOps, ReturnValueType.NO_RETURN, new bytes(0));

        // Create main operation that triggers flash loan
        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(flashLoanProvider),
            data: abi.encodeWithSelector(MockFlashLoanProvider.makeFlashLoan.selector, tokens, amounts, encodedCallbackOps),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashLoanProvider),
                selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });

        // Execute the flash loan with callback
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - with flash loan callback, no pipe");
    }

    function test_submit_callback_withPipeAndStaticCall() public {
        leaves.push(_getSimpleLeaf(address(token1), IERC20.approve.selector));
        leaves.push(_getSimpleLeaf(address(token2), IERC20.approve.selector));
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashLoanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashLoanProvider),
                    selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                    calldataOffset: _calculateFlashLoanOffset(2, 2)
                }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        // Set up tokens and amounts for flash loan
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 2e18;

        // Create approval operations for the callback with piping and staticcall
        Operation[] memory callbackOps = new Operation[](3);

        // First operation: balanceOf staticcall that we'll pipe from
        callbackOps[0] = Operation({
            target: address(tokens[0]),
            data: abi.encodeWithSelector(IERC20.balanceOf.selector, address(baseVault)),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        // Approval operations that use piped data
        callbackOps[1] = Operation({
            target: address(tokens[0]),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(flashLoanProvider), 0),
            clipboards: Encoder.makeClipboardArray(0, 0, 1 * 32),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        callbackOps[2] = Operation({
            target: address(tokens[1]),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(flashLoanProvider), amounts[1]),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        bytes memory encodedCallbackOps =
            Encoder.encodeCallbackOperations(callbackOps, ReturnValueType.NO_RETURN, new bytes(0));

        // Create main operation that triggers flash loan
        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(flashLoanProvider),
            data: abi.encodeWithSelector(MockFlashLoanProvider.makeFlashLoan.selector, tokens, amounts, encodedCallbackOps),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashLoanProvider),
                selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });

        // Execute the flash loan with callback
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - with flash loan callback, with pipe and staticcall");
    }

    function test_submit_callback_withParentClipboard() public {
        leaves.push(_getSimpleLeaf(address(token1), IERC20.approve.selector));
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashLoanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashLoanProvider),
                    selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                    calldataOffset: _calculateFlashLoanOffset(1, 1)
                }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = tokens[0].balanceOf(address(flashLoanProvider));

        // First operation: balanceOf call that we'll pipe from
        Operation[] memory operations = new Operation[](2);
        operations[0] = Operation({
            target: address(tokens[0]),
            data: abi.encodeWithSelector(IERC20.balanceOf.selector, address(flashLoanProvider)),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        // Create callback operations that will use the parent clipboard
        Operation[] memory callbackOps = new Operation[](1);
        callbackOps[0] = Operation({
            target: address(tokens[0]),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(flashLoanProvider), 0),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        bytes memory encodedCallbackOps =
            Encoder.encodeCallbackOperations(callbackOps, ReturnValueType.NO_RETURN, new bytes(0));

        // Second operation: flash loan that uses the callback operations
        operations[1] = Operation({
            target: address(flashLoanProvider),
            data: abi.encodeWithSelector(MockFlashLoanProvider.makeFlashLoan.selector, tokens, amounts, encodedCallbackOps),
            clipboards: Encoder.makeClipboardArray(0, 0, 7 * 32 + Encoder.calculatePasteOffset(encodedCallbackOps, 0, 1)),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashLoanProvider),
                selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - flash loan callback using parent clipboard");
    }

    function test_submit_callback_multipleCallbacks() public {
        leaves.push(_getSimpleLeaf(address(token1), IERC20.approve.selector));
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashLoanProvider),
                selector: MockFlashLoanProvider.makeFlashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashLoanProvider),
                    selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                    calldataOffset: _calculateFlashLoanOffset(1, 1)
                }),
                extractedData: ""
            })
        );
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(flashLoanProvider),
                selector: MockFlashLoanProvider.emptyCallback.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(flashLoanProvider),
                    selector: IFlashLoanRecipient.emptyCallback.selector,
                    calldataOffset: NO_CALLBACK_DATA
                }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = tokens[0].balanceOf(address(flashLoanProvider));

        Operation[] memory callbackOps = new Operation[](1);
        callbackOps[0] = Operation({
            target: address(tokens[0]),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(flashLoanProvider), amounts[0]),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        bytes memory encodedCallbackOps =
            Encoder.encodeCallbackOperations(callbackOps, ReturnValueType.NO_RETURN, new bytes(0));

        // Two callbacks - first empty callback, second flash loan that shouldn't be blocked by first callback
        Operation[] memory operations = new Operation[](2);
        operations[0] = Operation({
            target: address(flashLoanProvider),
            data: abi.encodeWithSelector(MockFlashLoanProvider.emptyCallback.selector),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashLoanProvider),
                selector: IFlashLoanRecipient.emptyCallback.selector,
                calldataOffset: NO_CALLBACK_DATA
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });
        operations[1] = Operation({
            target: address(flashLoanProvider),
            data: abi.encodeWithSelector(MockFlashLoanProvider.makeFlashLoan.selector, tokens, amounts, encodedCallbackOps),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(flashLoanProvider),
                selector: IFlashLoanRecipient.receiveFlashLoan.selector,
                calldataOffset: _calculateFlashLoanOffset(tokens.length, amounts.length)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - multiple callbacks");
    }

    function test_submit_callback_staticReturn_fixedSize() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithStaticFixedReturn.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithStaticFixedReturn.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        uint256 callbackProviderReturnValue = callbackProvider.STATIC_FIXED_RETURN();

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithStaticFixedReturn.selector,
                Encoder.encodeCallbackOperations(
                    new Operation[](0), ReturnValueType.STATIC_RETURN, abi.encode(callbackProviderReturnValue)
                )
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithStaticFixedReturn.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2 * word_size, to skip offset and length
             }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with static fixed return");
    }

    function test_submit_callback_staticReturn_fixedSizeMultipleValues() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithStaticFixedReturnMultipleValues.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithStaticFixedReturnMultipleValues.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        uint256 callbackProviderReturnValue = callbackProvider.STATIC_FIXED_RETURN();

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithStaticFixedReturnMultipleValues.selector,
                Encoder.encodeCallbackOperations(
                    new Operation[](0),
                    ReturnValueType.STATIC_RETURN,
                    abi.encode(callbackProviderReturnValue, bytes32(callbackProviderReturnValue))
                )
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithStaticFixedReturnMultipleValues.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2 * word_size, to skip offset and length
             }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with static fixed return multiple values");
    }

    function test_submit_callback_staticReturn_variableSize() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithStaticVariableReturn.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithStaticVariableReturn.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        bytes memory callbackProviderReturnValue = callbackProvider.STATIC_VARIABLE_RETURN();

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithStaticVariableReturn.selector,
                Encoder.encodeCallbackOperations(
                    new Operation[](0), ReturnValueType.STATIC_RETURN, abi.encode(callbackProviderReturnValue)
                )
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithStaticVariableReturn.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2 * word_size, to skip offset and length
             }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with static variable return");
    }

    function test_submit_callback_staticReturn_mixedValues_fixedFirst() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithStaticReturnMixedValuesFixedFirst.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithStaticReturnMixedValuesFixedFirst.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        uint256 callbackProviderReturnValue1 = callbackProvider.STATIC_FIXED_RETURN();
        bytes memory callbackProviderReturnValue2 = callbackProvider.STATIC_VARIABLE_RETURN();

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithStaticReturnMixedValuesFixedFirst.selector,
                Encoder.encodeCallbackOperations(
                    new Operation[](0),
                    ReturnValueType.STATIC_RETURN,
                    abi.encode(callbackProviderReturnValue1, callbackProviderReturnValue2)
                )
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithStaticReturnMixedValuesFixedFirst.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2 * word_size, to skip offset and length
             }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with static return mixed values (fixed returned first)");
    }

    function test_submit_callback_staticReturn_mixedValues_variableFirst() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithStaticReturnMixedValuesVariableFirst.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithStaticReturnMixedValuesVariableFirst.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        bytes memory callbackProviderReturnValue1 = callbackProvider.STATIC_VARIABLE_RETURN();
        uint256 callbackProviderReturnValue2 = callbackProvider.STATIC_FIXED_RETURN();

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithStaticReturnMixedValuesVariableFirst.selector,
                Encoder.encodeCallbackOperations(
                    new Operation[](0),
                    ReturnValueType.STATIC_RETURN,
                    abi.encode(callbackProviderReturnValue1, callbackProviderReturnValue2)
                )
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithStaticReturnMixedValuesVariableFirst.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2 * word_size, to skip offset and length
             }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with static return mixed values (variable returned first)");
    }

    function test_submit_callback_dynamicReturn_fixedSize() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithDynamicFixedReturn.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithDynamicFixedReturn.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        uint256 RETURN_VALUE = 42;

        Operation[] memory callbackOperations = new Operation[](1);
        callbackOperations[0] = Operation({
            target: address(callbackProvider.dynamicReturnValueReturner()),
            data: abi.encodeWithSelector(MockDynamicReturnValueReturner.getFixedSizeReturnValue.selector, RETURN_VALUE),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithDynamicFixedReturn.selector,
                RETURN_VALUE,
                Encoder.encodeCallbackOperations(callbackOperations, ReturnValueType.DYNAMIC_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithDynamicFixedReturn.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with dynamic fixed return");
    }

    function test_submit_callback_dynamicReturn_fixedSize_multipleValues() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithDynamicFixedReturnMultipleValues.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithDynamicFixedReturnMultipleValues.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        uint256 RETURN_VALUE1 = 42;
        uint256 RETURN_VALUE2 = 43;

        Operation[] memory callbackOperations = new Operation[](1);
        callbackOperations[0] = Operation({
            target: address(callbackProvider.dynamicReturnValueReturner()),
            data: abi.encodeWithSelector(
                MockDynamicReturnValueReturner.getFixedSizeReturnValueMultipleValues.selector, RETURN_VALUE1, RETURN_VALUE2
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithDynamicFixedReturnMultipleValues.selector,
                RETURN_VALUE1,
                RETURN_VALUE2,
                Encoder.encodeCallbackOperations(callbackOperations, ReturnValueType.DYNAMIC_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithDynamicFixedReturnMultipleValues.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with dynamic fixed return multiple values");
    }

    function test_submit_callback_dynamicReturn_variableSize() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithDynamicVariableReturn.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithDynamicVariableReturn.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        bytes memory RETURN_VALUE = abi.encode("dynamic return value");

        Operation[] memory callbackOperations = new Operation[](1);
        callbackOperations[0] = Operation({
            target: address(callbackProvider.dynamicReturnValueReturner()),
            data: abi.encodeWithSelector(MockDynamicReturnValueReturner.getVariableReturnValue.selector, RETURN_VALUE),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithDynamicVariableReturn.selector,
                RETURN_VALUE,
                Encoder.encodeCallbackOperations(callbackOperations, ReturnValueType.DYNAMIC_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithDynamicVariableReturn.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with dynamic variable return");
    }

    function test_submit_callback_noReturn_withOperations() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithNoReturnWithOperations.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithNoReturnWithOperations.selector,
                    calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE) // offset + 2*word_size, skip offset and length
                 }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        Operation[] memory callbackOperations = new Operation[](1);
        callbackOperations[0] = Operation({
            target: address(token1),
            data: abi.encodeWithSelector(IERC20.balanceOf.selector, address(baseVault)),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithNoReturnWithOperations.selector,
                Encoder.encodeCallbackOperations(callbackOperations, ReturnValueType.NO_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithNoReturnWithOperations.selector,
                calldataOffset: uint16(SELECTOR_SIZE + 2 * WORD_SIZE)
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with no return and with operations");
    }

    function test_submit_callback_noReturn_withoutOperations() public {
        leaves.push(
            MerkleHelper.getLeaf({
                target: address(callbackProvider),
                selector: MockCallbackProvider.triggerCallbackWithNoReturnWithoutOperations.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: address(callbackProvider),
                    selector: ICallbackRecipient.callbackWithNoReturnWithoutOperations.selector,
                    calldataOffset: NO_CALLBACK_DATA
                }),
                extractedData: ""
            })
        );

        vm.prank(users.owner);
        baseVault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: address(callbackProvider),
            data: abi.encodeWithSelector(
                MockCallbackProvider.triggerCallbackWithNoReturnWithoutOperations.selector,
                Encoder.encodeCallbackOperations(new Operation[](0), ReturnValueType.NO_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: address(callbackProvider),
                selector: ICallbackRecipient.callbackWithNoReturnWithoutOperations.selector,
                calldataOffset: NO_CALLBACK_DATA
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // Execute the operations
        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - callback with no return and without operations");
    }

    ////////////////////////////////////////////////////////////
    //                       submitHooks                      //
    ////////////////////////////////////////////////////////////

    function test_setSubmitHooks_success() public {
        address newSubmitHooks = address(0x1234);

        vm.prank(users.owner);
        vm.expectEmit(false, false, false, true, address(baseVault));
        emit IBaseVault.SubmitHooksSet(newSubmitHooks);
        baseVault.setSubmitHooks(ISubmitHooks(newSubmitHooks));

        assertEq(address(baseVault.submitHooks()), newSubmitHooks);
        vm.snapshotGasLastCall("setSubmitHooks - success");
    }

    function test_setSubmitHooks_revertsWith_unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        baseVault.setSubmitHooks(ISubmitHooks(address(0x1234)));
    }

    ////////////////////////////////////////////////////////////
    //                 checkGuardianWhitelist                 //
    ////////////////////////////////////////////////////////////

    function test_checkGuardianWhitelist_success_guardianIsWhitelisted() public {
        bytes32 rootBefore = baseVault.getGuardianRoot(users.guardian);

        vm.prank(users.guardian);
        baseVault.checkGuardianWhitelist(users.guardian);
        vm.snapshotGasLastCall("checkGuardianWhitelist - success - guardian is whitelisted");

        assertEq(baseVault.getGuardianRoot(users.guardian), rootBefore);
    }

    function test_checkGuardianWhitelist_success_guardianIsNotWhitelisted() public {
        vm.mockCall(
            address(baseVault.WHITELIST()),
            abi.encodeWithSelector(IWhitelist.isWhitelisted.selector, users.guardian),
            abi.encode(false)
        );

        vm.prank(users.guardian);

        vm.expectEmit(false, false, false, true, address(baseVault));
        emit IBaseVault.GuardianRootSet(users.guardian, bytes32(0));

        baseVault.checkGuardianWhitelist(users.guardian);
        vm.snapshotGasLastCall("checkGuardianWhitelist - success - guardian is not whitelisted");

        assertEq(baseVault.getGuardianRoot(users.guardian), bytes32(0));
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

    ////////////////////////////////////////////////////////////
    //                    onERC721Received                    //
    ////////////////////////////////////////////////////////////

    function test_onERC721Received_success() public {
        ERC721Mock erc721 = new ERC721Mock("MockERC721", "MCK");
        erc721.mint(users.alice, 1);

        vm.prank(users.alice);
        erc721.safeTransferFrom(users.alice, address(baseVault), 1);
    }

    function _isAllowanceSelector(bytes4 selector) internal pure returns (bool) {
        return selector == IERC20.approve.selector || selector == IERC20WithAllowance.increaseAllowance.selector;
    }

    ////////////////////////////////////////////////////////////
    //                    getHookCallType                    //
    ////////////////////////////////////////////////////////////

    function test_getHookCallType_success() public {
        MockBaseVault mockBaseVault = new MockBaseVault();
        HookCallType hookCallType = mockBaseVault.setAndGetCurrentHookCallType(HookCallType.BEFORE);
        assertEq(uint8(hookCallType), uint8(HookCallType.BEFORE));
    }
}
