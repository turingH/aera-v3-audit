// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";

import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";

import { MultiDepositorVault } from "src/core/MultiDepositorVault.sol";

import { IERC20Errors } from "@oz/interfaces/draft-IERC6093.sol";

import { Pausable } from "@oz/utils/Pausable.sol";
import { BaseVaultParameters, FeeVaultParameters } from "src/core/Types.sol";
import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";

import { IMultiDepositorVault } from "src/core/interfaces/IMultiDepositorVault.sol";
import { IProvisioner } from "src/core/interfaces/IProvisioner.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";
import { MockMultiDepositorVaultFactory } from "test/core/mocks/MockMultiDepositorVaultFactory.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract MultiDepositorVaultTest is BaseTest, MockMultiDepositorVaultFactory {
    MultiDepositorVault internal multiDepositorVault;
    ERC20Mock internal token;

    function setUp() public override {
        super.setUp();

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

        setMultiDepositorVaultParameters("MultiDepositorVault", "MDV", IBeforeTransferHook(BEFORE_TRANSFER_HOOK));

        multiDepositorVault = new MultiDepositorVault();
        multiDepositorVault.setProvisioner(PROVISIONER);

        vm.prank(users.owner);
        multiDepositorVault.acceptOwnership();
        vm.prank(users.owner);
        multiDepositorVault.setGuardianRoot(users.guardian, RANDOM_BYTES32);

        token = new ERC20Mock();
    }

    ////////////////////////////////////////////////////////////
    //                       Deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public view {
        assertEq(multiDepositorVault.name(), "MultiDepositorVault");
        assertEq(multiDepositorVault.symbol(), "MDV");
        assertEq(address(multiDepositorVault.beforeTransferHook()), address(BEFORE_TRANSFER_HOOK));
        assertEq(multiDepositorVault.owner(), users.owner);
    }

    ////////////////////////////////////////////////////////////
    //                         enter                          //
    ////////////////////////////////////////////////////////////

    function test_enter_success_tokens() public {
        uint256 tokenAmount = 100e18;
        uint256 unitsAmount = 50e18;

        token.mint(users.owner, tokenAmount);

        vm.prank(users.owner);
        token.approve(address(multiDepositorVault), tokenAmount);

        _mockBeforeTransferHook(address(0), users.owner);

        vm.prank(PROVISIONER);
        vm.expectEmit(true, false, false, true, address(multiDepositorVault));
        emit IMultiDepositorVault.Enter(users.owner, users.owner, token, tokenAmount, unitsAmount);
        multiDepositorVault.enter(users.owner, token, tokenAmount, unitsAmount, users.owner);

        assertEq(token.balanceOf(address(multiDepositorVault)), tokenAmount);
        assertEq(multiDepositorVault.balanceOf(users.owner), unitsAmount);
        vm.snapshotGasLastCall("enter - success - with tokens");
    }

    function test_enter_success_no_tokens() public {
        uint256 unitsAmount = 50e18;

        _mockBeforeTransferHook(address(0), users.owner);

        vm.prank(PROVISIONER);

        vm.expectEmit(false, false, false, true, address(multiDepositorVault));
        emit IMultiDepositorVault.Enter(address(this), users.owner, IERC20(address(0)), 0, unitsAmount);
        multiDepositorVault.enter(address(this), IERC20(address(0)), 0, unitsAmount, users.owner);

        assertEq(multiDepositorVault.balanceOf(users.owner), unitsAmount);
        vm.snapshotGasLastCall("enter - success - no tokens");
    }

    function test_enter_revertsWith_CallerIsNotProvisioner() public {
        vm.expectRevert(IMultiDepositorVault.Aera__CallerIsNotProvisioner.selector);
        multiDepositorVault.enter(address(this), IERC20(address(0)), 0, 50e18, users.owner);
    }

    function test_enter_revertsWith_safeERC20FailedOperation() public {
        uint256 tokenAmount = 100e18;
        uint256 unitsAmount = 50e18;

        token.mint(users.owner, tokenAmount - 1);

        vm.prank(users.owner);
        token.approve(address(multiDepositorVault), tokenAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, users.owner, tokenAmount - 1, tokenAmount
            )
        );
        vm.prank(PROVISIONER);
        multiDepositorVault.enter(users.owner, token, tokenAmount, unitsAmount, users.owner);
    }

    function test_enter_revertsWith_paused() public {
        vm.prank(users.owner);
        multiDepositorVault.pause();

        vm.prank(PROVISIONER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        multiDepositorVault.enter(address(this), token, 0, 50e18, users.owner);
    }

    function test_enter_revertsWith_beforeTransferHook() public {
        uint256 tokenAmount = 100e18;
        uint256 unitsAmount = 50e18;

        token.mint(users.owner, tokenAmount);

        vm.prank(users.owner);
        token.approve(address(multiDepositorVault), tokenAmount);

        vm.mockCallRevert(
            BEFORE_TRANSFER_HOOK,
            abi.encodeWithSelector(IBeforeTransferHook.beforeTransfer.selector, address(0), users.owner),
            hex"c0de"
        );

        vm.prank(PROVISIONER);
        vm.expectRevert();
        multiDepositorVault.enter(users.owner, token, tokenAmount, unitsAmount, users.owner);
    }

    ////////////////////////////////////////////////////////////
    //                         exit                           //
    ////////////////////////////////////////////////////////////

    function test_exit_success_tokens() public {
        uint256 tokenAmount = 100e18;
        uint256 unitsAmount = 50e18;

        _mockAreUserUnitsLocked(users.owner, false);
        _mockBeforeTransferHook(address(0), users.owner);
        _mockBeforeTransferHook(users.owner, address(0));

        // Setup: mint tokens and units first
        token.mint(address(multiDepositorVault), tokenAmount);
        vm.prank(PROVISIONER);
        multiDepositorVault.enter(address(this), token, 0, unitsAmount, users.owner);

        vm.prank(PROVISIONER);
        vm.expectEmit(true, false, false, true, address(multiDepositorVault));
        emit IMultiDepositorVault.Exit(users.owner, users.owner, token, tokenAmount, unitsAmount);
        multiDepositorVault.exit(users.owner, token, tokenAmount, unitsAmount, users.owner);

        assertEq(token.balanceOf(users.owner), tokenAmount);
        assertEq(multiDepositorVault.balanceOf(users.owner), 0);
        vm.snapshotGasLastCall("exit - success - with tokens");
    }

    function test_exit_success_no_tokens() public {
        uint256 unitsAmount = 50e18;

        _mockAreUserUnitsLocked(users.owner, false);
        _mockBeforeTransferHook(address(0), users.owner);
        _mockBeforeTransferHook(users.owner, address(0));

        // Setup: mint units first
        vm.prank(PROVISIONER);
        multiDepositorVault.enter(users.owner, IERC20(address(0)), 0, unitsAmount, users.owner);

        vm.prank(PROVISIONER);
        vm.expectEmit(false, false, false, true, address(multiDepositorVault));
        emit IMultiDepositorVault.Exit(users.owner, users.owner, IERC20(address(0)), 0, unitsAmount);
        multiDepositorVault.exit(users.owner, IERC20(address(0)), 0, unitsAmount, users.owner);

        assertEq(multiDepositorVault.balanceOf(users.owner), 0);
        vm.snapshotGasLastCall("exit - success - no tokens");
    }

    function test_exit_revertsWith_CallerIsNotProvisioner() public {
        vm.expectRevert(IMultiDepositorVault.Aera__CallerIsNotProvisioner.selector);
        multiDepositorVault.exit(address(this), IERC20(address(0)), 0, 50e18, users.owner);
    }

    function test_exit_revertsWith_safeERC20FailedOperation() public {
        uint256 tokenAmount = 100e18;
        uint256 unitsAmount = 50e18;

        _mockAreUserUnitsLocked(users.owner, false);
        _mockBeforeTransferHook(address(0), users.owner);

        // Setup: mint units but not enough tokens
        vm.prank(PROVISIONER);
        multiDepositorVault.enter(users.owner, token, 0, unitsAmount, users.owner);
        token.mint(address(multiDepositorVault), tokenAmount - 1);

        vm.prank(PROVISIONER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(multiDepositorVault),
                tokenAmount - 1,
                tokenAmount
            )
        );
        multiDepositorVault.exit(users.owner, token, tokenAmount, unitsAmount, users.owner);
    }

    function test_exit_revertsWith_ERC20InsufficientBalance() public {
        uint256 tokenAmount = 100e18;
        uint256 unitsAmount = 50e18;

        _mockBeforeTransferHook(address(0), users.owner);
        _mockAreUserUnitsLocked(users.owner, false);

        // Setup: mint tokens and units first
        token.mint(address(multiDepositorVault), tokenAmount);
        vm.prank(PROVISIONER);
        multiDepositorVault.enter(users.owner, token, 0, unitsAmount, users.owner);

        vm.prank(PROVISIONER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, users.owner, unitsAmount, unitsAmount + 1
            )
        );
        multiDepositorVault.exit(users.owner, token, tokenAmount, unitsAmount + 1, users.owner);
    }

    function test_exit_revertsWith_paused() public {
        vm.prank(users.owner);
        multiDepositorVault.pause();

        vm.prank(PROVISIONER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        multiDepositorVault.exit(address(this), token, 0, 50e18, users.owner);
    }

    function test_exit_revertsWith_beforeTransferHook() public {
        uint256 tokenAmount = 100e18;
        uint256 unitsAmount = 50e18;

        _mockAreUserUnitsLocked(users.owner, false);
        _mockBeforeTransferHook(address(0), users.owner);
        _mockBeforeTransferHook(users.owner, address(0));

        vm.prank(PROVISIONER);
        multiDepositorVault.enter(users.owner, token, 0, unitsAmount, users.owner);

        vm.mockCallRevert(
            BEFORE_TRANSFER_HOOK,
            abi.encodeWithSelector(IBeforeTransferHook.beforeTransfer.selector, users.owner, address(0)),
            hex"c0de"
        );

        vm.prank(PROVISIONER);
        vm.expectRevert();
        multiDepositorVault.exit(users.owner, token, tokenAmount, unitsAmount, users.owner);
    }

    ////////////////////////////////////////////////////////////
    //                      enter + exit                      //
    ////////////////////////////////////////////////////////////

    function test_fuzz_enterAndExit_success(uint256 tokenAmount, uint256 unitsAmount, address sender, address recipient)
        public
    {
        vm.assume(sender != address(0) && recipient != address(0));
        vm.assume(tokenAmount > 0 && tokenAmount < type(uint256).max);
        vm.assume(unitsAmount > 0);

        token.mint(sender, tokenAmount);
        vm.prank(sender);
        token.approve(address(multiDepositorVault), tokenAmount);

        _mockBeforeTransferHook(address(0), sender);
        _mockBeforeTransferHook(recipient, address(0));

        // Enter
        vm.prank(PROVISIONER);
        vm.expectEmit(true, false, false, true, address(multiDepositorVault));
        emit IMultiDepositorVault.Enter(sender, recipient, token, tokenAmount, unitsAmount);
        multiDepositorVault.enter(sender, token, tokenAmount, unitsAmount, recipient);

        assertEq(token.balanceOf(address(multiDepositorVault)), tokenAmount);
        assertEq(multiDepositorVault.balanceOf(recipient), unitsAmount);

        // Exit
        vm.prank(PROVISIONER);
        vm.expectEmit(true, false, false, true, address(multiDepositorVault));
        emit IMultiDepositorVault.Exit(recipient, sender, token, tokenAmount, unitsAmount);
        multiDepositorVault.exit(recipient, token, tokenAmount, unitsAmount, sender);

        assertEq(token.balanceOf(sender), tokenAmount);
        assertEq(multiDepositorVault.balanceOf(recipient), 0);
    }

    ////////////////////////////////////////////////////////////
    //                        transfer                        //
    ////////////////////////////////////////////////////////////

    function test_transfer_success() public {
        _mockAreUserUnitsLocked(users.alice, false);
        _mockBeforeTransferHook(users.alice, users.bob);

        vm.prank(PROVISIONER);
        multiDepositorVault.enter(address(0), token, 0, 100e18, users.alice);

        vm.startPrank(users.alice);
        assertTrue(multiDepositorVault.transfer(users.bob, 100e18));
    }

    function test_transfer_revertsWith_beforeTransferFailed() public {
        vm.prank(PROVISIONER);
        _mockBeforeTransferHook(address(0), users.alice);
        multiDepositorVault.enter(address(0), token, 0, 100e18, users.alice);

        vm.mockCallRevert(
            address(BEFORE_TRANSFER_HOOK),
            abi.encodeWithSelector(IBeforeTransferHook.beforeTransfer.selector, users.alice, users.bob),
            hex"c0de"
        );
        vm.expectRevert();
        vm.prank(users.alice);
        multiDepositorVault.transfer(users.bob, 100e18);
    }

    function test_transfer_revertsWith_unitsLocked() public {
        vm.prank(PROVISIONER);
        _mockBeforeTransferHook(address(0), users.alice);
        multiDepositorVault.enter(address(0), token, 0, 100e18, users.alice);

        _mockAreUserUnitsLocked(users.alice, true);
        _mockBeforeTransferHook(users.alice, users.bob);

        vm.prank(users.alice);
        vm.expectRevert(IMultiDepositorVault.Aera__UnitsLocked.selector);
        multiDepositorVault.transfer(users.bob, 100e18);
    }

    ////////////////////////////////////////////////////////////
    //                      transferFrom                      //
    ////////////////////////////////////////////////////////////

    function test_transferFrom_success() public {
        _mockAreUserUnitsLocked(users.alice, false);
        _mockBeforeTransferHook(users.alice, users.bob);

        vm.prank(PROVISIONER);
        multiDepositorVault.enter(address(0), token, 0, 100e18, users.alice);

        vm.prank(users.alice);
        multiDepositorVault.approve(address(this), 100e18);

        assertTrue(multiDepositorVault.transferFrom(users.alice, users.bob, 100e18));
    }

    function test_transferFrom_revertsWith_beforeTransferFailed() public {
        vm.prank(PROVISIONER);
        _mockBeforeTransferHook(address(0), users.alice);
        multiDepositorVault.enter(address(0), token, 0, 100e18, users.alice);

        _mockAreUserUnitsLocked(users.alice, false);
        vm.mockCallRevert(
            address(BEFORE_TRANSFER_HOOK),
            abi.encodeWithSelector(IBeforeTransferHook.beforeTransfer.selector, users.alice, users.bob),
            hex"c0de"
        );
        vm.prank(users.alice);
        multiDepositorVault.approve(address(this), 100e18);

        vm.expectRevert();
        multiDepositorVault.transferFrom(users.alice, users.bob, 100e18);
    }

    function test_transferFrom_revertsWith_unitsLocked() public {
        vm.prank(PROVISIONER);
        _mockBeforeTransferHook(address(0), users.alice);
        multiDepositorVault.enter(address(0), token, 0, 100e18, users.alice);

        _mockAreUserUnitsLocked(users.alice, true);
        _mockBeforeTransferHook(users.alice, users.bob);

        vm.prank(users.alice);
        multiDepositorVault.approve(address(this), 100e18);

        vm.expectRevert(IMultiDepositorVault.Aera__UnitsLocked.selector);
        multiDepositorVault.transferFrom(users.alice, users.bob, 100e18);
    }

    ////////////////////////////////////////////////////////////
    //                     setProvisioner                     //
    ////////////////////////////////////////////////////////////

    function test_setProvisioner_success() public {
        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true, address(multiDepositorVault));
        emit IMultiDepositorVault.ProvisionerSet(PROVISIONER);
        multiDepositorVault.setProvisioner(PROVISIONER);
    }

    function test_setProvisioner_revertsWith_zeroAddress() public {
        vm.prank(users.owner);
        vm.expectRevert(IMultiDepositorVault.Aera__ZeroAddressProvisioner.selector);
        multiDepositorVault.setProvisioner(address(0));
    }

    ////////////////////////////////////////////////////////////
    //                 setBeforeTransferHook                  //
    ////////////////////////////////////////////////////////////

    function test_setBeforeTransferHook_success() public {
        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true, address(multiDepositorVault));
        emit IMultiDepositorVault.BeforeTransferHookSet(address(0xabcd));
        multiDepositorVault.setBeforeTransferHook(IBeforeTransferHook(address(0xabcd)));

        assertEq(address(multiDepositorVault.beforeTransferHook()), address(0xabcd));
    }

    function test_setBeforeTransferHook_revertsWith_unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        multiDepositorVault.setBeforeTransferHook(IBeforeTransferHook(address(0xabcd)));
    }

    function _mockBeforeTransferHook(address from, address to) internal {
        vm.mockCall(
            address(BEFORE_TRANSFER_HOOK),
            abi.encodeWithSelector(IBeforeTransferHook.beforeTransfer.selector, from, to),
            abi.encode(false)
        );
    }

    function _mockAreUserUnitsLocked(address user, bool locked) internal {
        vm.mockCall(
            address(PROVISIONER),
            abi.encodeWithSelector(IProvisioner.areUserUnitsLocked.selector, user),
            abi.encode(locked)
        );
    }
}
