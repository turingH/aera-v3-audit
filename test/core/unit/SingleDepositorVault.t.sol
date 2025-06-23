// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { IERC4626 } from "@oz/interfaces/IERC4626.sol";
import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { ERC4626Mock } from "@oz/mocks/token/ERC4626Mock.sol";
import { Authority } from "@solmate/auth/Auth.sol";

import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { BaseVaultParameters, FeeVaultParameters, OperationPayable, TokenAmount } from "src/core/Types.sol";
import { IAuth2Step } from "src/core/interfaces/IAuth2Step.sol";

import { IBaseVault } from "src/core/interfaces/IBaseVault.sol";
import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";

import { IFeeVault } from "src/core/interfaces/IFeeVault.sol";

import { ISingleDepositorVault } from "src/core/interfaces/ISingleDepositorVault.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { MockFeeVaultFactory } from "test/core/mocks/MockFeeVaultFactory.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract SingleDepositorVaultTest is BaseTest, MockFeeVaultFactory {
    SingleDepositorVault internal singleDepositorVault;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;

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

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
    }

    ////////////////////////////////////////////////////////////
    //                       Deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public {
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

        vm.expectEmit(true, true, false, true);
        emit IAuth2Step.OwnershipTransferStarted(address(this), users.owner);

        SingleDepositorVault newSingleDepositorVault = new SingleDepositorVault();
        vm.snapshotGasLastCall("deployment - success");

        assertEq(newSingleDepositorVault.owner(), address(this));
        assertEq(newSingleDepositorVault.pendingOwner(), users.owner);
        assertFalse(newSingleDepositorVault.paused());
        assertEq(address(IFeeVault(address(newSingleDepositorVault)).feeCalculator()), address(mockFeeCalculator));
        assertEq(address(IFeeVault(address(newSingleDepositorVault)).FEE_TOKEN()), address(feeToken));
    }

    function test_deployment_revertsWith_ZeroAddressOwner() public {
        setBaseVaultParameters(
            BaseVaultParameters({
                owner: address(0),
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            })
        );
        setFeeVaultParameters(
            FeeVaultParameters({ feeToken: feeToken, feeCalculator: mockFeeCalculator, feeRecipient: users.feeRecipient })
        );
        vm.expectRevert(IBaseVault.Aera__ZeroAddressOwner.selector);
        new SingleDepositorVault();
    }

    ////////////////////////////////////////////////////////////
    //                        Deposit                         //
    ////////////////////////////////////////////////////////////

    function test_deposit_success() public {
        uint256 amountA = 1e20;
        uint256 amountB = 5e19;

        tokenA.mint(users.owner, amountA);
        tokenB.mint(users.owner, amountB);

        vm.startPrank(users.owner);

        tokenA.approve(address(singleDepositorVault), amountA);
        tokenB.approve(address(singleDepositorVault), amountB);

        TokenAmount[] memory tokenAmounts = new TokenAmount[](2);
        tokenAmounts[0] = TokenAmount({ token: IERC20(address(tokenA)), amount: amountA });
        tokenAmounts[1] = TokenAmount({ token: IERC20(address(tokenB)), amount: amountB });

        vm.expectEmit(false, false, false, true, address(singleDepositorVault));
        emit ISingleDepositorVault.Deposited(users.owner, tokenAmounts);
        singleDepositorVault.deposit(tokenAmounts);
        vm.snapshotGasLastCall("deposit - success");

        assertEq(tokenA.balanceOf(address(singleDepositorVault)), amountA);
        assertEq(tokenA.balanceOf(users.owner), 0);
        assertEq(tokenB.balanceOf(address(singleDepositorVault)), amountB);
        assertEq(tokenB.balanceOf(users.owner), 0);
    }

    function test_deposit_revertsWith_unauthorized() public {
        uint256 amountA = 1e20;
        uint256 amountB = 5e19;

        tokenA.mint(users.owner, amountA);
        tokenB.mint(users.owner, amountB);

        tokenA.approve(address(singleDepositorVault), amountA);
        tokenB.approve(address(singleDepositorVault), amountB);

        TokenAmount[] memory tokenAmounts = new TokenAmount[](2);
        tokenAmounts[0] = TokenAmount({ token: IERC20(address(tokenA)), amount: amountA });
        tokenAmounts[1] = TokenAmount({ token: IERC20(address(tokenB)), amount: amountB });

        vm.expectRevert("UNAUTHORIZED");
        singleDepositorVault.deposit(tokenAmounts);
    }

    function test_fuzz_deposit_revertsWith_UnexpectedTokenAllowance(uint256 x) public {
        uint256 amountA = 1e20;
        uint256 amountB = 5e19;
        vm.assume(x > 0 && x < amountB);

        tokenA.mint(users.owner, amountA);
        tokenB.mint(users.owner, amountB);

        vm.startPrank(users.owner);

        tokenA.approve(address(singleDepositorVault), amountA);
        tokenB.approve(address(singleDepositorVault), amountB);

        TokenAmount[] memory tokenAmounts = new TokenAmount[](2);
        tokenAmounts[0] = TokenAmount({ token: IERC20(address(tokenA)), amount: amountA });
        tokenAmounts[1] = TokenAmount({ token: IERC20(address(tokenB)), amount: amountB - x });

        vm.expectRevert(abi.encodeWithSelector(ISingleDepositorVault.Aera__UnexpectedTokenAllowance.selector, x));
        singleDepositorVault.deposit(tokenAmounts);
    }

    function test_deposit_revertsWith_ERC20TransferFailed() public {
        uint256 amountA = 1e20;
        uint256 amountB = 5e19;

        tokenB.mint(users.owner, amountB);

        tokenA.approve(address(singleDepositorVault), amountA);
        tokenB.approve(address(singleDepositorVault), amountB);

        TokenAmount[] memory tokenAmounts = new TokenAmount[](2);
        tokenAmounts[0] = TokenAmount({ token: IERC20(address(tokenA)), amount: amountA });
        tokenAmounts[1] = TokenAmount({ token: IERC20(address(tokenB)), amount: amountB });

        vm.expectRevert();
        singleDepositorVault.deposit(tokenAmounts);
    }

    ////////////////////////////////////////////////////////////
    //                        Withdraw                        //
    ////////////////////////////////////////////////////////////

    function test_withdraw_success() public {
        uint256 amountA = 1e20;
        uint256 amountB = 5e19;

        tokenA.mint(address(singleDepositorVault), amountA);
        tokenB.mint(address(singleDepositorVault), amountB);

        vm.prank(users.owner);

        TokenAmount[] memory tokenAmounts = new TokenAmount[](2);
        tokenAmounts[0] = TokenAmount({ token: IERC20(address(tokenA)), amount: amountA });
        tokenAmounts[1] = TokenAmount({ token: IERC20(address(tokenB)), amount: amountB });

        vm.expectEmit(false, false, false, true, address(singleDepositorVault));
        emit ISingleDepositorVault.Withdrawn(users.owner, tokenAmounts);
        singleDepositorVault.withdraw(tokenAmounts);
        vm.snapshotGasLastCall("withdraw - success");
        assertEq(tokenA.balanceOf(address(singleDepositorVault)), 0);
        assertEq(tokenA.balanceOf(users.owner), amountA);
        assertEq(tokenB.balanceOf(address(singleDepositorVault)), 0);
        assertEq(tokenB.balanceOf(users.owner), amountB);
    }

    function test_withdraw_revertsWith_unauthorized() public {
        uint256 amountA = 1e20;
        uint256 amountB = 5e19;

        tokenA.mint(address(singleDepositorVault), amountA);
        tokenB.mint(address(singleDepositorVault), amountB);

        TokenAmount[] memory tokenAmounts = new TokenAmount[](2);
        tokenAmounts[0] = TokenAmount({ token: IERC20(address(tokenA)), amount: amountA });
        tokenAmounts[1] = TokenAmount({ token: IERC20(address(tokenB)), amount: amountB });

        vm.expectRevert("UNAUTHORIZED");
        singleDepositorVault.withdraw(tokenAmounts);
    }

    function test_withdraw_revertsWith_ERC20TransferFailed() public {
        uint256 amountA = 1e20;
        uint256 amountB = 5e19;

        tokenA.mint(address(singleDepositorVault), amountA);

        vm.prank(users.owner);

        TokenAmount[] memory tokenAmounts = new TokenAmount[](2);
        tokenAmounts[0] = TokenAmount({ token: IERC20(address(tokenA)), amount: amountA });
        tokenAmounts[1] = TokenAmount({ token: IERC20(address(tokenB)), amount: amountB });

        vm.expectRevert();
        singleDepositorVault.withdraw(tokenAmounts);
    }

    ////////////////////////////////////////////////////////////
    //                   Deposit + Withdraw                   //
    ////////////////////////////////////////////////////////////

    function test_fuzz_depositAndWithdraw_success(uint256 amountA, uint256 amountB) public {
        vm.assume(amountA < type(uint256).max && amountB < type(uint256).max);

        tokenA.mint(users.owner, amountA);
        tokenB.mint(users.owner, amountB);
        vm.startPrank(users.owner);
        tokenA.approve(address(singleDepositorVault), amountA);
        tokenB.approve(address(singleDepositorVault), amountB);

        TokenAmount[] memory tokenAmounts = new TokenAmount[](2);
        tokenAmounts[0] = TokenAmount({ token: IERC20(address(tokenA)), amount: amountA });
        tokenAmounts[1] = TokenAmount({ token: IERC20(address(tokenB)), amount: amountB });

        // Deposit
        vm.expectEmit(false, false, false, true, address(singleDepositorVault));
        emit ISingleDepositorVault.Deposited(users.owner, tokenAmounts);
        singleDepositorVault.deposit(tokenAmounts);

        assertEq(tokenA.balanceOf(address(singleDepositorVault)), amountA);
        assertEq(tokenA.balanceOf(users.owner), 0);
        assertEq(tokenB.balanceOf(address(singleDepositorVault)), amountB);
        assertEq(tokenB.balanceOf(users.owner), 0);

        // Withdraw
        vm.expectEmit(false, false, false, true, address(singleDepositorVault));
        emit ISingleDepositorVault.Withdrawn(users.owner, tokenAmounts);
        singleDepositorVault.withdraw(tokenAmounts);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(singleDepositorVault)), 0);
        assertEq(tokenA.balanceOf(users.owner), amountA);
        assertEq(tokenB.balanceOf(address(singleDepositorVault)), 0);
        assertEq(tokenB.balanceOf(users.owner), amountB);
    }

    ////////////////////////////////////////////////////////////
    //                        Execute                         //
    ////////////////////////////////////////////////////////////

    function test_execute_success_single(uint256 value, bytes memory data) public {
        address target = address(0xabcd);
        vm.deal(address(singleDepositorVault), value);
        vm.mockCall(target, value, data, hex"c0de");

        OperationPayable[] memory operations = _createOperation(target, value, data);
        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true, address(singleDepositorVault));
        emit ISingleDepositorVault.Executed(users.owner, operations);
        singleDepositorVault.execute(operations);
        vm.snapshotGasLastCall("execute - success");
    }

    function test_execute_success_multiple() public {
        uint256 amount = 1e20;
        tokenA.mint(address(singleDepositorVault), amount);

        ERC4626Mock erc4626 = new ERC4626Mock(address(tokenA));

        OperationPayable[] memory operations = new OperationPayable[](2);
        operations[0] = OperationPayable({
            target: address(tokenA),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(erc4626), amount),
            value: 0
        });
        operations[1] = OperationPayable({
            target: address(erc4626),
            data: abi.encodeWithSelector(IERC4626.deposit.selector, amount, address(singleDepositorVault)),
            value: 0
        });

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true, address(singleDepositorVault));
        emit ISingleDepositorVault.Executed(users.owner, operations);
        singleDepositorVault.execute(operations);
        vm.snapshotGasLastCall("execute - success - multiple");
        assertEq(tokenA.balanceOf(address(singleDepositorVault)), 0);
        assertEq(tokenA.balanceOf(address(erc4626)), amount);
        assertEq(erc4626.balanceOf(address(singleDepositorVault)), amount);
    }

    function test_execute_success_multiple_sendValue() public {
        uint256 amount = 1e20;
        address target1 = address(0xabcd);
        address target2 = address(0x1234);

        deal(address(singleDepositorVault), 2 * amount);

        OperationPayable[] memory operations = new OperationPayable[](2);
        operations[0] = OperationPayable({ target: target1, data: "", value: amount });
        operations[1] = OperationPayable({ target: target2, data: "", value: amount });

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, true, address(singleDepositorVault));
        emit ISingleDepositorVault.Executed(users.owner, operations);
        singleDepositorVault.execute(operations);
        vm.snapshotGasLastCall("execute - success - multiple - send value");

        assertEq(target1.balance, amount);
        assertEq(target2.balance, amount);
        assertEq(address(singleDepositorVault).balance, 0);
    }

    function test_execute_revertsWith_unauthorized(uint256 value, bytes memory data) public {
        address target = address(0xabcd);
        vm.deal(address(singleDepositorVault), value);
        vm.mockCall(target, value, data, hex"c0de");

        vm.expectRevert("UNAUTHORIZED");
        singleDepositorVault.execute(_createOperation(target, value, data));
    }

    function test_execute_revertsWith_ExecutionFailed(uint256 value, bytes memory data) public {
        address target = address(0xabcd);
        vm.deal(address(singleDepositorVault), value);
        vm.mockCallRevert(target, value, data, hex"c0de");

        vm.expectRevert(abi.encodeWithSelector(ISingleDepositorVault.Aera__ExecutionFailed.selector, 0, hex"c0de"));
        vm.prank(users.owner);
        singleDepositorVault.execute(_createOperation(target, value, data));
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

    function test_claimFees_revertsWith_with_NoFeesToClaim() public {
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

    function test_claimFees_revertsWith_ERC20TransferFailed_Protocol() public {
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

    function _createOperation(address target, uint256 value, bytes memory data)
        internal
        pure
        returns (OperationPayable[] memory operations)
    {
        operations = new OperationPayable[](1);
        operations[0] = OperationPayable({ target: target, value: value, data: data });
    }
}
