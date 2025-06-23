// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { Test } from "forge-std/Test.sol";

import { SingleDepositorVaultDeployDelegate } from "src/core/SingleDepositorVaultDeployDelegate.sol";
import { SingleDepositorVaultFactory } from "src/core/SingleDepositorVaultFactory.sol";
import { BaseVaultParameters, FeeVaultParameters } from "src/core/Types.sol";
import { Whitelist } from "src/core/Whitelist.sol";
import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { ComputeSingleDepositorVaultAddressLens } from "src/periphery/ComputeSingleDepositorVaultAddressLens.sol";
import { MockFeeCalculator } from "test/core/mocks/MockFeeCalculator.sol";

contract ComputeSingleDepositorVaultAddressLensTest is Test {
    ComputeSingleDepositorVaultAddressLens internal helper;
    Whitelist internal whitelist;
    MockFeeCalculator internal mockFeeCalculator;

    address internal owner = address(this);
    address internal guardian = 0x1234567890123456789012345678901234567890;
    address internal feeRecipient = 0x0987654321098765432109876543210987654321;
    IERC20 internal mockFeeToken = IERC20(address(0xfee));

    function setUp() public {
        helper = new ComputeSingleDepositorVaultAddressLens();
        whitelist = new Whitelist(owner, Authority(address(0))); // Whitelist is owned by the test contract initially
        mockFeeCalculator = new MockFeeCalculator();

        // Pre-whitelist the guardian for the test
        whitelist.setWhitelisted(guardian, true);
    }

    function test_computeSingleDepositorVaultAddress() public {
        address deployDelegate = address(new SingleDepositorVaultDeployDelegate());
        SingleDepositorVaultFactory factory =
            new SingleDepositorVaultFactory(owner, Authority(address(0)), deployDelegate);
        bytes32 salt = bytes32(uint256(1));
        string memory description = "Test Single Depositor Vault";

        BaseVaultParameters memory baseVaultParams = BaseVaultParameters({
            owner: 0x1234567890123456789012345678901234567890, // Vault owner
            authority: Authority(address(0)),
            submitHooks: ISubmitHooks(address(0)),
            whitelist: whitelist
        });

        FeeVaultParameters memory feeVaultParams = FeeVaultParameters({
            feeCalculator: IFeeCalculator(address(mockFeeCalculator)),
            feeToken: mockFeeToken,
            feeRecipient: feeRecipient
        });

        address expectedAddress = helper.computeSingleDepositorVaultAddress(factory, salt);

        // SingleDepositorVaultFactory create function is onlyOwner
        vm.prank(owner);
        address actualAddress = factory.create(salt, description, baseVaultParams, feeVaultParams, expectedAddress);

        assertEq(actualAddress, expectedAddress);
    }
}
