// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { IERC4626 } from "@oz/interfaces/IERC4626.sol";
import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { ERC4626Mock } from "@oz/mocks/token/ERC4626Mock.sol";
import { MerkleProof } from "@oz/utils/cryptography/MerkleProof.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { BaseVaultParameters, Clipboard, Operation } from "src/core/Types.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { Encoder } from "test/core/utils/Encoder.sol";

import { BaseVault } from "src/core/BaseVault.sol";
import { MockBaseVaultFactory } from "test/core/mocks/MockBaseVaultFactory.sol";
import { LibPRNG } from "test/core/utils/LibPRNG.sol";
import { BaseMerkleTree } from "test/utils/BaseMerkleTree.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract MerkleTreeTest is BaseTest, BaseMerkleTree, MockBaseVaultFactory {
    using LibPRNG for LibPRNG.PRNG;

    ERC20Mock public underlying;
    ERC4626Mock public erc4626;

    uint256 internal constant MAX_LEAVES = 10;

    BaseVault internal vault;

    function setUp() public override {
        super.setUp();

        vault = BaseVault(BASE_VAULT);

        underlying = new ERC20Mock();
        erc4626 = new ERC4626Mock(address(underlying));

        vm.label(address(underlying), "UNDERLYING");
        vm.label(address(erc4626), "ERC4626");
    }

    function test_empty_tree() public pure {
        assertTrue(MerkleProof.verify(new bytes32[](0), bytes32(0), bytes32(0)));
    }

    function test_submit_success_verify_merkleProof_2_leaves() public {
        bytes memory operations = Encoder.encodeOperations(_prepareNLeavesOperations(2));

        vm.prank(users.guardian);
        vault.submit(operations);
        vm.snapshotGasLastCall("verify merkle proof - success - 2 leaf");
    }

    function test_submit_success_verify_merkleProof_64_leaves() public {
        bytes memory operations = Encoder.encodeOperations(_prepareNLeavesOperations(64));

        vm.prank(users.guardian);
        vault.submit(operations);
        vm.snapshotGasLastCall("verify merkle proof - success - 64 leaves");
    }

    function test_submit_success_verify_merkleProof_256_leaves() public {
        bytes memory operations = Encoder.encodeOperations(_prepareNLeavesOperations(256));

        vm.prank(users.guardian);
        vault.submit(operations);
        vm.snapshotGasLastCall("verify merkle proof - success - 256 leaves");
    }

    function test_submit_success_verify_merkleProof_1024_leaves() public {
        bytes memory operations = Encoder.encodeOperations(_prepareNLeavesOperations(1024));

        vm.prank(users.guardian);
        vault.submit(operations);
        vm.snapshotGasLastCall("verify merkle proof - success - 1024 leaves");
    }

    function test_submit_success_verify_merkleProof_16384_leaves() public {
        bytes memory operations = Encoder.encodeOperations(_prepareNLeavesOperations(16_384));

        vm.prank(users.guardian);
        vault.submit(operations);
        vm.snapshotGasLastCall("verify merkle proof - success - 16384 leaves");
    }

    function test_submit_success_erc4626_deposit_withdraw() public {
        bytes32[] memory leaves = new bytes32[](3);

        // 1. ERC20 approve leaf
        leaves[0] = MerkleHelper.getLeaf({
            target: address(underlying),
            selector: IERC20.approve.selector,
            hasValue: false,
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            hooks: address(0),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(address(erc4626))
        });

        // 2. ERC4626 deposit leaf
        leaves[1] = MerkleHelper.getLeaf({
            target: address(erc4626),
            selector: IERC4626.deposit.selector,
            hasValue: false,
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32),
            hooks: address(0),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(BASE_VAULT)
        });

        // 3. ERC4626 redeem leaf
        leaves[2] = MerkleHelper.getLeaf({
            target: address(erc4626),
            selector: IERC4626.redeem.selector,
            hasValue: false,
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32, 64),
            hooks: address(0),
            callbackData: Encoder.emptyCallbackData(),
            extractedData: abi.encode(BASE_VAULT, BASE_VAULT)
        });

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

        vm.prank(users.owner);
        vault.acceptOwnership();
        vm.prank(users.owner);
        vault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));

        underlying.mint(BASE_VAULT, 1e18);

        Operation[] memory operations = new Operation[](4);
        operations[0] = Operation({
            target: address(underlying),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(erc4626), 1e18),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });

        operations[1] = Operation({
            target: address(erc4626),
            data: abi.encodeWithSelector(IERC4626.deposit.selector, 1e18, BASE_VAULT),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        operations[2] = Operation({
            target: address(erc4626),
            data: abi.encodeWithSelector(IERC20.balanceOf.selector, BASE_VAULT),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        operations[3] = Operation({
            target: address(erc4626),
            data: abi.encodeWithSelector(IERC4626.redeem.selector, 0, BASE_VAULT, BASE_VAULT),
            clipboards: Encoder.makeClipboardArray(2, 0, 0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32, 64),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));
        vm.snapshotGasLastCall("verify merkle proof - success - erc4626 deposit with Merkle root redeem merkle proof");
    }

    function _prepareNLeavesOperations(uint256 numLeaves) internal returns (Operation[] memory operations) {
        bytes32[] memory _leaves = new bytes32[](numLeaves);
        // last leaf is the one that will be verified
        // fill the rest with 0
        for (uint256 i = 0; i < numLeaves - 1; ++i) {
            _leaves[i] = bytes32(0);
        }
        address target = address(0xabcd);
        bytes4 selector = IERC20.transfer.selector;

        vm.mockCall(target, abi.encodeWithSelector(selector), abi.encode(true));
        _leaves[numLeaves - 1] = _getSimpleLeaf(target, selector);

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

        vm.prank(users.owner);
        vault.acceptOwnership();
        vm.prank(users.owner);
        vault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(_leaves));

        bytes32[] memory proof = MerkleHelper.getProof(_leaves, numLeaves - 1);

        operations = new Operation[](1);
        operations[0] = Operation({
            target: target,
            data: abi.encodePacked(selector),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: proof,
            hooks: address(0),
            value: 0
        });
    }
}
