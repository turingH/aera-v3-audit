// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { BaseVaultParameters, Clipboard, Operation } from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { BaseVault } from "src/core/BaseVault.sol";
import { MockBaseVaultFactory } from "test/core/mocks/MockBaseVaultFactory.sol";

import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";
import { MockRevertableBeforeAfterHooks } from "test/core/mocks/MockRevertableBeforeAfterHooks.sol";
import { BaseMerkleTree } from "test/utils/BaseMerkleTree.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract SubmitHooksTest is BaseTest, BaseMerkleTree, MockBaseVaultFactory {
    BaseVault internal baseVault;
    MockRevertableBeforeAfterHooks internal beforeAfterHooks;

    address internal constant BEFORE_HOOKS = address(0x01000001);
    address internal constant AFTER_HOOKS = address(0x01000002);
    address internal constant BEFORE_AFTER_HOOKS = address(0x01000003);

    bytes internal transferCalldata;

    function setUp() public override {
        super.setUp();

        transferCalldata = abi.encodeWithSelector(IERC20.transfer.selector, users.alice, ONE);

        leaves.push(
            MerkleHelper.getLeaf({
                target: TOKEN,
                selector: IERC20.transfer.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: ""
            })
        );

        leaves.push(
            MerkleHelper.getLeaf({
                target: TOKEN,
                selector: IERC20.transfer.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(users.alice)
            })
        );

        leaves.push(
            MerkleHelper.getLeaf({
                target: TOKEN,
                selector: IERC20.transfer.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: BEFORE_HOOKS,
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(users.alice)
            })
        );

        leaves.push(
            MerkleHelper.getLeaf({
                target: TOKEN,
                selector: IERC20.transfer.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(AFTER_HOOKS),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: ""
            })
        );

        leaves.push(
            MerkleHelper.getLeaf({
                target: TOKEN,
                selector: IERC20.transfer.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: BEFORE_AFTER_HOOKS,
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(users.alice)
            })
        );

        leaves.push(
            MerkleHelper.getLeaf({
                target: TOKEN,
                selector: IERC20.transfer.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(BEFORE_AFTER_HOOKS),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: ""
            })
        );

        leaves.push(
            MerkleHelper.getLeaf({
                target: TOKEN,
                selector: IERC20.transfer.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
                hooks: AFTER_HOOKS,
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(users.alice)
            })
        );

        leaves.push(
            MerkleHelper.getLeaf({
                target: TOKEN,
                selector: IERC20.transfer.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
                hooks: BEFORE_HOOKS,
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(users.alice)
            })
        );

        root = MerkleHelper.getRoot(leaves);

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
        baseVault.setGuardianRoot(users.guardian, root);

        vm.mockCall(TOKEN, transferCalldata, hex"c0de");

        vm.label(BEFORE_HOOKS, "BEFORE_HOOKS");
        vm.label(AFTER_HOOKS, "AFTER_HOOKS");
        vm.label(BEFORE_AFTER_HOOKS, "BEFORE_AFTER_HOOKS");
    }

    function test_submit_success_noHooks() public {
        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - no hooks");
    }

    function test_submit_success_withConfigurableHooks() public {
        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - configurable hooks");
    }

    function test_submit_success_beforeOperationHooks() public {
        vm.mockCall(BEFORE_HOOKS, transferCalldata, abi.encode(abi.encode(users.alice)));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(BEFORE_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - operation before hooks");
    }

    function test_submit_revertsWith_BeforeOperationHooksFailed() public {
        vm.mockCallRevert(BEFORE_HOOKS, transferCalldata, hex"0bad");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(BEFORE_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__BeforeOperationHooksFailed.selector, 0, hex"0bad"));
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_success_afterOperationHooks() public {
        vm.mockCall(AFTER_HOOKS, transferCalldata, hex"c0de");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(AFTER_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - operation after hook");
    }

    function test_submit_revertsWith_AfterOperationHooksFailed() public {
        vm.mockCallRevert(AFTER_HOOKS, transferCalldata, hex"0bad");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(AFTER_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__AfterOperationHooksFailed.selector, 0, hex"0bad"));
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_beforeAfterHooks_success() public {
        vm.mockCall(BEFORE_AFTER_HOOKS, transferCalldata, abi.encode(abi.encode(users.alice)));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(BEFORE_AFTER_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - operation before and after hook");
    }

    function test_submit_beforeAfterHooks_revertsWith_BeforeAfterOperationHooksFailed() public {
        vm.mockCallRevert(BEFORE_AFTER_HOOKS, transferCalldata, hex"0bad");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(BEFORE_AFTER_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__BeforeOperationHooksFailed.selector, 0, hex"0bad"));
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_beforeAfterHooks_revertsWith_AfterOperationHooksFailed() public {
        deployCodeTo("MockRevertableBeforeAfterHooks.sol", address(BEFORE_AFTER_HOOKS));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 5),
            hooks: address(BEFORE_AFTER_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseVault.Aera__AfterOperationHooksFailed.selector,
                0,
                abi.encodeWithSignature("Error(string)", "REASON")
            )
        );
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_success_configurableAfterOperationHooks() public {
        vm.mockCall(AFTER_HOOKS, transferCalldata, abi.encode(users.alice));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 6),
            hooks: address(AFTER_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        baseVault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("submit - success - operation configurable after hook");
    }

    function test_submit_configurableHooks_revertsWith_AfterOperationHooksFailed() public {
        vm.mockCallRevert(AFTER_HOOKS, transferCalldata, hex"0bad");

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 6),
            hooks: address(AFTER_HOOKS),
            value: 0
        });

        vm.prank(users.guardian);
        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__AfterOperationHooksFailed.selector, 0, hex"0bad"));
        baseVault.submit(Encoder.encodeOperations(operations));
    }

    function test_submit_configurableHooks_revertsWith_BeforeOperationHooksWithConfigurableHooks() public {
        vm.prank(users.guardian);
        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__BeforeOperationHooksWithConfigurableHooks.selector));

        // used raw bytes for this case because Encoder.encodeOperations() reverts on configurable hooks with before
        // operation hooks defined
        baseVault.submit(
            hex"01000000000000000000000000000000000000abcd0044a9059cbb00000000000000000000000000000000000000000000000000000000000012340000000000000000000000000000000000000000000000000de0b6b3a7640000000000810000000000000000000000000000000000000100000103e98d493307bc4eb738488d8a5eea8c96d7fd40986198d55669045fe8ff7a8ef3b32f639c1ee801a2f46ca9e9abdac75a0ea423e4424d3e141f57cb025f5dd3d29118dd514be39d25787b05b798a8035f616f08ca7b9bb1966578b83b56e08fce00"
        );
    }

    function test_submit_success_beforeSubmitHooks() public {
        vm.prank(users.owner);
        baseVault.setSubmitHooks(ISubmitHooks(BEFORE_HOOKS));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedOperations = Encoder.encodeOperations(operations);
        vm.mockCall(
            BEFORE_HOOKS, abi.encodeCall(ISubmitHooks.beforeSubmit, (encodedOperations, users.guardian)), hex"c0de"
        );

        vm.prank(users.guardian);
        baseVault.submit(encodedOperations);
        vm.snapshotGasLastCall("submit - success - before submit hooks");
    }

    function test_submit_revertsWith_BeforeSubmitHooksFailed() public {
        vm.prank(users.owner);
        baseVault.setSubmitHooks(ISubmitHooks(BEFORE_HOOKS));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedOperations = Encoder.encodeOperations(operations);
        vm.mockCallRevert(
            BEFORE_HOOKS, abi.encodeCall(ISubmitHooks.beforeSubmit, (encodedOperations, users.guardian)), hex"0bad"
        );

        vm.prank(users.guardian);
        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__BeforeSubmitHooksFailed.selector, hex"0bad"));
        baseVault.submit(encodedOperations);
    }

    function test_submit_success_afterSubmitHooks() public {
        vm.prank(users.owner);
        baseVault.setSubmitHooks(ISubmitHooks(AFTER_HOOKS));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedOperations = Encoder.encodeOperations(operations);
        vm.mockCall(
            AFTER_HOOKS, abi.encodeCall(ISubmitHooks.afterSubmit, (encodedOperations, users.guardian)), hex"c0de"
        );

        vm.prank(users.guardian);
        baseVault.submit(encodedOperations);
        vm.snapshotGasLastCall("submit - success - after submit hooks");
    }

    function test_submit_revertsWith_AfterSubmitHooksFailed() public {
        vm.prank(users.owner);
        baseVault.setSubmitHooks(ISubmitHooks(AFTER_HOOKS));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedOperations = Encoder.encodeOperations(operations);
        vm.mockCallRevert(
            AFTER_HOOKS, abi.encodeCall(ISubmitHooks.afterSubmit, (encodedOperations, users.guardian)), hex"0bad"
        );

        vm.prank(users.guardian);
        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__AfterSubmitHooksFailed.selector, hex"0bad"));
        baseVault.submit(encodedOperations);
    }

    function test_submit_success_beforeAfterSubmitHooks() public {
        vm.prank(users.owner);
        baseVault.setSubmitHooks(ISubmitHooks(BEFORE_AFTER_HOOKS));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        bytes memory encodedOperations = Encoder.encodeOperations(operations);
        vm.mockCall(
            BEFORE_AFTER_HOOKS,
            abi.encodeCall(ISubmitHooks.beforeSubmit, (encodedOperations, users.guardian)),
            hex"c0de"
        );
        vm.mockCall(
            BEFORE_AFTER_HOOKS, abi.encodeCall(ISubmitHooks.afterSubmit, (encodedOperations, users.guardian)), hex"c0de"
        );

        vm.prank(users.guardian);
        baseVault.submit(encodedOperations);
        vm.snapshotGasLastCall("submit - success - before and after submit hooks");
    }

    function test_submit_beforeAfterSubmitHooks_revertsWith_AfterSubmitHooksFailed() public {
        vm.prank(users.owner);
        baseVault.setSubmitHooks(ISubmitHooks(BEFORE_AFTER_HOOKS));

        Operation[] memory operations = new Operation[](1);
        operations[0] = Operation({
            target: TOKEN,
            data: transferCalldata,
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });

        bytes memory encodedOperations = Encoder.encodeOperations(operations);

        vm.mockCall(
            BEFORE_AFTER_HOOKS,
            abi.encodeCall(ISubmitHooks.beforeSubmit, (encodedOperations, users.guardian)),
            hex"c0de"
        );
        vm.mockCallRevert(
            BEFORE_AFTER_HOOKS, abi.encodeCall(ISubmitHooks.afterSubmit, (encodedOperations, users.guardian)), hex"0bad"
        );

        vm.prank(users.guardian);
        vm.expectRevert(abi.encodeWithSelector(IBaseVault.Aera__AfterSubmitHooksFailed.selector, hex"0bad"));
        baseVault.submit(encodedOperations);
    }
}
