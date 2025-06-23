// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { Test } from "forge-std/Test.sol";
import { MultiDepositorVaultDeployDelegate } from "src/core/MultiDepositorVaultDeployDelegate.sol";
import { MultiDepositorVaultFactory } from "src/core/MultiDepositorVaultFactory.sol";
import { BaseVaultParameters, ERC20Parameters, FeeVaultParameters } from "src/core/Types.sol";

import { Whitelist } from "src/core/Whitelist.sol";
import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";
import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { ComputeMultiDepositorVaultAddressLens } from "src/periphery/ComputeMultiDepositorVaultAddressLens.sol";

import { MockFeeCalculator } from "test/core/mocks/MockFeeCalculator.sol";

contract ComputeMultiDepositorVaultAddressLensTest is Test {
    ComputeMultiDepositorVaultAddressLens internal helper;
    MultiDepositorVaultDeployDelegate internal deployDelegate;
    MockFeeCalculator internal priceAndFeeCalculator;
    Whitelist internal whitelist;

    address internal guardian = 0x1234567890123456789012345678901234567890;

    function setUp() public {
        helper = new ComputeMultiDepositorVaultAddressLens();
        deployDelegate = new MultiDepositorVaultDeployDelegate();
        whitelist = new Whitelist(address(this), Authority(address(0)));
        priceAndFeeCalculator = new MockFeeCalculator();

        whitelist.setWhitelisted(guardian, true);
    }

    function test_computeMultiDepositorVaultFactoryAddress() public {
        MultiDepositorVaultFactory factory =
            new MultiDepositorVaultFactory(address(this), Authority(address(0)), address(deployDelegate));
        bytes32 salt = bytes32(uint256(1));

        string memory description = "Test Vault";

        ERC20Parameters memory erc20Params = ERC20Parameters({ name: "Test Token", symbol: "TEST" });
        BaseVaultParameters memory baseVaultParams = BaseVaultParameters({
            owner: 0x1234567890123456789012345678901234567890,
            authority: Authority(address(0)),
            submitHooks: ISubmitHooks(address(0)),
            whitelist: whitelist
        });
        FeeVaultParameters memory feeVaultParams = FeeVaultParameters({
            feeCalculator: IFeeCalculator(address(priceAndFeeCalculator)),
            feeToken: IERC20(address(0x1)),
            feeRecipient: 0x1234567890123456789012345678901234567890
        });
        IBeforeTransferHook beforeTransferHook = IBeforeTransferHook(address(1));

        address expectedAddress = helper.computeMultiDepositorVaultAddress(factory, salt);

        address actualAddress = factory.create(
            salt, description, erc20Params, baseVaultParams, feeVaultParams, beforeTransferHook, expectedAddress
        );

        assertEq(actualAddress, expectedAddress);
    }
}
