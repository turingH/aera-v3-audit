// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { IERC4626 } from "@oz/interfaces/IERC4626.sol";
import { Authority } from "@solmate/auth/Auth.sol";

import { IMaplePool } from "src/dependencies/maple-finance/IMaplePool.sol";
import { IWithdrawalManagerLike } from "src/dependencies/maple-finance/IWithdrawalManagerLike.sol";

import { BaseVault } from "src/core/BaseVault.sol";
import { BaseVaultParameters, Clipboard, Operation } from "src/core/Types.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { MockBaseVaultFactory } from "test/core/mocks/MockBaseVaultFactory.sol";
import { BaseMerkleTree } from "test/utils/BaseMerkleTree.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { Encoder } from "test/core/utils/Encoder.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract MapleFinanceForkTest is BaseTest, BaseMerkleTree, MockBaseVaultFactory {
    ////////////////////////////////////////////////////////
    //                     Constants                     //
    ////////////////////////////////////////////////////////

    // Mainnet addresses
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant SYRUP_USDC_POOL = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;
    address internal constant SYRUP_USDC_WITHDRAWAL_MANAGER = 0x1bc47a0Dd0FdaB96E9eF982fdf1F34DC6207cfE3;
    address internal constant SYRUP_USDC_POOL_DELEGATE = 0xEe3cBEFF9dC14EC9710A643B7624C5BEaF20BCcb;
    // random address from mainnet that has permissions to mint and redeem
    address internal constant ALLOWED_MINTER = 0x9204A92D5CD48F31C039c16206B618E1E1e47E3A;
    uint256 internal constant USDC_AMOUNT = 100e6; // 100 USDC (6 decimals)

    ////////////////////////////////////////////////////////
    //                       State                       //
    ////////////////////////////////////////////////////////

    BaseVault public vault;
    IMaplePool public syrupUsdcPool;

    ////////////////////////////////////////////////////////
    //                       Setup                       //
    ////////////////////////////////////////////////////////

    function setUp() public override(BaseTest) {
        super.setUp();

        vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), 22_687_454);

        setGuardian(users.guardian);
        setBaseVaultParameters(
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            })
        );

        deployCodeTo("BaseVault.sol", address(ALLOWED_MINTER));
        vault = BaseVault(payable(ALLOWED_MINTER));

        // Prepare Merkle leaves
        // 0. USDC -> approve(SYRUP_USDC_POOL, amount)
        leaves.push(
            MerkleHelper.getLeaf({
                target: USDC,
                selector: IERC20.approve.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0), // spender param
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(SYRUP_USDC_POOL)
            })
        );

        // 1. SYRUP_USDC_POOL -> mint(uint256 shares, address receiver)
        leaves.push(
            MerkleHelper.getLeaf({
                target: SYRUP_USDC_POOL,
                selector: IERC4626.mint.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32), // receiver param (2nd arg)
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(address(vault))
            })
        );

        // 2. SYRUP_USDC_POOL -> redeem(uint256 shares, address receiver, address owner)
        leaves.push(
            MerkleHelper.getLeaf({
                target: SYRUP_USDC_POOL,
                selector: IERC4626.redeem.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32, 64), // receiver + owner (2nd + 3rd args)
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(address(vault), address(vault))
            })
        );

        vm.startPrank(users.owner);
        vault.acceptOwnership();
        vault.setGuardianRoot(users.guardian, MerkleHelper.getRoot(leaves));
        vm.stopPrank();

        syrupUsdcPool = IMaplePool(SYRUP_USDC_POOL);

        vm.label(USDC, "USDC");
        vm.label(SYRUP_USDC_POOL, "SYRUP_USDC_POOL");
        vm.label(SYRUP_USDC_WITHDRAWAL_MANAGER, "SYRUP_USDC_WITHDRAWAL_MANAGER");
        vm.label(SYRUP_USDC_POOL_DELEGATE, "SYRUP_USDC_POOL_DELEGATE");
        vm.label(address(vault), "VAULT");
    }

    ////////////////////////////////////////////////////////
    //                 mint & redeem flow                //
    ////////////////////////////////////////////////////////

    function test_fork_mintAndRedeem_success() public {
        // ───────── Before mint assertions ─────────
        uint256 usdcBalanceBeforeMint = IERC20(USDC).balanceOf(address(vault));
        uint256 syrupUsdcBalanceBeforeMint = syrupUsdcPool.balanceOf(address(vault));

        deal(USDC, address(vault), USDC_AMOUNT);

        // Determine shares required for given USDC amount
        uint256 sharesToMint = syrupUsdcPool.convertToShares(USDC_AMOUNT);
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        //////////////////////
        //       Mint       //
        //////////////////////

        Operation[] memory mintOps = new Operation[](2);
        // 0. Approve USDC for the pool
        mintOps[0] = Operation({
            target: USDC,
            data: abi.encodeWithSelector(IERC20.approve.selector, SYRUP_USDC_POOL, USDC_AMOUNT),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });

        // 1. Mint shares to the vault
        mintOps[1] = Operation({
            target: SYRUP_USDC_POOL,
            data: abi.encodeWithSelector(IERC4626.mint.selector, sharesToMint, address(vault)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        // Guardian submits the batch
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(mintOps));

        // ───────── After mint assertions ─────────
        uint256 usdcBalanceAfterMint = IERC20(USDC).balanceOf(address(vault));
        uint256 syrupUsdcBalanceAfterMint = syrupUsdcPool.balanceOf(address(vault));

        assertEq(usdcBalanceBeforeMint - usdcBalanceAfterMint, 0, "USDC should be spent");
        assertEq(syrupUsdcBalanceAfterMint - syrupUsdcBalanceBeforeMint, sharesToMint, "shares balance mismatch");

        ////////////////////////
        //       Redeem       //
        ////////////////////////

        // Redeems have to go through a queue and be handled by multiple actors, so we simulate that here

        // 0. Allow the vault to manually redeem shares.
        vm.prank(SYRUP_USDC_POOL_DELEGATE);
        IWithdrawalManagerLike(SYRUP_USDC_WITHDRAWAL_MANAGER).setManualWithdrawal(address(vault), true);

        // 1. vault queues redemption
        vm.prank(address(vault));
        syrupUsdcPool.requestRedeem(sharesToMint, address(vault));

        // 2. PD processes queue to unlock shares
        vm.prank(SYRUP_USDC_POOL_DELEGATE);
        IWithdrawalManagerLike(SYRUP_USDC_WITHDRAWAL_MANAGER).processRedemptions(sharesToMint);

        // Query how many shares became available after processing. Not all will be available immediately.
        uint256 unlockedShares =
            IWithdrawalManagerLike(SYRUP_USDC_WITHDRAWAL_MANAGER).manualSharesAvailable(address(vault));
        assertGt(unlockedShares, 0, "No shares unlocked");

        Operation[] memory redeemOps = new Operation[](1);
        // 1. vault redeems shares
        redeemOps[0] = Operation({
            target: SYRUP_USDC_POOL,
            data: abi.encodeWithSelector(IERC4626.redeem.selector, unlockedShares, address(vault), address(vault)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32, 64),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        uint256 syrupUsdcBalanceAfterRedeem = syrupUsdcPool.balanceOf(address(vault));

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(redeemOps));

        // ───────── Final assertions ─────────
        uint256 finalUsdc = IERC20(USDC).balanceOf(address(vault));
        assertGt(finalUsdc, usdcBalanceAfterMint, "Vault did not receive any new USDC through redeem()");
        assertGt(syrupUsdcBalanceAfterMint, syrupUsdcBalanceAfterRedeem + unlockedShares, "No syrupUSDC was burned");
    }
}
