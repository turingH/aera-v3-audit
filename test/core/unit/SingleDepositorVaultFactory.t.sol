// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { Authority } from "@solmate/auth/Auth.sol";

import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { SingleDepositorVaultDeployDelegate } from "src/core/SingleDepositorVaultDeployDelegate.sol";
import { SingleDepositorVaultFactory } from "src/core/SingleDepositorVaultFactory.sol";
import { BaseVaultParameters, FeeVaultParameters } from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";
import { IBaseVaultDeployer } from "src/core/interfaces/IBaseVaultDeployer.sol";
import { ISingleDepositorVaultFactory } from "src/core/interfaces/ISingleDepositorVaultFactory.sol";

import { Create2 } from "@oz/utils/Create2.sol";
import { TestBaseSingleDepositorVault } from "test/core/utils/TestBaseSingleDepositorVault.sol";

contract SingleDepositorVaultFactoryTest is TestBaseSingleDepositorVault {
    ////////////////////////////////////////////////////////////
    //                       Deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public {
        address deployDelegate = address(new SingleDepositorVaultDeployDelegate());
        SingleDepositorVaultFactory factory =
            new SingleDepositorVaultFactory(users.owner, Authority(address(0xabcd)), deployDelegate);
        assertEq(factory.owner(), users.owner);
        assertEq(address(factory.authority()), address(0xabcd));
    }

    function test_deployment_revertsWith_ZeroAddressDeployDelegate() public {
        vm.expectRevert(ISingleDepositorVaultFactory.Aera__ZeroAddressDeployDelegate.selector);
        new SingleDepositorVaultFactory(users.owner, Authority(address(0xabcd)), address(0));
    }

    ////////////////////////////////////////////////////////////
    //                         Create                         //
    ////////////////////////////////////////////////////////////

    function test_create_revertsWith_Unauthorized() public {
        address expectedVaultAddress_ =
            Create2.computeAddress(bytes32(ONE), keccak256(type(SingleDepositorVault).creationCode), address(factory));

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(users.stranger);
        _deployAeraV3Contracts(bytes32(vm.randomUint()), expectedVaultAddress_);
    }

    function test_create_revertsWith_ZeroAddressOwner() public {
        baseVaultParameters.owner = address(0);
        address expectedVaultAddress_ =
            Create2.computeAddress(bytes32(ONE), keccak256(type(SingleDepositorVault).creationCode), address(factory));

        vm.prank(FACTORY_OWNER);
        vm.expectRevert(IBaseVault.Aera__ZeroAddressOwner.selector);
        _deployAeraV3Contracts(bytes32(ONE), expectedVaultAddress_);
    }

    function test_create_revertsWith_DescriptionIsEmpty() public {
        vm.prank(FACTORY_OWNER);
        vm.expectRevert(IBaseVaultDeployer.Aera__DescriptionIsEmpty.selector);
        factory.create(bytes32(ONE), "", baseVaultParameters, feeVaultParameters, address(0));
    }

    function test_create_success() public {
        address expectedVaultAddress_ =
            Create2.computeAddress(bytes32(ONE), keccak256(type(SingleDepositorVault).creationCode), address(factory));

        vm.expectEmit(false, false, false, true);
        emit ISingleDepositorVaultFactory.VaultCreated(
            expectedVaultAddress_,
            baseVaultParameters.owner,
            address(baseVaultParameters.submitHooks),
            feeVaultParameters.feeToken,
            feeVaultParameters.feeCalculator,
            feeVaultParameters.feeRecipient,
            "Test Vault"
        );
        vm.prank(FACTORY_OWNER);
        address deployedVault =
            factory.create(bytes32(ONE), "Test Vault", baseVaultParameters, feeVaultParameters, expectedVaultAddress_);
        vm.snapshotGasLastCall("create - success");
        vault = SingleDepositorVault(payable(deployedVault));

        assertEq(address(vault), expectedVaultAddress_);
        assertEq(vault.pendingOwner(), baseVaultParameters.owner);
        assertEq(address(vault.authority()), address(baseVaultParameters.authority));
    }

    ////////////////////////////////////////////////////////////
    //                    Vault Parameters                    //
    ////////////////////////////////////////////////////////////

    function test_fuzz_storeBaseVaultParameters_success(BaseVaultParameters calldata params) public {
        address deployDelegate = address(new SingleDepositorVaultDeployDelegate());
        SingleDepositorVaultFactoryPublic newFactory =
            new SingleDepositorVaultFactoryPublic(FACTORY_OWNER, Authority(address(0)), deployDelegate);

        BaseVaultParameters memory storedParams = newFactory.storeAndFetchBaseVaultParameters(params);
        assertEq(storedParams.owner, params.owner);
        assertEq(address(storedParams.submitHooks), address(params.submitHooks));
        assertEq(address(storedParams.whitelist), address(params.whitelist));
    }

    function test_fuzz_storeFeeVaultParameters_success(FeeVaultParameters calldata params) public {
        address deployDelegate = address(new SingleDepositorVaultDeployDelegate());
        SingleDepositorVaultFactoryPublic newFactory =
            new SingleDepositorVaultFactoryPublic(FACTORY_OWNER, Authority(address(0)), deployDelegate);

        FeeVaultParameters memory storedParams = newFactory.storeAndFetchFeeVaultParameters(params);
        assertEq(address(storedParams.feeCalculator), address(params.feeCalculator));
        assertEq(address(storedParams.feeToken), address(params.feeToken));
    }

    function test_fuzz_storeBaseAndSingleDepositorVaultParameters_success(
        BaseVaultParameters calldata baseParams,
        FeeVaultParameters calldata singleDepositorParams
    ) public {
        address deployDelegate = address(new SingleDepositorVaultDeployDelegate());
        SingleDepositorVaultFactoryPublic newFactory =
            new SingleDepositorVaultFactoryPublic(FACTORY_OWNER, Authority(address(0)), deployDelegate);

        BaseVaultParameters memory storedBaseParams = newFactory.storeAndFetchBaseVaultParameters(baseParams);
        assertEq(storedBaseParams.owner, baseParams.owner);
        assertEq(address(storedBaseParams.submitHooks), address(baseParams.submitHooks));
        assertEq(address(storedBaseParams.whitelist), address(baseParams.whitelist));

        FeeVaultParameters memory storedSingleDepositorParams =
            newFactory.storeAndFetchFeeVaultParameters(singleDepositorParams);
        assertEq(address(storedSingleDepositorParams.feeCalculator), address(singleDepositorParams.feeCalculator));
        assertEq(address(storedSingleDepositorParams.feeToken), address(singleDepositorParams.feeToken));
    }
}

contract SingleDepositorVaultFactoryPublic is SingleDepositorVaultFactory, Test {
    constructor(address initialOwner, Authority initialAuthority, address deployDelegate)
        SingleDepositorVaultFactory(initialOwner, initialAuthority, deployDelegate)
    { }

    // solhint-disable-next-line foundry-test-functions
    function storeAndFetchBaseVaultParameters(BaseVaultParameters calldata params)
        external
        returns (BaseVaultParameters memory)
    {
        _storeBaseVaultParameters(params);
        return this.baseVaultParameters();
    }

    // solhint-disable-next-line foundry-test-functions
    function storeAndFetchFeeVaultParameters(FeeVaultParameters calldata params)
        external
        returns (FeeVaultParameters memory)
    {
        _storeFeeVaultParameters(params);
        return this.feeVaultParameters();
    }
}
