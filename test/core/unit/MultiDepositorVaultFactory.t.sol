// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { ShortStrings } from "@oz/utils/ShortStrings.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { MultiDepositorVault } from "src/core/MultiDepositorVault.sol";

import { MultiDepositorVaultFactory } from "src/core/MultiDepositorVaultFactory.sol";
import { BaseVaultParameters, ERC20Parameters, FeeVaultParameters } from "src/core/Types.sol";
import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";
import { IBaseVaultDeployer } from "src/core/interfaces/IBaseVaultDeployer.sol";
import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";
import { IMultiDepositorVaultFactory } from "src/core/interfaces/IMultiDepositorVaultFactory.sol";

import { Create2 } from "@oz/utils/Create2.sol";
import { TestBaseMultiDepositorVault } from "test/core/utils/TestBaseMultiDepositorVault.sol";

contract MultiDepositorVaultFactoryTest is TestBaseMultiDepositorVault {
    MultiDepositorVaultFactoryPublic internal factoryPublic;

    function setUp() public override {
        super.setUp();

        factoryPublic =
            new MultiDepositorVaultFactoryPublic(FACTORY_OWNER, Authority(address(0)), address(deployDelegate));
    }
    ////////////////////////////////////////////////////////////
    //                       deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_deployment_success() public {
        MultiDepositorVaultFactory factory =
            new MultiDepositorVaultFactory(FACTORY_OWNER, Authority(address(0xabcd)), address(deployDelegate));
        assertEq(factory.owner(), FACTORY_OWNER);
        assertEq(address(factory.authority()), address(0xabcd));
    }

    function test_deployment_revertsWith_ZeroAddressDeployDelegate() public {
        vm.expectRevert(IMultiDepositorVaultFactory.Aera__ZeroAddressDeployDelegate.selector);
        new MultiDepositorVaultFactoryPublic(FACTORY_OWNER, Authority(address(0)), address(0));
    }

    ////////////////////////////////////////////////////////////
    //                         Create                         //
    ////////////////////////////////////////////////////////////

    function test_create_revertsWith_Unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");

        address expectedVaultAddress_ =
            Create2.computeAddress(bytes32(ONE), keccak256(type(MultiDepositorVault).creationCode), address(factory));

        vm.prank(users.stranger);
        _deployAeraV3Contracts(bytes32(ONE), expectedVaultAddress_);
    }

    function test_create_revertsWith_ZeroAddressOwner() public {
        baseVaultParameters.owner = address(0);

        address expectedVaultAddress_ =
            Create2.computeAddress(bytes32(ONE), keccak256(type(MultiDepositorVault).creationCode), address(factory));

        vm.prank(FACTORY_OWNER);
        vm.expectRevert(IBaseVault.Aera__ZeroAddressOwner.selector);
        _deployAeraV3Contracts(bytes32(ONE), expectedVaultAddress_);
    }

    function test_create_revertsWith_DescriptionIsEmpty() public {
        vm.prank(FACTORY_OWNER);
        vm.expectRevert(IBaseVaultDeployer.Aera__DescriptionIsEmpty.selector);
        factory.create(
            bytes32(ONE), "", erc20Parameters, baseVaultParameters, feeVaultParameters, beforeTransferHook, address(0)
        );
    }

    function test_create_success() public {
        address expectedVaultAddress_ =
            Create2.computeAddress(bytes32(ONE), keccak256(type(MultiDepositorVault).creationCode), address(factory));

        vm.expectEmit(false, false, false, true);
        emit IMultiDepositorVaultFactory.VaultCreated(
            expectedVaultAddress_,
            baseVaultParameters.owner,
            address(baseVaultParameters.submitHooks),
            erc20Parameters,
            feeVaultParameters,
            beforeTransferHook,
            "Test Vault"
        );
        vm.prank(FACTORY_OWNER);
        address deployedVault = factory.create(
            bytes32(ONE),
            "Test Vault",
            erc20Parameters,
            baseVaultParameters,
            feeVaultParameters,
            beforeTransferHook,
            expectedVaultAddress_
        );
        vm.snapshotGasLastCall("create - success");
        vault = MultiDepositorVault(payable(deployedVault));

        assertEq(address(vault), expectedVaultAddress_);
        assertEq(vault.pendingOwner(), baseVaultParameters.owner);
        assertEq(address(vault.authority()), address(baseVaultParameters.authority));
        assertEq(vault.name(), erc20Parameters.name);
        assertEq(vault.symbol(), erc20Parameters.symbol);
        assertEq(address(vault.feeCalculator()), address(feeVaultParameters.feeCalculator));
        assertEq(address(vault.FEE_TOKEN()), address(feeVaultParameters.feeToken));
        assertEq(vault.feeRecipient(), feeVaultParameters.feeRecipient);
        assertEq(address(vault.beforeTransferHook()), address(beforeTransferHook));
    }

    ////////////////////////////////////////////////////////////
    //                    Vault Parameters                    //
    ////////////////////////////////////////////////////////////

    function test_fuzz_storeBaseVaultParameters_success(BaseVaultParameters calldata params) public {
        BaseVaultParameters memory storedParams = factoryPublic.storeAndFetchBaseVaultParameters(params);
        assertEq(storedParams.owner, params.owner);
        assertEq(address(storedParams.submitHooks), address(params.submitHooks));
        assertEq(address(storedParams.whitelist), address(params.whitelist));
    }

    function test_fuzz_storeFeeVaultParameters_success(FeeVaultParameters calldata params) public {
        FeeVaultParameters memory storedParams = factoryPublic.storeAndFetchFeeVaultParameters(params);
        assertEq(address(storedParams.feeCalculator), address(params.feeCalculator));
        assertEq(address(storedParams.feeToken), address(params.feeToken));
    }

    function test_fuzz_storeMultiDepositorVaultParameters_success(IBeforeTransferHook beforeTransferHook) public {
        IBeforeTransferHook storedBeforeTransferHook =
            factoryPublic.storeAndFetchMultiDepositorVaultParameters(beforeTransferHook);
        assertEq(address(storedBeforeTransferHook), address(beforeTransferHook));
    }

    function test_fuzz_storeERC20Parameters_success(ERC20Parameters calldata params) public {
        vm.assume(bytes(params.name).length < 32 && bytes(params.symbol).length < 32);

        ERC20Parameters memory storedParams = factoryPublic.storeAndFetchERC20Parameters(params);
        assertEq(storedParams.name, params.name);
        assertEq(storedParams.symbol, params.symbol);
    }

    function test_fuzz_storeERC20LongName_revertsWith_StringTooLong(ERC20Parameters calldata params) public {
        vm.assume(bytes(params.name).length >= 32 && bytes(params.symbol).length < 32);

        vm.expectRevert(abi.encodeWithSelector(ShortStrings.StringTooLong.selector, params.name));
        factoryPublic.storeAndFetchERC20Parameters(params);
    }

    function test_fuzz_storeERC20LongSymbol_revertsWith_StringTooLong(ERC20Parameters calldata params) public {
        vm.assume(bytes(params.symbol).length >= 32 && bytes(params.name).length < 32);

        vm.expectRevert(abi.encodeWithSelector(ShortStrings.StringTooLong.selector, params.symbol));
        factoryPublic.storeAndFetchERC20Parameters(params);
    }

    function test_fuzz_storeAllMultiDepositorVaultParameters_success(
        BaseVaultParameters calldata baseParams,
        FeeVaultParameters calldata feeVaultParams,
        IBeforeTransferHook beforeTransferHook,
        ERC20Parameters calldata params
    ) public {
        vm.assume(bytes(params.name).length < 32 && bytes(params.symbol).length < 32);

        BaseVaultParameters memory storedBaseParams = factoryPublic.storeAndFetchBaseVaultParameters(baseParams);
        FeeVaultParameters memory storedFeeVaultParams = factoryPublic.storeAndFetchFeeVaultParameters(feeVaultParams);
        IBeforeTransferHook storedBeforeTransferHook =
            factoryPublic.storeAndFetchMultiDepositorVaultParameters(beforeTransferHook);
        ERC20Parameters memory storedParams = factoryPublic.storeAndFetchERC20Parameters(params);

        assertEq(storedBaseParams.owner, baseParams.owner);
        assertEq(address(storedBaseParams.submitHooks), address(baseParams.submitHooks));
        assertEq(address(storedFeeVaultParams.feeCalculator), address(feeVaultParams.feeCalculator));
        assertEq(address(storedFeeVaultParams.feeToken), address(feeVaultParams.feeToken));
        assertEq(address(storedBeforeTransferHook), address(beforeTransferHook));
        assertEq(storedParams.name, params.name);
        assertEq(storedParams.symbol, params.symbol);
    }
}

contract MultiDepositorVaultFactoryPublic is MultiDepositorVaultFactory, Test {
    constructor(address initialOwner, Authority initialAuthority, address deployDelegate)
        MultiDepositorVaultFactory(initialOwner, initialAuthority, deployDelegate)
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

    // solhint-disable-next-line foundry-test-functions
    function storeAndFetchMultiDepositorVaultParameters(IBeforeTransferHook beforeTransferHook)
        external
        returns (IBeforeTransferHook)
    {
        _storeMultiDepositorVaultParameters(beforeTransferHook);
        return this.multiDepositorVaultParameters();
    }

    // solhint-disable-next-line foundry-test-functions
    function storeAndFetchERC20Parameters(ERC20Parameters calldata params) external returns (ERC20Parameters memory) {
        _storeERC20Parameters(params);
        return ERC20Parameters({ name: this.getERC20Name(), symbol: this.getERC20Symbol() });
    }
}
