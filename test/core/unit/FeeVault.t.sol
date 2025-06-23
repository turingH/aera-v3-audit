// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { BaseVaultParameters, FeeVaultParameters } from "src/core/Types.sol";

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";
import { IFeeVault } from "src/core/interfaces/IFeeVault.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";
import { MockFeeVaultFactory } from "test/core/mocks/MockFeeVaultFactory.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract SingleDepositorVaultTest is BaseTest, MockFeeVaultFactory {
    SingleDepositorVault internal singleDepositorVault;

    bytes32 public root;

    function setUp() public override {
        super.setUp();

        root = RANDOM_BYTES32;

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
            FeeVaultParameters({ feeToken: feeToken, feeCalculator: mockFeeCalculator, feeRecipient: users.feeRecipient })
        );

        singleDepositorVault = new SingleDepositorVault();

        vm.prank(users.owner);
        singleDepositorVault.acceptOwnership();
        vm.prank(users.owner);
        singleDepositorVault.setGuardianRoot(users.guardian, root);
    }

    ////////////////////////////////////////////////////////////
    //                       deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public view {
        assertEq(address(singleDepositorVault.feeCalculator()), address(mockFeeCalculator));
        assertEq(address(singleDepositorVault.FEE_TOKEN()), address(feeToken));
        assertEq(singleDepositorVault.feeRecipient(), users.feeRecipient);
    }

    function test_deployment_revertsWith_ZeroAddressFeeCalculator() public {
        setFeeVaultParameters(
            FeeVaultParameters({
                feeToken: feeToken,
                feeCalculator: IFeeCalculator(address(0)),
                feeRecipient: users.feeRecipient
            })
        );

        vm.expectRevert(IFeeVault.Aera__ZeroAddressFeeCalculator.selector);
        new SingleDepositorVault();
    }

    function test_deployment_revertsWith_ZeroAddressFeeToken() public {
        setFeeVaultParameters(
            FeeVaultParameters({
                feeToken: IERC20(address(0)),
                feeCalculator: mockFeeCalculator,
                feeRecipient: users.feeRecipient
            })
        );

        vm.expectRevert(IFeeVault.Aera__ZeroAddressFeeToken.selector);
        new SingleDepositorVault();
    }

    function test_deployment_revertsWith_ZeroAddressFeeRecipient() public {
        setFeeVaultParameters(
            FeeVaultParameters({ feeToken: feeToken, feeCalculator: mockFeeCalculator, feeRecipient: address(0) })
        );

        vm.expectRevert(IFeeVault.Aera__ZeroAddressFeeRecipient.selector);
        new SingleDepositorVault();
    }

    function test_deployment_revertsWith_RegisterVaultReverts() public {
        vm.mockCallRevert(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.registerVault.selector),
            abi.encode(bytes("Aera__VaultAlreadyRegistered"))
        );

        vm.expectRevert();
        new SingleDepositorVault();
    }

    ////////////////////////////////////////////////////////////
    //                       claimFees                        //
    ////////////////////////////////////////////////////////////

    function test_claimFees_success() public {
        uint256 feeAmount = 1e18;
        feeToken.mint(address(singleDepositorVault), feeAmount);

        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimFees.selector),
            abi.encode(feeAmount, 0, users.protocolFeeRecipient)
        );

        vm.prank(users.feeRecipient);

        vm.expectEmit(true, true, true, true);
        emit IFeeVault.FeesClaimed(users.feeRecipient, feeAmount);
        singleDepositorVault.claimFees();
        vm.snapshotGasLastCall("claimFees - success - no protocol fees");

        assertEq(feeToken.balanceOf(users.feeRecipient), feeAmount);
        assertEq(feeToken.balanceOf(address(singleDepositorVault)), 0);
    }

    function test_claimFees_success_withProtocolFees() public {
        uint256 feeAmount = 1e18;
        uint256 protocolFee = 0.5e18;
        feeToken.mint(address(singleDepositorVault), feeAmount + protocolFee);

        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimFees.selector),
            abi.encode(feeAmount, protocolFee, users.protocolFeeRecipient)
        );

        vm.prank(users.feeRecipient);

        vm.expectEmit(true, true, true, true);
        emit IFeeVault.FeesClaimed(users.feeRecipient, feeAmount);
        vm.expectEmit(true, true, true, true);
        emit IFeeVault.ProtocolFeesClaimed(users.protocolFeeRecipient, protocolFee);
        singleDepositorVault.claimFees();
        vm.snapshotGasLastCall("claimFees - success with protocol");

        assertEq(feeToken.balanceOf(users.feeRecipient), feeAmount);
        assertEq(feeToken.balanceOf(address(singleDepositorVault)), 0);
        assertEq(feeToken.balanceOf(users.protocolFeeRecipient), protocolFee);
    }

    function test_fuzz_claimFees_success(uint256 feeAmount, uint256 protocolFee, uint256 vaultRemainingBalance)
        public
    {
        vm.assume(feeAmount > 0);
        vm.assume(protocolFee <= type(uint256).max - feeAmount);
        vm.assume(vaultRemainingBalance <= type(uint256).max - feeAmount - protocolFee);

        feeToken.mint(address(singleDepositorVault), feeAmount + protocolFee + vaultRemainingBalance);

        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimFees.selector),
            abi.encode(feeAmount, protocolFee, users.protocolFeeRecipient)
        );

        vm.prank(users.feeRecipient);
        vm.expectEmit(true, true, true, true);
        emit IFeeVault.FeesClaimed(users.feeRecipient, feeAmount);
        if (protocolFee > 0) {
            vm.expectEmit(true, true, true, true);
            emit IFeeVault.ProtocolFeesClaimed(users.protocolFeeRecipient, protocolFee);
        }
        singleDepositorVault.claimFees();

        assertEq(feeToken.balanceOf(users.feeRecipient), feeAmount);
        assertEq(feeToken.balanceOf(address(singleDepositorVault)), vaultRemainingBalance);
        assertEq(feeToken.balanceOf(users.protocolFeeRecipient), protocolFee);
    }

    function test_claimFees_revertsWith_NoFeesToClaim() public {
        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimFees.selector),
            abi.encode(0, 0, users.protocolFeeRecipient)
        );

        vm.prank(users.feeRecipient);
        vm.expectRevert(IFeeVault.Aera__NoFeesToClaim.selector);
        singleDepositorVault.claimFees();
    }

    function test_claimFees_revertsWith_Erc20TransferFailed_FeeRecipient() public {
        uint256 feeAmount = 1e18;

        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimFees.selector),
            abi.encode(feeAmount, 0, users.protocolFeeRecipient)
        );

        vm.prank(users.feeRecipient);

        vm.expectRevert();
        singleDepositorVault.claimFees();
    }

    function test_claimFees_revertsWith_Erc20TransferFailed_Protocol() public {
        uint256 feeAmount = 1e18;
        uint256 protocolFee = 0.5e18;
        feeToken.mint(address(singleDepositorVault), feeAmount);

        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimFees.selector),
            abi.encode(feeAmount, protocolFee, users.protocolFeeRecipient)
        );

        vm.prank(users.feeRecipient);

        vm.expectRevert();
        singleDepositorVault.claimFees();
    }

    function test_claimFees_revertsWith_CallerIsNotFeeRecipient() public {
        vm.prank(users.stranger);
        vm.expectRevert(IFeeVault.Aera__CallerIsNotFeeRecipient.selector);
        singleDepositorVault.claimFees();
    }

    ////////////////////////////////////////////////////////////
    //                   claimProtocolFees                    //
    ////////////////////////////////////////////////////////////

    function test_claimProtocolFees_success() public {
        uint256 feeAmount = 1e18;
        feeToken.mint(address(singleDepositorVault), feeAmount);

        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimProtocolFees.selector),
            abi.encode(feeAmount, users.protocolFeeRecipient)
        );

        vm.prank(users.protocolFeeRecipient);

        vm.expectEmit(true, true, true, true);
        emit IFeeVault.ProtocolFeesClaimed(users.protocolFeeRecipient, feeAmount);
        singleDepositorVault.claimProtocolFees();
        vm.snapshotGasLastCall("claimProtocolFees - success");

        assertEq(feeToken.balanceOf(users.protocolFeeRecipient), feeAmount);
        assertEq(feeToken.balanceOf(address(singleDepositorVault)), 0);
    }

    function test_fuzz_claimProtocolFees_success(uint256 protocolFee, uint256 vaultRemainingBalance) public {
        vm.assume(protocolFee > 0);
        vm.assume(vaultRemainingBalance <= type(uint256).max - protocolFee);
        feeToken.mint(address(singleDepositorVault), protocolFee + vaultRemainingBalance);

        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimProtocolFees.selector),
            abi.encode(protocolFee, users.protocolFeeRecipient)
        );

        vm.prank(users.protocolFeeRecipient);
        vm.expectEmit(true, true, true, true);
        emit IFeeVault.ProtocolFeesClaimed(users.protocolFeeRecipient, protocolFee);
        singleDepositorVault.claimProtocolFees();

        assertEq(feeToken.balanceOf(users.protocolFeeRecipient), protocolFee);
        assertEq(feeToken.balanceOf(address(singleDepositorVault)), vaultRemainingBalance);
    }

    function test_claimProtocolFees_revertsWith_NoFeesToClaim() public {
        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimProtocolFees.selector),
            abi.encode(0, users.protocolFeeRecipient)
        );
        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.protocolFeeRecipient.selector),
            abi.encode(users.protocolFeeRecipient)
        );

        vm.prank(users.protocolFeeRecipient);
        vm.expectRevert(IFeeVault.Aera__NoFeesToClaim.selector);
        singleDepositorVault.claimProtocolFees();
    }

    function test_claimProtocolFees_revertsWith_Erc20TransferFailed() public {
        uint256 feeAmount = 1e18;
        feeToken.mint(address(singleDepositorVault), feeAmount - 1);

        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimProtocolFees.selector),
            abi.encode(feeAmount, users.protocolFeeRecipient)
        );

        vm.prank(users.protocolFeeRecipient);
        vm.expectRevert();
        singleDepositorVault.claimProtocolFees();
    }

    function test_claimProtocolFees_revertsWith_Unauthorized() public {
        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.claimProtocolFees.selector),
            abi.encode(1e18, users.protocolFeeRecipient)
        );
        vm.mockCall(
            address(mockFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.protocolFeeRecipient.selector),
            abi.encode(users.protocolFeeRecipient)
        );

        vm.prank(users.feeRecipient);
        vm.expectRevert(IFeeVault.Aera__CallerIsNotProtocolFeeRecipient.selector);
        singleDepositorVault.claimProtocolFees();
    }

    ////////////////////////////////////////////////////////////
    //                    setFeeCalculator                    //
    ////////////////////////////////////////////////////////////

    function test_setFeeCalculator_success() public {
        IFeeCalculator newFeeCalculator = IFeeCalculator(makeAddr("newFeeCalculator"));
        vm.mockCall(address(newFeeCalculator), abi.encodeWithSelector(IFeeCalculator.registerVault.selector), "");

        vm.prank(users.owner);

        vm.expectEmit(false, false, false, true);
        emit IFeeVault.FeeCalculatorUpdated(address(newFeeCalculator));
        singleDepositorVault.setFeeCalculator(newFeeCalculator);
        vm.snapshotGasLastCall("setFeeCalculator - success");
    }

    function test_setFeeCalculator_revertsWith_VaultAlreadyRegistered() public {
        IFeeCalculator newFeeCalculator = IFeeCalculator(makeAddr("newFeeCalculator"));
        vm.mockCallRevert(
            address(newFeeCalculator),
            abi.encodeWithSelector(IFeeCalculator.registerVault.selector),
            abi.encode(IFeeCalculator.Aera__VaultAlreadyRegistered.selector)
        );

        vm.prank(users.owner);

        vm.expectRevert();
        singleDepositorVault.setFeeCalculator(newFeeCalculator);
    }

    function test_setFeeCalculator_revertsWith_Unauthorized() public {
        vm.prank(users.stranger);
        vm.expectRevert("UNAUTHORIZED");
        singleDepositorVault.setFeeCalculator(mockFeeCalculator);
    }

    ////////////////////////////////////////////////////////////
    //                    setFeeRecipient                     //
    ////////////////////////////////////////////////////////////

    function test_setFeeRecipient_success() public {
        vm.prank(users.owner);
        vm.expectEmit(false, false, false, true);
        emit IFeeVault.FeeRecipientUpdated(users.feeRecipient);
        singleDepositorVault.setFeeRecipient(users.feeRecipient);
        vm.snapshotGasLastCall("setFeeRecipient - success");

        assertEq(singleDepositorVault.feeRecipient(), users.feeRecipient);
    }

    function test_setFeeRecipient_revertsWith_Unauthorized() public {
        vm.prank(users.stranger);
        vm.expectRevert("UNAUTHORIZED");
        singleDepositorVault.setFeeRecipient(users.feeRecipient);
    }

    function test_setFeeRecipient_revertsWith_ZeroAddressFeeRecipient() public {
        vm.prank(users.owner);
        vm.expectRevert(IFeeVault.Aera__ZeroAddressFeeRecipient.selector);
        singleDepositorVault.setFeeRecipient(address(0));
    }
}
