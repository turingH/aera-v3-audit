// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Create2 } from "@oz/utils/Create2.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { BaseVault } from "src/core/BaseVault.sol";
import { BaseVaultFactory } from "src/core/BaseVaultFactory.sol";
import { BaseVaultParameters } from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";
import { IBaseVaultDeployer } from "src/core/interfaces/IBaseVaultDeployer.sol";
import { IBaseVaultFactory } from "src/core/interfaces/IBaseVaultFactory.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract BaseVaultFactoryTest is BaseTest {
    BaseVaultFactory internal factory;
    BaseVault internal vault;

    address public expectedVaultAddress;

    function setUp() public override {
        super.setUp();
        factory = new BaseVaultFactory(users.owner, Authority(address(0)));
        expectedVaultAddress =
            Create2.computeAddress(RANDOM_BYTES32, keccak256(type(BaseVault).creationCode), address(factory));

        vm.mockCall(
            WHITELIST, abi.encodeWithSelector(IWhitelist.isWhitelisted.selector, users.guardian), abi.encode(true)
        );
    }
    ////////////////////////////////////////////////////////////
    //                       deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public {
        BaseVaultFactory newFactory = new BaseVaultFactory(users.owner, Authority(address(0xabcd)));
        assertEq(newFactory.owner(), users.owner);
        assertEq(address(newFactory.authority()), address(0xabcd));
    }

    ////////////////////////////////////////////////////////////
    //                         Create                         //
    ////////////////////////////////////////////////////////////

    function test_create_success() public {
        BaseVaultParameters memory baseVaultParameters = BaseVaultParameters({
            owner: users.owner,
            authority: Authority(address(0xabcd)),
            submitHooks: ISubmitHooks(address(0)),
            whitelist: IWhitelist(WHITELIST)
        });

        vm.expectEmit(true, true, true, true);
        emit IBaseVaultFactory.VaultCreated(
            expectedVaultAddress, baseVaultParameters.owner, address(baseVaultParameters.submitHooks), "Test Vault"
        );
        vm.prank(users.owner);
        address deployedVault =
            factory.create(bytes32(RANDOM_BYTES32), "Test Vault", baseVaultParameters, expectedVaultAddress);
        vm.snapshotGasLastCall("create - success");
        vault = BaseVault(payable(deployedVault));

        assertEq(address(vault), expectedVaultAddress);
        assertEq(vault.pendingOwner(), baseVaultParameters.owner);
        assertEq(address(vault.authority()), address(baseVaultParameters.authority));
    }

    function test_create_revertsWith_Unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(users.stranger);
        factory.create(
            bytes32(RANDOM_BYTES32),
            "Test Vault",
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            }),
            expectedVaultAddress
        );
    }

    function test_create_revertsWith_ZeroAddressOwner() public {
        vm.prank(users.owner);
        vm.expectRevert(IBaseVault.Aera__ZeroAddressOwner.selector);
        factory.create(
            bytes32(RANDOM_BYTES32),
            "Test Vault",
            BaseVaultParameters({
                owner: address(0),
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            }),
            expectedVaultAddress
        );
    }

    function test_create_revertsWith_DescriptionIsEmpty() public {
        vm.prank(users.owner);
        vm.expectRevert(IBaseVaultDeployer.Aera__DescriptionIsEmpty.selector);
        factory.create(
            RANDOM_BYTES32,
            "",
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            }),
            expectedVaultAddress
        );
    }

    function test_create_revertsWith_VaultAddressMismatch() public {
        vm.prank(users.owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseVaultDeployer.Aera__VaultAddressMismatch.selector, expectedVaultAddress, address(0)
            )
        );
        factory.create(
            RANDOM_BYTES32,
            "Test Vault",
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            }),
            address(0)
        );
    }

    ////////////////////////////////////////////////////////////
    //                    Vault Parameters                    //
    ////////////////////////////////////////////////////////////

    function test_fuzz_storeBaseVaultParameters_success(BaseVaultParameters calldata params) public {
        BaseVaultFactoryPublic newFactory = new BaseVaultFactoryPublic(users.owner, Authority(address(0)));

        BaseVaultParameters memory storedParams = newFactory.storeAndFetchBaseVaultParameters(params);
        assertEq(storedParams.owner, params.owner);
        assertEq(address(storedParams.submitHooks), address(params.submitHooks));
        assertEq(address(storedParams.whitelist), address(params.whitelist));
    }
}

contract BaseVaultFactoryPublic is BaseVaultFactory {
    constructor(address initialOwner, Authority initialAuthority) BaseVaultFactory(initialOwner, initialAuthority) { }

    // solhint-disable-next-line foundry-test-functions
    function storeAndFetchBaseVaultParameters(BaseVaultParameters calldata params)
        external
        returns (BaseVaultParameters memory)
    {
        _storeBaseVaultParameters(params);
        return this.baseVaultParameters();
    }
}
