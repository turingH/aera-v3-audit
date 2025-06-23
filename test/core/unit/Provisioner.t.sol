// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { Authority } from "@solmate/auth/Auth.sol";

import { Provisioner } from "src/core/Provisioner.sol";

import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { Request, RequestType, TokenDetails } from "src/core/Types.sol";

import { Math } from "@oz/utils/math/Math.sol";
import { MAX_SECONDS_TO_DEADLINE, MIN_DEPOSIT_MULTIPLIER, ONE_IN_BPS, ONE_UNIT } from "src/core/Constants.sol";
import { IPriceAndFeeCalculator } from "src/core/interfaces/IPriceAndFeeCalculator.sol";
import { IProvisioner } from "src/core/interfaces/IProvisioner.sol";
import { MockMultiDepositorVault } from "test/core/mocks/MockMultiDepositorVault.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract ProvisionerTest is BaseTest {
    Provisioner internal provisioner;
    IERC20 internal token;
    MockMultiDepositorVault internal multiDepositorVault;

    address internal immutable PRICE_FEE_CALCULATOR = makeAddr("PRICE_FEE_CALCULATOR");

    uint256 internal constant DEPOSIT_CAP = 100_000 ether;
    uint256 internal constant DEPOSIT_REFUND_TIMEOUT = 2 days;
    uint256 internal constant TOTAL_SUPPLY = 69_000 ether;
    uint256 internal constant TOTAL_ASSETS = 71_000 ether;

    uint256 internal constant ALICE_TOKEN_BALANCE = 100_000 ether;
    uint256 internal constant UNIT_PRICE_AGE = 1 minutes;

    uint16 internal constant DEPOSIT_MULTIPLIER = 9900;
    uint16 internal constant REDEEM_MULTIPLIER = 9900;

    uint256 internal constant TOKENS_AMOUNT = 10_000 ether;
    uint256 internal constant UNITS_OUT = 10_000 ether;
    uint256 internal constant SOLVER_TIP = 100 ether;

    function setUp() public override {
        super.setUp();

        token = IERC20(address(new ERC20Mock()));
        vm.label(address(token), "token");

        multiDepositorVault = new MockMultiDepositorVault();

        provisioner = new Provisioner(
            IPriceAndFeeCalculator(PRICE_FEE_CALCULATOR),
            address(multiDepositorVault),
            users.owner,
            Authority(address(0))
        );

        vm.prank(users.owner);
        provisioner.setDepositDetails(DEPOSIT_CAP, DEPOSIT_REFUND_TIMEOUT);

        multiDepositorVault.mint(users.stranger, TOTAL_SUPPLY);

        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToNumeraire.selector, address(multiDepositorVault), TOTAL_SUPPLY
            ),
            abi.encode(TOTAL_ASSETS)
        );
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(IPriceAndFeeCalculator.getVaultsPriceAge.selector, address(multiDepositorVault)),
            abi.encode(UNIT_PRICE_AGE)
        );
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(IPriceAndFeeCalculator.isVaultPaused.selector, address(multiDepositorVault)),
            abi.encode(false)
        );
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToToken.selector, address(multiDepositorVault), token, ONE_UNIT
            ),
            abi.encode(1e18)
        );

        ERC20Mock(address(token)).mint(users.alice, ALICE_TOKEN_BALANCE);

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        );
    }

    ////////////////////////////////////////////////////////////
    //                       deployment                       //
    ////////////////////////////////////////////////////////////

    function test_deployment_success() public {
        Provisioner newProvisioner = new Provisioner(
            IPriceAndFeeCalculator(PRICE_FEE_CALCULATOR),
            address(multiDepositorVault),
            users.owner,
            Authority(address(0))
        );

        assertEq(address(newProvisioner.PRICE_FEE_CALCULATOR()), PRICE_FEE_CALCULATOR);
        assertEq(address(newProvisioner.MULTI_DEPOSITOR_VAULT()), address(multiDepositorVault));
        assertEq(newProvisioner.owner(), users.owner);
    }

    function test_deployment_revertsWith_ZeroPriceFeeCalculator() public {
        vm.expectRevert(IProvisioner.Aera__ZeroAddressPriceAndFeeCalculator.selector);
        new Provisioner(
            IPriceAndFeeCalculator(address(0)), address(multiDepositorVault), users.owner, Authority(address(0))
        );
    }

    function test_deployment_revertsWith_ZeroMultiDepositorVault() public {
        vm.expectRevert(IProvisioner.Aera__ZeroAddressMultiDepositorVault.selector);
        new Provisioner(IPriceAndFeeCalculator(PRICE_FEE_CALCULATOR), address(0), users.owner, Authority(address(0)));
    }

    ////////////////////////////////////////////////////////////
    //                   setDepositDetails                    //
    ////////////////////////////////////////////////////////////

    function test_setDepositDetails_success() public {
        vm.prank(users.owner);
        vm.expectEmit(false, false, false, true);
        emit IProvisioner.DepositDetailsUpdated(DEPOSIT_CAP, DEPOSIT_REFUND_TIMEOUT);
        provisioner.setDepositDetails(DEPOSIT_CAP, DEPOSIT_REFUND_TIMEOUT);

        assertEq(provisioner.depositCap(), DEPOSIT_CAP);
        assertEq(provisioner.depositRefundTimeout(), DEPOSIT_REFUND_TIMEOUT);
    }

    function test_setDepositDetails_revertsWith_Unauthorized() public {
        vm.prank(users.stranger);
        vm.expectRevert("UNAUTHORIZED");
        provisioner.setDepositDetails(DEPOSIT_CAP, DEPOSIT_REFUND_TIMEOUT);
    }

    function test_setDepositDetails_revertsWith_ZeroDepositCap() public {
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__DepositCapZero.selector);
        provisioner.setDepositDetails(0, DEPOSIT_REFUND_TIMEOUT);
    }

    function test_setDepositDetails_revertsWith_MaxDepositRefundTimeoutExceeded() public {
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__MaxDepositRefundTimeoutExceeded.selector);
        provisioner.setDepositDetails(DEPOSIT_CAP, 32 days);
    }

    ////////////////////////////////////////////////////////////
    //                    setTokenDetails                     //
    ////////////////////////////////////////////////////////////

    function test_setTokenDetails_success() public {
        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: false,
            asyncRedeemEnabled: true,
            syncDepositEnabled: false,
            depositMultiplier: uint16(ONE_IN_BPS - 100),
            redeemMultiplier: uint16(ONE_IN_BPS - 100)
        });
        vm.prank(users.owner);
        vm.expectEmit(false, false, false, true);
        emit IProvisioner.TokenDetailsSet(token, tokenDetails);
        provisioner.setTokenDetails(token, tokenDetails);

        (
            bool asyncDepositEnabled,
            bool asyncRedeemEnabled,
            bool syncDepositEnabled,
            uint16 depositMultiplier,
            uint16 redeemMultiplier
        ) = provisioner.tokensDetails(token);
        assertEq(asyncDepositEnabled, tokenDetails.asyncDepositEnabled);
        assertEq(asyncRedeemEnabled, tokenDetails.asyncRedeemEnabled);
        assertEq(syncDepositEnabled, tokenDetails.syncDepositEnabled);
        assertEq(depositMultiplier, tokenDetails.depositMultiplier);
        assertEq(redeemMultiplier, tokenDetails.redeemMultiplier);
    }

    function test_setTokenDetails_success_when_unsetting_tokenCantBePriced() public {
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToToken.selector, address(multiDepositorVault), token, 1e18
            ),
            abi.encode(0)
        );

        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: false,
            asyncRedeemEnabled: false,
            syncDepositEnabled: false,
            depositMultiplier: uint16(ONE_IN_BPS - 100),
            redeemMultiplier: uint16(ONE_IN_BPS - 100)
        });
        vm.prank(users.owner);
        vm.expectEmit(false, false, false, true);
        emit IProvisioner.TokenDetailsSet(token, tokenDetails);
        provisioner.setTokenDetails(token, tokenDetails);

        (
            bool asyncDepositEnabled,
            bool asyncRedeemEnabled,
            bool syncDepositEnabled,
            uint16 depositMultiplier,
            uint16 redeemMultiplier
        ) = provisioner.tokensDetails(token);
        assertEq(asyncDepositEnabled, tokenDetails.asyncDepositEnabled);
        assertEq(asyncRedeemEnabled, tokenDetails.asyncRedeemEnabled);
        assertEq(syncDepositEnabled, tokenDetails.syncDepositEnabled);
        assertEq(depositMultiplier, tokenDetails.depositMultiplier);
        assertEq(redeemMultiplier, tokenDetails.redeemMultiplier);
    }

    function test_setTokenDetails_revertsWith_Unauthorized() public {
        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: false,
            asyncRedeemEnabled: false,
            syncDepositEnabled: false,
            depositMultiplier: uint16(ONE_IN_BPS - 100),
            redeemMultiplier: uint16(ONE_IN_BPS - 100)
        });
        vm.prank(users.stranger);
        vm.expectRevert("UNAUTHORIZED");
        provisioner.setTokenDetails(token, tokenDetails);
    }

    function test_setTokenDetails_revertsWith_InvalidToken() public {
        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: true,
            asyncRedeemEnabled: true,
            syncDepositEnabled: true,
            depositMultiplier: uint16(ONE_IN_BPS),
            redeemMultiplier: uint16(ONE_IN_BPS)
        });
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__InvalidToken.selector);
        provisioner.setTokenDetails(multiDepositorVault, tokenDetails);
    }

    function test_setTokenDetails_revertsWith_DepositMultiplierTooLow() public {
        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: true,
            asyncRedeemEnabled: true,
            syncDepositEnabled: true,
            depositMultiplier: uint16(0),
            redeemMultiplier: uint16(ONE_IN_BPS)
        });
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__DepositMultiplierTooLow.selector);
        provisioner.setTokenDetails(token, tokenDetails);
    }

    function test_setTokenDetails_revertsWith_DepositMultiplierTooHigh() public {
        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: true,
            asyncRedeemEnabled: true,
            syncDepositEnabled: true,
            depositMultiplier: uint16(ONE_IN_BPS + 1),
            redeemMultiplier: uint16(ONE_IN_BPS)
        });
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__DepositMultiplierTooHigh.selector);
        provisioner.setTokenDetails(token, tokenDetails);
    }

    function test_setTokenDetails_revertsWith_RedeemMultiplierTooLow() public {
        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: true,
            asyncRedeemEnabled: true,
            syncDepositEnabled: true,
            depositMultiplier: uint16(ONE_IN_BPS),
            redeemMultiplier: uint16(0)
        });
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__RedeemMultiplierTooLow.selector);
        provisioner.setTokenDetails(token, tokenDetails);
    }

    function test_setTokenDetails_revertsWith_RedeemMultiplierTooHigh() public {
        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: true,
            asyncRedeemEnabled: true,
            syncDepositEnabled: true,
            depositMultiplier: uint16(ONE_IN_BPS),
            redeemMultiplier: uint16(ONE_IN_BPS + 1)
        });
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__RedeemMultiplierTooHigh.selector);
        provisioner.setTokenDetails(token, tokenDetails);
    }

    function test_setTokenDetails_revertsWith_TokenCantBePriced() public {
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToToken.selector, address(multiDepositorVault), token, 1e18
            ),
            abi.encode(0)
        );

        TokenDetails memory tokenDetails = TokenDetails({
            asyncDepositEnabled: true,
            asyncRedeemEnabled: true,
            syncDepositEnabled: true,
            depositMultiplier: uint16(ONE_IN_BPS),
            redeemMultiplier: uint16(ONE_IN_BPS)
        });
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__TokenCantBePriced.selector);
        provisioner.setTokenDetails(token, tokenDetails);
    }

    ////////////////////////////////////////////////////////////
    //                         deposit                        //
    ////////////////////////////////////////////////////////////

    function test_deposit_success_noPremium() public {
        uint256 unitsOut = 10_000 ether;
        _mockConvertTokenToUnits(token, TOKENS_AMOUNT, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + TOKENS_AMOUNT);

        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        bytes32 depositHash = provisioner.getDepositHash(
            users.alice, token, TOKENS_AMOUNT, unitsOut, vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.Deposited(users.alice, token, TOKENS_AMOUNT, unitsOut, depositHash);
        uint256 returnedUnitsOut = provisioner.deposit(token, TOKENS_AMOUNT, unitsOut);

        vm.snapshotGasLastCall("deposit - success no premium");

        assertEq(provisioner.syncDepositHashes(depositHash), true, "Hash should be set");
        assertEq(multiDepositorVault.balanceOf(users.alice), unitsOut, "User should get units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(returnedUnitsOut, unitsOut, "Deposit function should return the exact number of units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE - TOKENS_AMOUNT, "User should lose tokens");
        assertEq(token.balanceOf(address(multiDepositorVault)), TOKENS_AMOUNT, "Vault should get tokens");
    }

    function test_fuzz_deposit_success_noPremium(uint256 tokensIn, uint256 unitsOut) public {
        vm.assume(tokensIn > 0 && tokensIn <= DEPOSIT_CAP - TOTAL_ASSETS);
        vm.assume(unitsOut > 0 && unitsOut <= type(uint256).max - TOTAL_SUPPLY);

        _mockConvertTokenToUnits(token, tokensIn, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + tokensIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokensIn);

        bytes32 depositHash = provisioner.getDepositHash(
            users.alice, token, tokensIn, unitsOut, vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.Deposited(users.alice, token, tokensIn, unitsOut, depositHash);
        uint256 returnedUnitsOut = provisioner.deposit(token, tokensIn, unitsOut);

        assertEq(provisioner.syncDepositHashes(depositHash), true, "Hash should be set");
        assertEq(multiDepositorVault.balanceOf(users.alice), unitsOut, "User should get units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(returnedUnitsOut, unitsOut, "Deposit function should return the exact number of units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE - tokensIn, "User should lose tokens");
        assertEq(token.balanceOf(address(multiDepositorVault)), tokensIn, "Vault should get tokens");
    }

    function test_deposit_success_withPremium() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: DEPOSIT_MULTIPLIER,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        uint256 tokensAfterPremium = TOKENS_AMOUNT * DEPOSIT_MULTIPLIER / ONE_IN_BPS;
        uint256 unitsOut = 10_000 ether;
        _mockConvertTokenToUnits(token, tokensAfterPremium, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + tokensAfterPremium);

        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        bytes32 depositHash = provisioner.getDepositHash(
            users.alice, token, TOKENS_AMOUNT, unitsOut, vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.Deposited(users.alice, token, TOKENS_AMOUNT, unitsOut, depositHash);
        uint256 returnedUnitsOut = provisioner.deposit(token, TOKENS_AMOUNT, unitsOut);

        vm.snapshotGasLastCall("deposit - success with premium");

        assertEq(provisioner.syncDepositHashes(depositHash), true, "Hash should be set");
        assertEq(multiDepositorVault.balanceOf(users.alice), unitsOut, "User should get units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(returnedUnitsOut, unitsOut, "Deposit function should return the exact number of units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE - TOKENS_AMOUNT, "User should lose tokens");
        assertEq(token.balanceOf(address(multiDepositorVault)), TOKENS_AMOUNT, "Vault should get tokens");
    }

    function test_fuzz_deposit_success_withPremium(uint256 tokensIn, uint256 unitsOut, uint16 depositMultiplier)
        public
    {
        depositMultiplier = uint16(bound(depositMultiplier, MIN_DEPOSIT_MULTIPLIER, ONE_IN_BPS));
        tokensIn = bound(tokensIn, 1, DEPOSIT_CAP - TOTAL_ASSETS);
        unitsOut = bound(unitsOut, 1, type(uint256).max - TOTAL_SUPPLY);

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: depositMultiplier,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        uint256 tokensAfterPremium = tokensIn * depositMultiplier / ONE_IN_BPS;
        _mockConvertTokenToUnits(token, tokensAfterPremium, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + tokensAfterPremium);

        _approveToken(users.alice, token, address(multiDepositorVault), tokensIn);

        bytes32 depositHash = provisioner.getDepositHash(
            users.alice, token, tokensIn, unitsOut, vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.Deposited(users.alice, token, tokensIn, unitsOut, depositHash);
        uint256 returnedUnitsOut = provisioner.deposit(token, tokensIn, unitsOut);

        assertEq(provisioner.syncDepositHashes(depositHash), true, "Hash should be set");
        assertEq(multiDepositorVault.balanceOf(users.alice), unitsOut, "User should get units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(returnedUnitsOut, unitsOut, "Deposit function should return the exact number of units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE - tokensIn, "User should lose tokens");
        assertEq(token.balanceOf(address(multiDepositorVault)), tokensIn, "Vault should get tokens");
    }

    function test_deposit_revertsWith_CallerIsVault() public {
        vm.prank(address(multiDepositorVault));
        vm.expectRevert(IProvisioner.Aera__CallerIsVault.selector);
        provisioner.deposit(token, 1, 1);
    }

    function test_deposit_revertsWith_TokenAmountZero() public {
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__TokensInZero.selector);
        provisioner.deposit(token, 0, 1);
    }

    function test_deposit_revertsWith_MinUnitsAmountZero() public {
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__MinUnitsOutZero.selector);
        provisioner.deposit(token, 1, 0);
    }

    function test_deposit_revertsWith_SyncDepositDisabled() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: false,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        ); // disable sync deposit

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__SyncDepositDisabled.selector);
        provisioner.deposit(token, 1, 1);
    }

    function test_deposit_revertsWith_MinUnitsOutNotMet() public {
        uint256 minUnitsOut = UNITS_OUT + 1; // require more units than possible

        _mockConvertTokenToUnits(token, TOKENS_AMOUNT, UNITS_OUT);
        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__MinUnitsOutNotMet.selector);
        provisioner.deposit(token, TOKENS_AMOUNT, minUnitsOut);
    }

    function test_deposit_revertsWith_DepositCapExceeded() public {
        _mockConvertTokenToUnits(token, TOKENS_AMOUNT, UNITS_OUT);
        _mockConvertUnitsToNumeraire(UNITS_OUT + TOTAL_SUPPLY, DEPOSIT_CAP + 1); // exceed deposit cap
        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__DepositCapExceeded.selector);
        provisioner.deposit(token, TOKENS_AMOUNT, UNITS_OUT);
    }

    function test_deposit_revertsWith_HashCollision() public {
        _mockConvertTokenToUnits(token, TOKENS_AMOUNT, UNITS_OUT);
        _mockConvertUnitsToNumeraire(UNITS_OUT + TOTAL_SUPPLY, TOTAL_ASSETS + TOKENS_AMOUNT);
        _mockConvertUnitsToNumeraire(UNITS_OUT + UNITS_OUT + TOTAL_SUPPLY, TOTAL_ASSETS + TOKENS_AMOUNT + TOKENS_AMOUNT);
        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        // First deposit to set the hash
        vm.prank(users.alice);
        provisioner.deposit(token, TOKENS_AMOUNT, UNITS_OUT);

        // Try to deposit with same parameters
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__HashCollision.selector);
        provisioner.deposit(token, TOKENS_AMOUNT, UNITS_OUT);
    }

    function test_deposit_revertsWith_VaultPaused() public {
        vm.mockCallRevert(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertTokenToUnitsIfActive.selector,
                address(multiDepositorVault),
                token,
                TOKENS_AMOUNT
            ),
            abi.encodeWithSelector(IPriceAndFeeCalculator.Aera__VaultPaused.selector)
        );
        _mockConvertUnitsToNumeraire(UNITS_OUT + TOTAL_SUPPLY, TOTAL_ASSETS + TOKENS_AMOUNT);
        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        vm.prank(users.alice);
        vm.expectRevert();
        provisioner.deposit(token, TOKENS_AMOUNT, UNITS_OUT);
    }

    ////////////////////////////////////////////////////////////
    //                         mint                           //
    ////////////////////////////////////////////////////////////

    function test_mint_success_noPremium() public {
        uint256 units = 10_000 ether;
        uint256 tokenIn = 10_000 ether;

        _mockConvertUnitsToToken(token, units, tokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        bytes32 depositHash = provisioner.getDepositHash(
            users.alice, token, tokenIn, units, vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.Deposited(users.alice, token, tokenIn, units, depositHash);
        uint256 returnedTokenIn = provisioner.mint(token, units, tokenIn);

        vm.snapshotGasLastCall("mint - success no premium");

        assertEq(provisioner.syncDepositHashes(depositHash), true, "Hash should be set");
        assertEq(multiDepositorVault.balanceOf(users.alice), units, "User should get units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(returnedTokenIn, tokenIn, "Mint function should return the exact number of tokens");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE - tokenIn, "User should lose tokens");
        assertEq(token.balanceOf(address(multiDepositorVault)), tokenIn, "Vault should get tokens");
    }

    function test_fuzz_mint_success_noPremium(uint256 tokenIn, uint256 units) public {
        vm.assume(tokenIn > 0 && tokenIn <= DEPOSIT_CAP - TOTAL_ASSETS);
        vm.assume(units > 0 && units <= type(uint256).max - TOTAL_SUPPLY);

        _mockConvertUnitsToToken(token, units, tokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);
        bytes32 depositHash = provisioner.getDepositHash(
            users.alice, token, tokenIn, units, vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.Deposited(users.alice, token, tokenIn, units, depositHash);
        uint256 returnedTokenIn = provisioner.mint(token, units, tokenIn);

        assertEq(provisioner.syncDepositHashes(depositHash), true, "Hash should be set");
        assertEq(multiDepositorVault.balanceOf(users.alice), units, "User should get units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(returnedTokenIn, tokenIn, "Mint function should return the exact number of tokens");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE - tokenIn, "User should lose tokens");
        assertEq(token.balanceOf(address(multiDepositorVault)), tokenIn, "Vault should get tokens");
    }

    function test_mint_success_withPremium() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: DEPOSIT_MULTIPLIER,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        uint256 units = 1000 ether;
        uint256 initialTokenIn = 1000 ether;
        uint256 tokenIn = Math.mulDiv(initialTokenIn, ONE_IN_BPS, DEPOSIT_MULTIPLIER, Math.Rounding.Ceil);

        _mockConvertUnitsToToken(token, units, initialTokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        bytes32 depositHash = provisioner.getDepositHash(
            users.alice, token, tokenIn, units, vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.Deposited(users.alice, token, tokenIn, units, depositHash);
        uint256 returnedTokenIn = provisioner.mint(token, units, tokenIn);

        vm.snapshotGasLastCall("mint - success no premium");

        assertEq(provisioner.syncDepositHashes(depositHash), true, "Hash status should be true");
        assertEq(multiDepositorVault.balanceOf(users.alice), units, "User should have correct units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should have 0 units");
        assertEq(returnedTokenIn, tokenIn, "Mint function should return the exact number of tokens");
        assertEq(token.balanceOf(address(multiDepositorVault)), tokenIn, "Vault should have correct token balance");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should have 0 tokens");
        assertEq(
            token.balanceOf(address(users.alice)),
            ALICE_TOKEN_BALANCE - tokenIn,
            "User should have correct token balance"
        );
    }

    function test_fuzz_mint_success_withPremium(uint256 initialTokenIn, uint256 units, uint16 depositMultiplier)
        public
    {
        depositMultiplier = uint16(bound(depositMultiplier, MIN_DEPOSIT_MULTIPLIER, ONE_IN_BPS));
        initialTokenIn = bound(initialTokenIn, 1, (DEPOSIT_CAP - TOTAL_ASSETS) * depositMultiplier / ONE_IN_BPS);
        units = bound(units, 1, type(uint256).max - TOTAL_SUPPLY);

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: depositMultiplier,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );
        uint256 tokenIn = Math.mulDiv(initialTokenIn, ONE_IN_BPS, depositMultiplier, Math.Rounding.Ceil);
        _mockConvertUnitsToToken(token, units, initialTokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        bytes32 depositHash = provisioner.getDepositHash(
            users.alice, token, tokenIn, units, vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.Deposited(users.alice, token, tokenIn, units, depositHash);
        uint256 returnedTokenIn = provisioner.mint(token, units, tokenIn);

        assertEq(provisioner.syncDepositHashes(depositHash), true, "Hash status should be true");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should have 0 units");
        assertEq(multiDepositorVault.balanceOf(users.alice), units, "User should have correct units");
        assertEq(returnedTokenIn, tokenIn, "Mint function should return the exact number of tokens");
        assertEq(token.balanceOf(address(multiDepositorVault)), tokenIn, "Vault should have correct token balance");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should have 0 tokens");
        assertEq(
            token.balanceOf(address(users.alice)),
            ALICE_TOKEN_BALANCE - tokenIn,
            "User should have correct token balance"
        );
    }

    function test_mint_revertsWith_CallerIsVault() public {
        vm.prank(address(multiDepositorVault));
        vm.expectRevert(IProvisioner.Aera__CallerIsVault.selector);
        provisioner.mint(token, 1, 1);
    }

    function test_mint_revertsWith_UnitsAmountZero() public {
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__UnitsOutZero.selector);
        provisioner.mint(token, 0, 1);
    }

    function test_mint_revertsWith_MaxTokenInZero() public {
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__MaxTokensInZero.selector);
        provisioner.mint(token, 1, 0);
    }

    function test_mint_revertsWith_SyncDepositDisabled() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: false,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        );

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__SyncDepositDisabled.selector);
        provisioner.mint(token, 1, 1);
    }

    function test_mint_revertsWith_DepositCapExceeded() public {
        uint256 units = 10_000 ether;
        uint256 tokenIn = 10_000 ether;

        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, DEPOSIT_CAP + 1); // exceed deposit cap
        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__DepositCapExceeded.selector);
        provisioner.mint(token, units, tokenIn);
    }

    function test_mint_revertsWith_MaxTokenInExceeded() public {
        uint256 units = 10_000 ether;
        uint256 tokenIn = 10_000 ether;
        uint256 maxTokenIn = tokenIn - 1; // set max less than required

        _mockConvertUnitsToToken(token, units, tokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);
        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__MaxTokensInExceeded.selector);
        provisioner.mint(token, units, maxTokenIn);
    }

    function test_mint_revertsWith_HashCollision() public {
        uint256 units = 10_000 ether;
        uint256 tokenIn = 10_000 ether;

        _mockConvertUnitsToToken(token, units, tokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);
        _mockConvertUnitsToNumeraire(units + units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn + tokenIn);
        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        // First mint to set the hash
        vm.prank(users.alice);
        provisioner.mint(token, units, tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);
        // Try to mint with same parameters
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__HashCollision.selector);
        provisioner.mint(token, units, tokenIn);
    }

    function test_mint_revertsWith_VaultPaused() public {
        vm.mockCallRevert(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToTokenIfActive.selector,
                address(multiDepositorVault),
                token,
                UNITS_OUT
            ),
            abi.encodeWithSelector(IPriceAndFeeCalculator.Aera__VaultPaused.selector)
        );
        _mockConvertUnitsToNumeraire(UNITS_OUT + TOTAL_SUPPLY, TOTAL_ASSETS + TOKENS_AMOUNT);
        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        vm.prank(users.alice);
        vm.expectRevert();
        provisioner.mint(token, UNITS_OUT, TOKENS_AMOUNT);
    }

    ////////////////////////////////////////////////////////////
    //                     refundDeposit                      //
    ////////////////////////////////////////////////////////////

    function test_refundDeposit_success_deposited_noPremium() public {
        uint256 unitsOut = 10_000 ether;

        _mockConvertTokenToUnits(token, TOKENS_AMOUNT, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + TOKENS_AMOUNT);

        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;

        bytes32 depositHash = provisioner.getDepositHash(users.alice, token, TOKENS_AMOUNT, unitsOut, refundableUntil);

        vm.prank(users.alice);
        provisioner.deposit(token, TOKENS_AMOUNT, unitsOut);

        skip(DEPOSIT_REFUND_TIMEOUT);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DirectDepositRefunded(depositHash);
        provisioner.refundDeposit(users.alice, token, TOKENS_AMOUNT, unitsOut, refundableUntil);

        vm.snapshotGasLastCall("refundDeposit - success");

        assertEq(provisioner.syncDepositHashes(depositHash), false, "Hash should be reset");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(multiDepositorVault)), 0, "Vault should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE, "User should have correct token balance");
    }

    function test_fuzz_refundDeposit_success_deposited_noPremium(uint256 tokensIn, uint256 unitsOut) public {
        vm.assume(tokensIn > 0 && tokensIn <= DEPOSIT_CAP - TOTAL_ASSETS);
        vm.assume(unitsOut > 0 && unitsOut <= type(uint256).max - TOTAL_SUPPLY);

        _mockConvertTokenToUnits(token, tokensIn, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + tokensIn);
        _approveToken(users.alice, token, address(multiDepositorVault), tokensIn);

        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;
        bytes32 depositHash = provisioner.getDepositHash(users.alice, token, tokensIn, unitsOut, refundableUntil);

        vm.prank(users.alice);
        provisioner.deposit(token, tokensIn, unitsOut);

        skip(DEPOSIT_REFUND_TIMEOUT);
        vm.prank(users.owner);
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DirectDepositRefunded(depositHash);
        provisioner.refundDeposit(users.alice, token, tokensIn, unitsOut, refundableUntil);

        assertEq(provisioner.syncDepositHashes(depositHash), false, "Hash should be reset");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(multiDepositorVault)), 0, "Vault should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE, "User should have correct token balance");
    }

    function test_refundDeposit_success_deposited_withPremium() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: DEPOSIT_MULTIPLIER,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        uint256 tokensAfterPremium = TOKENS_AMOUNT * DEPOSIT_MULTIPLIER / ONE_IN_BPS;
        uint256 unitsOut = 10_000 ether;

        _mockConvertTokenToUnits(token, tokensAfterPremium, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + tokensAfterPremium);

        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;

        bytes32 depositHash = provisioner.getDepositHash(users.alice, token, TOKENS_AMOUNT, unitsOut, refundableUntil);

        vm.prank(users.alice);
        provisioner.deposit(token, TOKENS_AMOUNT, unitsOut);

        skip(DEPOSIT_REFUND_TIMEOUT);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DirectDepositRefunded(depositHash);
        provisioner.refundDeposit(users.alice, token, TOKENS_AMOUNT, unitsOut, refundableUntil);

        assertEq(provisioner.syncDepositHashes(depositHash), false, "Hash should be reset");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(multiDepositorVault)), 0, "Vault should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE, "User should have correct token balance");
    }

    function test_fuzz_refundDeposit_success_deposited_withPremium(
        uint256 tokensIn,
        uint256 unitsOut,
        uint16 depositMultiplier
    ) public {
        depositMultiplier = uint16(bound(depositMultiplier, MIN_DEPOSIT_MULTIPLIER, ONE_IN_BPS));
        tokensIn = bound(tokensIn, 1, DEPOSIT_CAP - TOTAL_ASSETS);
        unitsOut = bound(unitsOut, 1, type(uint256).max - TOTAL_SUPPLY);

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: depositMultiplier,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        uint256 tokensAfterPremium = tokensIn * depositMultiplier / ONE_IN_BPS;
        _mockConvertTokenToUnits(token, tokensAfterPremium, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + tokensAfterPremium);

        _approveToken(users.alice, token, address(multiDepositorVault), tokensIn);
        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;
        bytes32 depositHash = provisioner.getDepositHash(users.alice, token, tokensIn, unitsOut, refundableUntil);

        vm.prank(users.alice);
        provisioner.deposit(token, tokensIn, unitsOut);

        skip(DEPOSIT_REFUND_TIMEOUT);
        vm.prank(users.owner);
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DirectDepositRefunded(depositHash);
        provisioner.refundDeposit(users.alice, token, tokensIn, unitsOut, refundableUntil);

        assertEq(provisioner.syncDepositHashes(depositHash), false, "Hash should be reset");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(multiDepositorVault)), 0, "Vault should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE, "User should have correct token balance");
    }

    function test_refundDeposit_success_minted_noPremium() public {
        uint256 units = 10_000 ether;
        uint256 tokenIn = 10_000 ether;

        _mockConvertUnitsToToken(token, units, tokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;

        bytes32 depositHash = provisioner.getDepositHash(users.alice, token, tokenIn, units, refundableUntil);

        vm.prank(users.alice);
        provisioner.mint(token, units, tokenIn);

        skip(DEPOSIT_REFUND_TIMEOUT);

        vm.prank(users.owner);
        provisioner.refundDeposit(users.alice, token, tokenIn, units, refundableUntil);

        assertEq(provisioner.syncDepositHashes(depositHash), false, "Hash should be reset");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(multiDepositorVault)), 0, "Vault should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE, "User should have correct token balance");
    }

    function test_fuzz_refundDeposit_success_minted_noPremium(uint256 tokenIn, uint256 units) public {
        vm.assume(tokenIn > 0 && tokenIn <= DEPOSIT_CAP - TOTAL_ASSETS);
        vm.assume(units > 0 && units <= type(uint256).max - TOTAL_SUPPLY);

        _mockConvertUnitsToToken(token, units, tokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;
        bytes32 depositHash = provisioner.getDepositHash(users.alice, token, tokenIn, units, refundableUntil);

        vm.prank(users.alice);
        provisioner.mint(token, units, tokenIn);

        skip(DEPOSIT_REFUND_TIMEOUT);

        vm.prank(users.owner);
        provisioner.refundDeposit(users.alice, token, tokenIn, units, refundableUntil);

        assertEq(provisioner.syncDepositHashes(depositHash), false, "Hash should be reset");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(multiDepositorVault)), 0, "Vault should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE, "User should have correct token balance");
    }

    function test_refundDeposit_success_minted_withPremium() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: DEPOSIT_MULTIPLIER,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        uint256 units = 1000 ether;
        uint256 initialTokenIn = 1000 ether;
        uint256 tokenIn = Math.mulDiv(initialTokenIn, ONE_IN_BPS, DEPOSIT_MULTIPLIER, Math.Rounding.Ceil);

        _mockConvertUnitsToToken(token, units, initialTokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);

        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;

        bytes32 depositHash = provisioner.getDepositHash(users.alice, token, tokenIn, units, refundableUntil);

        vm.prank(users.alice);
        provisioner.mint(token, units, tokenIn);

        skip(DEPOSIT_REFUND_TIMEOUT);

        vm.prank(users.owner);
        provisioner.refundDeposit(users.alice, token, tokenIn, units, refundableUntil);

        assertEq(provisioner.syncDepositHashes(depositHash), false, "Hash should be reset");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(multiDepositorVault)), 0, "Vault should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE, "User should have correct token balance");
    }

    function test_fuzz_refundDeposit_success_minted_withPremium(
        uint256 initialTokenIn,
        uint256 units,
        uint16 depositMultiplier
    ) public {
        depositMultiplier = uint16(bound(depositMultiplier, MIN_DEPOSIT_MULTIPLIER, ONE_IN_BPS));
        initialTokenIn = bound(initialTokenIn, 1, (DEPOSIT_CAP - TOTAL_ASSETS) * depositMultiplier / ONE_IN_BPS);
        units = bound(units, 1, type(uint256).max - TOTAL_SUPPLY);

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: depositMultiplier,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        uint256 tokenIn = Math.mulDiv(initialTokenIn, ONE_IN_BPS, depositMultiplier, Math.Rounding.Ceil);

        _mockConvertUnitsToToken(token, units, initialTokenIn);
        _mockConvertUnitsToNumeraire(units + TOTAL_SUPPLY, TOTAL_ASSETS + tokenIn);

        _approveToken(users.alice, token, address(multiDepositorVault), tokenIn);
        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;
        bytes32 depositHash = provisioner.getDepositHash(users.alice, token, tokenIn, units, refundableUntil);

        vm.prank(users.alice);
        provisioner.mint(token, units, tokenIn);

        skip(DEPOSIT_REFUND_TIMEOUT);

        vm.prank(users.owner);
        provisioner.refundDeposit(users.alice, token, tokenIn, units, refundableUntil);

        assertEq(provisioner.syncDepositHashes(depositHash), false, "Hash should be reset");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(multiDepositorVault)), 0, "Vault should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE, "User should have correct token balance");
    }

    function test_refundDeposit_revertsWith_RefundPeriodExpired() public {
        uint256 unitsOut = 10_000 ether;
        uint256 refundableUntil = vm.getBlockTimestamp();

        _mockConvertTokenToUnits(token, TOKENS_AMOUNT, unitsOut);
        _mockConvertUnitsToNumeraire(unitsOut + TOTAL_SUPPLY, TOTAL_ASSETS + TOKENS_AMOUNT);
        _approveToken(users.alice, token, address(multiDepositorVault), TOKENS_AMOUNT);

        // Make the deposit
        vm.prank(users.alice);
        provisioner.deposit(token, TOKENS_AMOUNT, unitsOut);

        // Move time past refundableUntil
        vm.warp(refundableUntil + 1);

        // Try to refund after period expired
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__RefundPeriodExpired.selector);
        provisioner.refundDeposit(users.alice, token, TOKENS_AMOUNT, unitsOut, refundableUntil);
    }

    function test_refundDeposit_revertsWith_DepositHashNotFound() public {
        uint256 unitsOut = 10_000 ether;

        // Try to refund a deposit that was never made
        vm.prank(users.owner);
        vm.expectRevert(IProvisioner.Aera__DepositHashNotFound.selector);
        provisioner.refundDeposit(users.alice, token, TOKENS_AMOUNT, unitsOut, vm.getBlockTimestamp());
    }

    ////////////////////////////////////////////////////////////
    //                     requestDeposit                     //
    ////////////////////////////////////////////////////////////

    function test_requestDeposit_success() public {
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        _approveToken(users.alice, token, address(provisioner), TOKENS_AMOUNT);

        bytes32 depositHash = provisioner.getRequestHash(
            token,
            Request({
                requestType: RequestType.DEPOSIT_AUTO_PRICE,
                user: users.alice,
                tokens: TOKENS_AMOUNT,
                units: UNITS_OUT,
                solverTip: SOLVER_TIP,
                deadline: deadline,
                maxPriceAge: UNIT_PRICE_AGE
            })
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.DepositRequested(
            users.alice, token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false, depositHash
        );
        provisioner.requestDeposit(token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);

        vm.snapshotGasLastCall("requestDeposit - success");

        assertEq(provisioner.asyncDepositHashes(depositHash), true, "Hash should be set");
        assertEq(
            token.balanceOf(address(users.alice)),
            ALICE_TOKEN_BALANCE - TOKENS_AMOUNT,
            "User should have correct token balance"
        );
        assertEq(token.balanceOf(address(provisioner)), TOKENS_AMOUNT, "Provisioner should have correct token balance");
    }

    function test_fuzz_requestDeposit_success(
        uint256 tokensIn,
        uint256 minUnitsOut,
        uint256 solverTip,
        uint256 maxPriceAge,
        bool isFixedPrice
    ) public {
        vm.assume(tokensIn > 0 && tokensIn <= ALICE_TOKEN_BALANCE);
        vm.assume(minUnitsOut > 0);
        vm.assume(solverTip == 0 || !isFixedPrice);

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        _approveToken(users.alice, token, address(provisioner), tokensIn);
        RequestType requestType = isFixedPrice ? RequestType.DEPOSIT_FIXED_PRICE : RequestType.DEPOSIT_AUTO_PRICE;
        bytes32 depositHash = provisioner.getRequestHash(
            token,
            Request({
                requestType: requestType,
                user: users.alice,
                tokens: tokensIn,
                units: minUnitsOut,
                solverTip: solverTip,
                deadline: deadline,
                maxPriceAge: maxPriceAge
            })
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.DepositRequested(
            users.alice, token, tokensIn, minUnitsOut, solverTip, deadline, maxPriceAge, isFixedPrice, depositHash
        );
        provisioner.requestDeposit(token, tokensIn, minUnitsOut, solverTip, deadline, maxPriceAge, isFixedPrice);

        assertEq(provisioner.asyncDepositHashes(depositHash), true, "Hash should be set");
        assertEq(
            token.balanceOf(address(users.alice)),
            ALICE_TOKEN_BALANCE - tokensIn,
            "User should have correct token balance"
        );
        assertEq(token.balanceOf(address(provisioner)), tokensIn, "Provisioner should have correct token balance");
    }

    function test_requestDeposit_revertsWith_CallerIsVault() public {
        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        vm.prank(address(multiDepositorVault));
        vm.expectRevert(IProvisioner.Aera__CallerIsVault.selector);
        provisioner.requestDeposit(token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestDeposit_revertsWith_TokenAmountZero() public {
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__TokensInZero.selector);
        provisioner.requestDeposit(token, 0, UNITS_OUT, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestDeposit_revertsWith_MinUnitsOutZero() public {
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__MinUnitsOutZero.selector);
        provisioner.requestDeposit(token, TOKENS_AMOUNT, 0, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestDeposit_revertsWith_DeadlineInPast() public {
        _approveToken(users.alice, token, address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__DeadlineInPast.selector);
        provisioner.requestDeposit(
            token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, vm.getBlockTimestamp(), UNIT_PRICE_AGE, false
        );
    }

    function test_requestDeposit_revertsWith_DeadlineTooFarInFuture() public {
        _approveToken(users.alice, token, address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__DeadlineTooFarInFuture.selector);
        provisioner.requestDeposit(
            token,
            TOKENS_AMOUNT,
            UNITS_OUT,
            SOLVER_TIP,
            vm.getBlockTimestamp() + MAX_SECONDS_TO_DEADLINE + 1,
            UNIT_PRICE_AGE,
            false
        );
    }

    function test_requestDeposit_revertsWith_AsyncDepositDisabled() public {
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: false,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: DEPOSIT_MULTIPLIER,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__AsyncDepositDisabled.selector);
        provisioner.requestDeposit(token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestDeposit_revertsWith_HashCollision() public {
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        _approveToken(users.alice, token, address(provisioner), TOKENS_AMOUNT * 2); // Double approval for
            // two attempts

        // First request
        vm.prank(users.alice);
        provisioner.requestDeposit(token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);

        // Try same request again
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__HashCollision.selector);
        provisioner.requestDeposit(token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestDeposit_revertsWith_PriceAndFeeCalculatorVaultPaused() public {
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(IPriceAndFeeCalculator.isVaultPaused.selector, address(multiDepositorVault)),
            abi.encode(true)
        );

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__PriceAndFeeCalculatorVaultPaused.selector);
        provisioner.requestDeposit(
            token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, vm.getBlockTimestamp() + 1 days, UNIT_PRICE_AGE, false
        );
    }

    function test_requestDeposit_revertsWith_FixedPriceSolverTipNotAllowed() public {
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__FixedPriceSolverTipNotAllowed.selector);
        provisioner.requestDeposit(
            token, TOKENS_AMOUNT, UNITS_OUT, SOLVER_TIP, vm.getBlockTimestamp() + 1 days, UNIT_PRICE_AGE, true
        );
    }

    ////////////////////////////////////////////////////////////
    //                     requestRedeem                      //
    ////////////////////////////////////////////////////////////

    function test_requestRedeem_success() public {
        uint256 minTokenOut = 10_000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        bytes32 redeemHash = provisioner.getRequestHash(
            token,
            Request({
                requestType: RequestType.REDEEM_AUTO_PRICE,
                user: users.alice,
                tokens: minTokenOut,
                units: UNITS_OUT,
                solverTip: SOLVER_TIP,
                deadline: deadline,
                maxPriceAge: UNIT_PRICE_AGE
            })
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.RedeemRequested(
            users.alice, token, minTokenOut, UNITS_OUT, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false, redeemHash
        );
        provisioner.requestRedeem(token, UNITS_OUT, minTokenOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);

        vm.snapshotGasLastCall("requestRedeem - success");

        assertEq(provisioner.asyncRedeemHashes(redeemHash), true, "Hash should be set");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), UNITS_OUT, "Vault should have correct units");
    }

    function test_fuzz_requestRedeem_success(
        uint256 unitsIn,
        uint256 minTokensOut,
        uint256 solverTip,
        uint256 maxPriceAge,
        bool isFixedPrice
    ) public {
        vm.assume(minTokensOut > 0);
        vm.assume(unitsIn > 0 && unitsIn < TOTAL_SUPPLY);
        vm.assume(solverTip == 0 || !isFixedPrice);

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        multiDepositorVault.mint(users.alice, unitsIn);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), unitsIn);
        RequestType requestType = isFixedPrice ? RequestType.REDEEM_FIXED_PRICE : RequestType.REDEEM_AUTO_PRICE;
        bytes32 redeemHash = provisioner.getRequestHash(
            token,
            Request({
                requestType: requestType,
                user: users.alice,
                tokens: minTokensOut,
                units: unitsIn,
                solverTip: solverTip,
                deadline: deadline,
                maxPriceAge: maxPriceAge
            })
        );

        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit IProvisioner.RedeemRequested(
            users.alice, token, minTokensOut, unitsIn, solverTip, deadline, maxPriceAge, isFixedPrice, redeemHash
        );
        provisioner.requestRedeem(token, unitsIn, minTokensOut, solverTip, deadline, maxPriceAge, isFixedPrice);

        assertEq(provisioner.asyncRedeemHashes(redeemHash), true, "Hash should be set");
        assertEq(multiDepositorVault.balanceOf(users.alice), 0, "User should get 0 units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), unitsIn, "Vault should have correct units");
    }

    function test_requestRedeem_revertsWith_CallerIsVault() public {
        uint256 minTokenOut = 10_000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        vm.prank(address(multiDepositorVault));
        vm.expectRevert(IProvisioner.Aera__CallerIsVault.selector);
        provisioner.requestRedeem(token, UNITS_OUT, minTokenOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestRedeem_revertsWith_UnitsAmountZero() public {
        uint256 minTokenOut = 10_000 ether;
        uint256 deadline = 1 days;

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__UnitsInZero.selector);
        provisioner.requestRedeem(token, 0, minTokenOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestRedeem_revertsWith_MinTokenOutZero() public {
        uint256 deadline = 1 days;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__MinTokenOutZero.selector);
        provisioner.requestRedeem(token, UNITS_OUT, 0, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestRedeem_revertsWith_DeadlineInPast() public {
        uint256 minTokenOut = 10_000 ether;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__DeadlineInPast.selector);
        provisioner.requestRedeem(token, UNITS_OUT, minTokenOut, SOLVER_TIP, 0, UNIT_PRICE_AGE, false);
    }

    function test_requestRedeem_revertsWith_DeadlineTooFarInFuture() public {
        uint256 minTokenOut = 10_000 ether;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__DeadlineTooFarInFuture.selector);
        provisioner.requestRedeem(
            token,
            UNITS_OUT,
            minTokenOut,
            SOLVER_TIP,
            vm.getBlockTimestamp() + MAX_SECONDS_TO_DEADLINE + 1,
            UNIT_PRICE_AGE,
            false
        );
    }

    function test_requestRedeem_revertsWith_AsyncRedeemDisabled() public {
        uint256 minTokenOut = 10_000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: false,
                syncDepositEnabled: true,
                depositMultiplier: DEPOSIT_MULTIPLIER,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__AsyncRedeemDisabled.selector);
        provisioner.requestRedeem(token, UNITS_OUT, minTokenOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestRedeem_revertsWith_HashCollision() public {
        uint256 minTokenOut = 10_000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        multiDepositorVault.mint(users.alice, UNITS_OUT * 2);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT * 2);

        // First request
        vm.prank(users.alice);
        provisioner.requestRedeem(token, UNITS_OUT, minTokenOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);

        // Try same request again
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__HashCollision.selector);
        provisioner.requestRedeem(token, UNITS_OUT, minTokenOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false);
    }

    function test_requestRedeem_revertsWith_PriceAndFeeCalculatorVaultPaused() public {
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(IPriceAndFeeCalculator.isVaultPaused.selector, address(multiDepositorVault)),
            abi.encode(true)
        );

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__PriceAndFeeCalculatorVaultPaused.selector);
        provisioner.requestRedeem(
            token, UNITS_OUT, TOKENS_AMOUNT, SOLVER_TIP, vm.getBlockTimestamp() + 1 days, UNIT_PRICE_AGE, false
        );
    }

    function test_requestRedeem_revertsWith_FixedPriceSolverTipNotAllowed() public {
        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__FixedPriceSolverTipNotAllowed.selector);
        provisioner.requestRedeem(
            token, UNITS_OUT, TOKENS_AMOUNT, SOLVER_TIP, vm.getBlockTimestamp() + 1 days, UNIT_PRICE_AGE, true
        );
    }

    ////////////////////////////////////////////////////////////
    //                     refundRequest                      //
    ////////////////////////////////////////////////////////////

    function test_refundRequest_success_deposit() public {
        uint256 minUnitsOut = 9000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        // User approves TOKENS_AMOUNT for the deposit request
        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        // Make deposit request
        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false
        );

        Request memory request = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        vm.warp(deadline + 1);

        bytes32 depositHash = _getRequestHash(IERC20(address(token)), request);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DepositRefunded(depositHash);
        provisioner.refundRequest(IERC20(address(token)), request);

        assertEq(provisioner.asyncDepositHashes(depositHash), false, "Hash should be unset after refund");
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE, "Tokens should be refunded");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
    }

    function test_fuzz_refundRequest_success_deposit(
        uint256 tokensIn,
        uint256 minUnitsOut,
        uint256 solverTip,
        uint256 maxPriceAge,
        bool isFixedPrice
    ) public {
        vm.assume(tokensIn > 0 && tokensIn <= ALICE_TOKEN_BALANCE);
        vm.assume(minUnitsOut > 0);
        vm.assume(solverTip == 0 || !isFixedPrice);

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        // User approves TOKENS_AMOUNT for the deposit request
        _approveToken(users.alice, IERC20(address(token)), address(provisioner), tokensIn);

        // Make deposit request
        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), tokensIn, minUnitsOut, solverTip, deadline, maxPriceAge, isFixedPrice
        );
        RequestType requestType = isFixedPrice ? RequestType.DEPOSIT_FIXED_PRICE : RequestType.DEPOSIT_AUTO_PRICE;
        Request memory request = Request({
            requestType: requestType,
            user: users.alice,
            tokens: tokensIn,
            units: minUnitsOut,
            solverTip: solverTip,
            deadline: deadline,
            maxPriceAge: maxPriceAge
        });

        vm.warp(deadline + 1);

        bytes32 depositHash = _getRequestHash(IERC20(address(token)), request);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DepositRefunded(depositHash);
        provisioner.refundRequest(IERC20(address(token)), request);

        assertEq(provisioner.asyncDepositHashes(depositHash), false, "Hash should be unset after refund");
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE, "Tokens should be refunded");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 tokens");
    }

    function test_refundRequest_success_redeem() public {
        uint256 minTokenOut = 9000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        // Make redeem request
        vm.prank(users.alice);
        provisioner.requestRedeem(
            IERC20(address(token)), UNITS_OUT, minTokenOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false
        );

        // Create request object for refund
        Request memory request = Request({
            requestType: RequestType.REDEEM_AUTO_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        // Fast forward past deadline
        vm.warp(deadline + 1);

        bytes32 redeemHash = _getRequestHash(IERC20(address(token)), request);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.RedeemRefunded(redeemHash);
        provisioner.refundRequest(IERC20(address(token)), request);

        assertEq(provisioner.asyncRedeemHashes(redeemHash), false, "Hash should be unset after refund");
        assertEq(multiDepositorVault.balanceOf(users.alice), UNITS_OUT, "User should get units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
    }

    function test_fuzz_refundRequest_success_redeem(
        uint256 unitsIn,
        uint256 minTokensOut,
        uint256 solverTip,
        uint256 maxPriceAge,
        bool isFixedPrice
    ) public {
        vm.assume(minTokensOut > 0);
        vm.assume(unitsIn > 0 && unitsIn < TOTAL_SUPPLY);
        vm.assume(solverTip == 0 || !isFixedPrice);

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        multiDepositorVault.mint(users.alice, unitsIn);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), unitsIn);

        // Make redeem request
        vm.prank(users.alice);
        provisioner.requestRedeem(
            IERC20(address(token)), unitsIn, minTokensOut, solverTip, deadline, maxPriceAge, isFixedPrice
        );
        RequestType requestType = isFixedPrice ? RequestType.REDEEM_FIXED_PRICE : RequestType.REDEEM_AUTO_PRICE;
        // Create request object for refund
        Request memory request = Request({
            requestType: requestType,
            user: users.alice,
            tokens: minTokensOut,
            units: unitsIn,
            solverTip: solverTip,
            deadline: deadline,
            maxPriceAge: maxPriceAge
        });

        // Fast forward past deadline
        vm.warp(deadline + 1);

        bytes32 redeemHash = _getRequestHash(IERC20(address(token)), request);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.RedeemRefunded(redeemHash);
        provisioner.refundRequest(IERC20(address(token)), request);

        assertEq(provisioner.asyncRedeemHashes(redeemHash), false, "Hash should be unset after refund");
        assertEq(multiDepositorVault.balanceOf(users.alice), unitsIn, "User should get units");
        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
    }

    function test_refundRequest_success_authorizedCanRefundBeforeDeadline() public {
        uint256 minUnitsOut = 9000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        // User approves tokens for the deposit request
        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        // Make deposit request
        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false
        );

        // Create request object for refund
        Request memory request = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        // Still before deadline
        vm.warp(deadline - 1);

        // Owner can refund before deadline
        bytes32 depositHash = _getRequestHash(IERC20(address(token)), request);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DepositRefunded(depositHash);
        vm.prank(users.owner);
        provisioner.refundRequest(IERC20(address(token)), request);

        assertEq(provisioner.asyncDepositHashes(depositHash), false, "Hash should be unset after refund");
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE, "Tokens should be refunded");
        assertEq(token.balanceOf(address(provisioner)), 0, "Provisioner should get 0 units");
    }

    function test_refundRequest_revertsWith_DeadlineInFutureAndUnauthorized() public {
        uint256 minUnitsOut = 9000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        // User approves tokens for the deposit request
        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        // Make deposit request
        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false
        );

        // Create request object for refund
        Request memory request = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        // Still before deadline
        vm.warp(deadline - 1);

        // Try to refund before deadline
        vm.expectRevert(IProvisioner.Aera__DeadlineInFutureAndUnauthorized.selector);
        provisioner.refundRequest(IERC20(address(token)), request);
    }

    function test_refundRequest_deposit_revertsWith_HashNotFound() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        // Create request object for a request that was never made
        Request memory request = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        // Fast forward past deadline
        vm.warp(deadline + 1);

        // Try to refund a request that was never made
        vm.expectRevert(IProvisioner.Aera__HashNotFound.selector);
        provisioner.refundRequest(IERC20(address(token)), request);
    }

    function test_refundRequest_redeem_revertsWith_HashNotFound() public {
        uint256 minTokenOut = 9000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        // Create request object for refund that was never made
        Request memory request = Request({
            requestType: RequestType.REDEEM_AUTO_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        // Fast forward past deadline
        vm.warp(deadline + 1);

        // Try to refund a request that was never made
        vm.expectRevert(IProvisioner.Aera__HashNotFound.selector);
        provisioner.refundRequest(IERC20(address(token)), request);
    }

    ////////////////////////////////////////////////////////////
    //                   solveRequestsVault                   //
    ////////////////////////////////////////////////////////////

    function test_solveRequestsVault_success_all_solvable_noPremium() public {
        Request memory deposit1 = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            tokens: TOKENS_AMOUNT,
            units: 9000 ether,
            solverTip: 100 ether,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory deposit2 = _makeRequest({
            user: users.bob,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: 5000 ether,
            units: 4500 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory redeem1 = _makeRequest({
            user: users.charlie,
            requestType: RequestType.REDEEM_AUTO_PRICE,
            tokens: 3300 ether,
            units: 3000 ether,
            solverTip: 30 ether,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory redeem2 = _makeRequest({
            user: users.dan,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: 2200 ether,
            units: 2000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 totalSupplyOnDeposit1 = TOTAL_SUPPLY + deposit1.units + redeem1.units + redeem2.units;
        uint256 totalAssetsOnDeposit1 = TOTAL_ASSETS + deposit1.tokens - deposit1.solverTip;
        uint256 totalSupplyOnDeposit2 = totalSupplyOnDeposit1 + deposit2.units;
        uint256 totalAssetsOnDeposit2 = totalAssetsOnDeposit1 + deposit2.tokens;

        _mockConvertTokenToUnits(token, deposit1.tokens - deposit1.solverTip, deposit1.units);
        _mockConvertUnitsToToken(token, deposit2.units, deposit2.tokens - SOLVER_TIP);
        _mockConvertUnitsToNumeraire(totalSupplyOnDeposit1, totalSupplyOnDeposit1);
        _mockConvertUnitsToNumeraire(totalSupplyOnDeposit2, totalAssetsOnDeposit2);

        _mockConvertUnitsToToken(token, redeem1.units, redeem1.tokens + redeem1.solverTip);
        _mockConvertUnitsToToken(token, redeem2.units, redeem2.tokens + SOLVER_TIP);

        ERC20Mock(address(token)).mint(deposit2.user, deposit2.tokens);
        _approveToken(deposit1.user, token, address(provisioner), deposit1.tokens);
        _approveToken(deposit2.user, token, address(provisioner), deposit2.tokens);

        multiDepositorVault.mint(redeem1.user, redeem1.units);
        _approveToken(redeem1.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem1.units);
        multiDepositorVault.mint(redeem2.user, redeem2.units);
        _approveToken(redeem2.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem2.units);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            token, deposit1.tokens, deposit1.units, deposit1.solverTip, deposit1.deadline, deposit1.maxPriceAge, false
        );

        vm.prank(users.bob);
        provisioner.requestDeposit(
            token, deposit2.tokens, deposit2.units, deposit2.solverTip, deposit2.deadline, deposit2.maxPriceAge, true
        );

        // Make redeem requests
        vm.prank(redeem1.user);
        provisioner.requestRedeem(
            token, redeem1.units, redeem1.tokens, redeem1.solverTip, redeem1.deadline, redeem1.maxPriceAge, false
        );

        vm.prank(redeem2.user);
        provisioner.requestRedeem(
            token, redeem2.units, redeem2.tokens, redeem2.solverTip, redeem2.deadline, redeem2.maxPriceAge, true
        );

        Request[] memory requests = new Request[](4);
        requests[0] = deposit1;
        requests[1] = deposit2;
        requests[2] = redeem1;
        requests[3] = redeem2;

        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.DepositSolved(provisioner.getRequestHash(token, deposit1));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.DepositSolved(provisioner.getRequestHash(token, deposit2));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.RedeemSolved(provisioner.getRequestHash(token, redeem1));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.RedeemSolved(provisioner.getRequestHash(token, redeem2));

        vm.prank(users.owner);
        provisioner.solveRequestsVault(token, requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - all solvable - no premium");

        uint256 totalTips = deposit1.solverTip + SOLVER_TIP + redeem1.solverTip + SOLVER_TIP;
        assertFalse(provisioner.asyncDepositHashes(provisioner.getRequestHash(token, deposit1)));
        assertFalse(provisioner.asyncDepositHashes(provisioner.getRequestHash(token, deposit2)));
        assertFalse(provisioner.asyncRedeemHashes(provisioner.getRequestHash(token, redeem1)));
        assertFalse(provisioner.asyncRedeemHashes(provisioner.getRequestHash(token, redeem2)));

        assertEq(token.balanceOf(users.owner), totalTips);
        assertEq(
            token.balanceOf(address(multiDepositorVault)),
            deposit1.tokens + deposit2.tokens - totalTips - redeem1.tokens - redeem2.tokens
        );
        assertEq(token.balanceOf(address(provisioner)), 0);
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE - deposit1.tokens);
        assertEq(token.balanceOf(users.bob), 0);
        assertEq(token.balanceOf(users.charlie), redeem1.tokens);
        assertEq(token.balanceOf(users.dan), redeem2.tokens);

        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0);
        assertEq(multiDepositorVault.balanceOf(users.alice), deposit1.units);
        assertEq(multiDepositorVault.balanceOf(users.bob), deposit2.units);
        assertEq(multiDepositorVault.balanceOf(users.charlie), 0);
        assertEq(multiDepositorVault.balanceOf(users.dan), 0);
    }

    function test_solveRequestsVault_success_all_solvable_withPremium() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: DEPOSIT_MULTIPLIER,
                redeemMultiplier: REDEEM_MULTIPLIER
            })
        );

        Request memory deposit1 = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 100 ether,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory deposit2 = _makeRequest({
            user: users.bob,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: 5000 ether,
            units: 4500 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory redeem1 = _makeRequest({
            user: users.charlie,
            requestType: RequestType.REDEEM_AUTO_PRICE,
            tokens: 3300 ether,
            units: 3000 ether,
            solverTip: 30 ether,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory redeem2 = _makeRequest({
            user: users.dan,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: 2200 ether,
            units: 2000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 totalSupplyOnDeposit1 = TOTAL_SUPPLY + deposit1.units + redeem1.units + redeem2.units;
        uint256 totalAssetsOnDeposit1 = TOTAL_ASSETS + deposit1.tokens - deposit1.solverTip;
        uint256 totalSupplyOnDeposit2 = totalSupplyOnDeposit1 + deposit2.units;
        uint256 totalAssetsOnDeposit2 = totalAssetsOnDeposit1 + deposit2.tokens - deposit2.solverTip;

        _mockConvertTokenToUnits(
            token, (deposit1.tokens - deposit1.solverTip) * DEPOSIT_MULTIPLIER / ONE_IN_BPS, deposit1.units
        );
        _mockConvertUnitsToToken(token, deposit2.units, deposit2.tokens * DEPOSIT_MULTIPLIER / ONE_IN_BPS - SOLVER_TIP);
        _mockConvertUnitsToNumeraire(totalSupplyOnDeposit1, totalSupplyOnDeposit1);
        _mockConvertUnitsToNumeraire(totalSupplyOnDeposit2, totalAssetsOnDeposit2);

        _mockConvertUnitsToToken(
            token, redeem1.units, (redeem1.tokens + redeem1.solverTip) * ONE_IN_BPS / REDEEM_MULTIPLIER + 1
        );
        _mockConvertUnitsToToken(token, redeem2.units, (redeem2.tokens) * ONE_IN_BPS / REDEEM_MULTIPLIER + SOLVER_TIP);

        ERC20Mock(address(token)).mint(deposit2.user, deposit2.tokens);
        _approveToken(deposit1.user, token, address(provisioner), deposit1.tokens);
        _approveToken(deposit2.user, token, address(provisioner), deposit2.tokens);

        multiDepositorVault.mint(redeem1.user, redeem1.units);
        _approveToken(redeem1.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem1.units);
        multiDepositorVault.mint(redeem2.user, redeem2.units);
        _approveToken(redeem2.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem2.units);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            token, deposit1.tokens, deposit1.units, deposit1.solverTip, deposit1.deadline, deposit1.maxPriceAge, false
        );

        vm.prank(users.bob);
        provisioner.requestDeposit(
            token, deposit2.tokens, deposit2.units, deposit2.solverTip, deposit2.deadline, deposit2.maxPriceAge, true
        );

        vm.prank(redeem1.user);
        provisioner.requestRedeem(
            token, redeem1.units, redeem1.tokens, redeem1.solverTip, redeem1.deadline, redeem1.maxPriceAge, false
        );

        vm.prank(redeem2.user);
        provisioner.requestRedeem(
            token, redeem2.units, redeem2.tokens, redeem2.solverTip, redeem2.deadline, redeem2.maxPriceAge, true
        );

        Request[] memory requests = new Request[](4);
        requests[0] = deposit1;
        requests[1] = deposit2;
        requests[2] = redeem1;
        requests[3] = redeem2;

        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.DepositSolved(provisioner.getRequestHash(token, deposit1));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.DepositSolved(provisioner.getRequestHash(token, deposit2));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.RedeemSolved(provisioner.getRequestHash(token, redeem1));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.RedeemSolved(provisioner.getRequestHash(token, redeem2));

        vm.prank(users.owner);
        provisioner.solveRequestsVault(token, requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - all solvable - with premium");

        uint256 totalTips = deposit1.solverTip + SOLVER_TIP + redeem1.solverTip + SOLVER_TIP;
        assertFalse(provisioner.asyncDepositHashes(provisioner.getRequestHash(token, deposit1)));
        assertFalse(provisioner.asyncDepositHashes(provisioner.getRequestHash(token, deposit2)));
        assertFalse(provisioner.asyncRedeemHashes(provisioner.getRequestHash(token, redeem1)));
        assertFalse(provisioner.asyncRedeemHashes(provisioner.getRequestHash(token, redeem2)));

        assertApproxEqAbs(token.balanceOf(users.owner), totalTips, 0.1 ether);
        assertApproxEqAbs(
            token.balanceOf(address(multiDepositorVault)),
            deposit1.tokens + deposit2.tokens - totalTips - redeem1.tokens - redeem2.tokens,
            0.1 ether
        );
        assertEq(token.balanceOf(address(provisioner)), 0);
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE - deposit1.tokens);
        assertEq(token.balanceOf(users.bob), 0);
        assertEq(token.balanceOf(users.charlie), redeem1.tokens);
        assertEq(token.balanceOf(users.dan), redeem2.tokens);

        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0);
        assertEq(multiDepositorVault.balanceOf(users.alice), deposit1.units);
        assertEq(multiDepositorVault.balanceOf(users.bob), deposit2.units);
        assertEq(multiDepositorVault.balanceOf(users.charlie), 0);
        assertEq(multiDepositorVault.balanceOf(users.dan), 0);
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_deposit_asyncDepositDisabled() public {
        Request memory deposit = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: 9000 ether,
            solverTip: SOLVER_TIP,
            deadline: vm.getBlockTimestamp() + 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        Request[] memory requests = new Request[](1);
        requests[0] = deposit;

        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)),
            deposit.tokens,
            deposit.units,
            deposit.solverTip,
            deposit.deadline,
            deposit.maxPriceAge,
            false
        );

        _mockConvertTokenToUnits(IERC20(address(token)), TOKENS_AMOUNT - SOLVER_TIP, deposit.units);

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: false,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        );

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.AsyncDepositDisabled(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price deposit - async deposit disabled");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        bytes32 depositHash = _getRequestHash(IERC20(address(token)), requests[0]);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncDepositHashes(depositHash), true, "Hash should still be set");
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_deposit_AmountBoundExceeded() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 netTokens = TOKENS_AMOUNT - SOLVER_TIP;
        uint256 actualUnitsOut = minUnitsOut - 1; // Less than minimum required

        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false
        );

        _mockConvertTokenToUnits(IERC20(address(token)), netTokens, actualUnitsOut);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.AmountBoundExceeded(0, actualUnitsOut, minUnitsOut);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall(
            "solveRequestsVault - success - unsolvable auto price deposit - insufficient output units"
        );

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        bytes32 depositHash = _getRequestHash(IERC20(address(token)), requests[0]);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncDepositHashes(depositHash), true, "Hash should still be set");
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_deposit_depositCapExceeded() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 netTokens = TOKENS_AMOUNT - SOLVER_TIP;

        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false
        );

        _mockConvertTokenToUnits(IERC20(address(token)), netTokens, minUnitsOut);
        _mockConvertUnitsToNumeraire(TOTAL_SUPPLY + minUnitsOut, DEPOSIT_CAP + 1); // Exceed deposit cap

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DepositCapExceeded(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price deposit - deposit cap exceeded");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(
            provisioner.asyncDepositHashes(_getRequestHash(IERC20(address(token)), requests[0])),
            true,
            "Hash should still be set"
        );
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_deposit_hashNotFound() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.InvalidRequestHash(provisioner.getRequestHash(token, requests[0]));

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price deposit - hash not found");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_deposit_refunded() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false
        );

        vm.warp(deadline + 1); // Past deadline

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        bytes32 depositHash = _getRequestHash(IERC20(address(token)), requests[0]);

        uint256 aliceBalanceBefore = token.balanceOf(users.alice);
        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DepositRefunded(depositHash);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price deposit - refunded");

        uint256 aliceBalanceAfter = token.balanceOf(users.alice);
        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(aliceBalanceAfter - aliceBalanceBefore, TOKENS_AMOUNT, "User should get tokens back");
        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncDepositHashes(depositHash), false, "Hash should be unset");
        assertEq(token.balanceOf(address(provisioner)), 0);
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE);
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_deposit_solverTipTooHigh() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 maxPriceAge = UNIT_PRICE_AGE;
        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, TOKENS_AMOUNT + 1, deadline, maxPriceAge, false
        );

        vm.warp(deadline);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: TOKENS_AMOUNT + 1,
            deadline: deadline,
            maxPriceAge: maxPriceAge
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);
        uint256 provisionerBalanceBefore = multiDepositorVault.balanceOf(address(provisioner));

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.InsufficientTokensForTip(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price deposit - solver tip too high");

        assertEq(token.balanceOf(users.owner), ownerBalanceBefore, "Solver should not receive tip");
        assertEq(
            multiDepositorVault.balanceOf(address(provisioner)),
            provisionerBalanceBefore,
            "Provisioner should keep tokens"
        );
        assertEq(
            provisioner.asyncDepositHashes(_getRequestHash(IERC20(address(token)), requests[0])),
            true,
            "Hash should still be set"
        );
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_deposit_priceTooOld() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 maxPriceAge = UNIT_PRICE_AGE - 1;
        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, SOLVER_TIP, deadline, maxPriceAge, false
        );

        vm.warp(deadline);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: maxPriceAge
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);
        uint256 provisionerBalanceBefore = multiDepositorVault.balanceOf(address(provisioner));

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.PriceAgeExceeded(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price deposit - price too old");

        assertEq(token.balanceOf(users.owner), ownerBalanceBefore, "Solver should not receive tip");
        assertEq(
            multiDepositorVault.balanceOf(address(provisioner)),
            provisionerBalanceBefore,
            "Provisioner should keep tokens"
        );
        assertEq(
            provisioner.asyncDepositHashes(_getRequestHash(IERC20(address(token)), requests[0])),
            true,
            "Hash should still be set"
        );
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_deposit_priceTooOld() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 maxPriceAge = UNIT_PRICE_AGE - 1;
        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, 0, deadline, maxPriceAge, true);

        vm.warp(deadline);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: maxPriceAge
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);
        uint256 provisionerBalanceBefore = multiDepositorVault.balanceOf(address(provisioner));

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.PriceAgeExceeded(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable fixed price deposit - price too old");

        assertEq(token.balanceOf(users.owner), ownerBalanceBefore, "Solver should not receive tip");
        assertEq(
            multiDepositorVault.balanceOf(address(provisioner)),
            provisionerBalanceBefore,
            "Provisioner should keep tokens"
        );
        assertEq(
            provisioner.asyncDepositHashes(_getRequestHash(IERC20(address(token)), requests[0])),
            true,
            "Hash should still be set"
        );
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_deposit_hashNotFound() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.InvalidRequestHash(provisioner.getRequestHash(token, requests[0]));

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable fixed price deposit - hash not found");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_deposit_AmountBoundExceeded() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, 0, deadline, UNIT_PRICE_AGE, true
        );

        _mockConvertUnitsToToken(IERC20(address(token)), minUnitsOut, TOKENS_AMOUNT + 1);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.AmountBoundExceeded(0, TOKENS_AMOUNT + 1, minUnitsOut);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable fixed price deposit - token limit exceeded");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        bytes32 depositHash = _getRequestHash(IERC20(address(token)), requests[0]);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncDepositHashes(depositHash), true, "Hash should still be set");
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_deposit_depositCapExceeded() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, 0, deadline, UNIT_PRICE_AGE, true
        );

        _mockConvertUnitsToToken(IERC20(address(token)), minUnitsOut, TOKENS_AMOUNT);
        _mockConvertUnitsToNumeraire(TOTAL_SUPPLY + minUnitsOut, DEPOSIT_CAP + 1); // Exceed deposit cap

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DepositCapExceeded(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable fixed price deposit - deposit cap exceeded");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(
            provisioner.asyncDepositHashes(_getRequestHash(IERC20(address(token)), requests[0])),
            true,
            "Hash should still be set"
        );
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_deposit_refunded() public {
        uint256 minUnitsOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)), TOKENS_AMOUNT, minUnitsOut, 0, deadline, UNIT_PRICE_AGE, true
        );

        vm.warp(deadline + 1); // Past deadline

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            user: users.alice,
            tokens: TOKENS_AMOUNT,
            units: minUnitsOut,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        bytes32 depositHash = _getRequestHash(IERC20(address(token)), requests[0]);

        uint256 aliceBalanceBefore = token.balanceOf(users.alice);
        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.DepositRefunded(depositHash);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable fixed price deposit - refunded");

        uint256 aliceBalanceAfter = token.balanceOf(users.alice);
        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(aliceBalanceAfter - aliceBalanceBefore, TOKENS_AMOUNT, "User should get tokens back");
        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncDepositHashes(depositHash), false, "Hash should be unset");
        assertEq(token.balanceOf(address(provisioner)), 0);
        assertEq(token.balanceOf(address(users.alice)), ALICE_TOKEN_BALANCE);
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_redeem_asyncRedeemDisabled() public {
        uint256 minTokenOut = 9000 ether;
        uint256 solverTip = 501 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        provisioner.requestRedeem(
            IERC20(address(token)), UNITS_OUT, minTokenOut, solverTip, deadline, UNIT_PRICE_AGE, false
        );

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_AUTO_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: solverTip,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: false,
                syncDepositEnabled: true,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        );

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.AsyncRedeemDisabled(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price redeem - async redeem disabled");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        bytes32 redeemHash = _getRequestHash(IERC20(address(token)), requests[0]);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncRedeemHashes(redeemHash), true, "Hash should still be set");
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_redeem_AmountBoundExceeded() public {
        uint256 minTokenOut = 9000 ether;
        uint256 solverTip = 501 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 actualTokenOut = 9500 ether; // More than minimum but not enough after tip

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        provisioner.requestRedeem(
            IERC20(address(token)), UNITS_OUT, minTokenOut, solverTip, deadline, UNIT_PRICE_AGE, false
        );

        _mockConvertUnitsToToken(IERC20(address(token)), UNITS_OUT, actualTokenOut);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_AUTO_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: solverTip,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.AmountBoundExceeded(0, actualTokenOut, minTokenOut);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall(
            "solveRequestsVault - success - unsolvable auto price redeem - insufficient token output"
        );

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        bytes32 redeemHash = _getRequestHash(IERC20(address(token)), requests[0]);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncRedeemHashes(redeemHash), true, "Hash should still be set");
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_redeem_hashNotFound() public {
        uint256 minTokenOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_AUTO_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.InvalidRequestHash(provisioner.getRequestHash(token, requests[0]));

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price redeem - hash not found");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_redeem_refunded() public {
        uint256 minTokenOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        provisioner.requestRedeem(
            IERC20(address(token)), UNITS_OUT, minTokenOut, SOLVER_TIP, deadline, UNIT_PRICE_AGE, false
        );

        vm.warp(deadline + 1); // Past deadline

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_AUTO_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        bytes32 redeemHash = _getRequestHash(IERC20(address(token)), requests[0]);

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.RedeemRefunded(redeemHash);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price redeem - refunded");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(multiDepositorVault.balanceOf(users.alice), UNITS_OUT, "User should get units back");
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE, "User should get tokens back");
        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncRedeemHashes(redeemHash), false, "Hash should be unset");
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_redeem_solverTipTooHigh() public {
        uint256 minTokenOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 maxPriceAge = UNIT_PRICE_AGE;

        _mockConvertUnitsToToken(token, UNITS_OUT, minTokenOut);

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        provisioner.requestRedeem(
            IERC20(address(token)), UNITS_OUT, minTokenOut, minTokenOut + 1, deadline, maxPriceAge, false
        );

        vm.warp(deadline);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_AUTO_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: minTokenOut + 1,
            deadline: deadline,
            maxPriceAge: maxPriceAge
        });

        uint256 ownerBalanceBefore = multiDepositorVault.balanceOf(users.owner);
        uint256 provisionerBalanceBefore = multiDepositorVault.balanceOf(address(provisioner));

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.InsufficientTokensForTip(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price redeem - solver tip too high");

        assertEq(multiDepositorVault.balanceOf(users.owner), ownerBalanceBefore, "Solver should not receive tip");
        assertEq(
            multiDepositorVault.balanceOf(address(provisioner)),
            provisionerBalanceBefore,
            "Provisioner should keep units"
        );
        assertEq(
            provisioner.asyncRedeemHashes(_getRequestHash(IERC20(address(token)), requests[0])),
            true,
            "Hash should still be set"
        );
    }

    function test_solveRequestsVault_success_unsolvable_autoPrice_redeem_priceTooOld() public {
        uint256 minTokenOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 maxPriceAge = UNIT_PRICE_AGE - 1;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        provisioner.requestRedeem(
            IERC20(address(token)), UNITS_OUT, minTokenOut, SOLVER_TIP, deadline, maxPriceAge, false
        );

        vm.warp(deadline);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_AUTO_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: SOLVER_TIP,
            deadline: deadline,
            maxPriceAge: maxPriceAge
        });

        uint256 ownerBalanceBefore = multiDepositorVault.balanceOf(users.owner);
        uint256 provisionerBalanceBefore = multiDepositorVault.balanceOf(address(provisioner));

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.PriceAgeExceeded(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable auto price redeem - price too old");

        assertEq(multiDepositorVault.balanceOf(users.owner), ownerBalanceBefore, "Solver should not receive tip");
        assertEq(
            multiDepositorVault.balanceOf(address(provisioner)),
            provisionerBalanceBefore,
            "Provisioner should keep units"
        );
        assertEq(
            provisioner.asyncRedeemHashes(_getRequestHash(IERC20(address(token)), requests[0])),
            true,
            "Hash should still be set"
        );
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_redeem_priceTooOld() public {
        uint256 minTokenOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 maxPriceAge = UNIT_PRICE_AGE - 1;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        provisioner.requestRedeem(IERC20(address(token)), UNITS_OUT, minTokenOut, 0, deadline, maxPriceAge, true);

        vm.warp(deadline);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_FIXED_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: maxPriceAge
        });

        uint256 ownerBalanceBefore = multiDepositorVault.balanceOf(users.owner);
        uint256 provisionerBalanceBefore = multiDepositorVault.balanceOf(address(provisioner));

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.PriceAgeExceeded(0);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable fixed price redeem - price too old");

        assertEq(multiDepositorVault.balanceOf(users.owner), ownerBalanceBefore, "Solver should not receive tip");
        assertEq(
            multiDepositorVault.balanceOf(address(provisioner)),
            provisionerBalanceBefore,
            "Provisioner should keep units"
        );
        assertEq(
            provisioner.asyncRedeemHashes(_getRequestHash(IERC20(address(token)), requests[0])),
            true,
            "Hash should still be set"
        );
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_redeem_hashNotFound() public {
        uint256 minTokenOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_FIXED_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.InvalidRequestHash(provisioner.getRequestHash(token, requests[0]));

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable fixed price redeem - hash not found");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_redeem_AmountBoundExceeded() public {
        uint256 minTokenOut = 9000 ether;
        uint256 deadline = vm.getBlockTimestamp() + 1 days;
        uint256 actualTokenOut = minTokenOut - 1; // Less than minimum token out

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        provisioner.requestRedeem(IERC20(address(token)), UNITS_OUT, minTokenOut, 0, deadline, UNIT_PRICE_AGE, true);

        _mockConvertUnitsToToken(IERC20(address(token)), UNITS_OUT, actualTokenOut);

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_FIXED_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.AmountBoundExceeded(0, actualTokenOut, minTokenOut);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall(
            "solveRequestsVault - success - unsolvable fixed price redeem - insufficient token output"
        );

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        bytes32 redeemHash = _getRequestHash(IERC20(address(token)), requests[0]);

        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncRedeemHashes(redeemHash), true, "Hash should still be set");
    }

    function test_solveRequestsVault_success_unsolvable_fixedPrice_redeem_refunded() public {
        uint256 minTokenOut = 9000 ether;

        uint256 deadline = vm.getBlockTimestamp() + 1 days;

        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        vm.prank(users.alice);
        provisioner.requestRedeem(IERC20(address(token)), UNITS_OUT, minTokenOut, 0, deadline, UNIT_PRICE_AGE, true);

        vm.warp(deadline + 1); // Past deadline

        Request[] memory requests = new Request[](1);
        requests[0] = Request({
            requestType: RequestType.REDEEM_FIXED_PRICE,
            user: users.alice,
            tokens: minTokenOut,
            units: UNITS_OUT,
            solverTip: 0,
            deadline: deadline,
            maxPriceAge: UNIT_PRICE_AGE
        });

        bytes32 redeemHash = _getRequestHash(IERC20(address(token)), requests[0]);

        uint256 ownerBalanceBefore = token.balanceOf(users.owner);

        vm.prank(users.owner);
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.RedeemRefunded(redeemHash);
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
        vm.snapshotGasLastCall("solveRequestsVault - success - unsolvable fixed price redeem - refunded");

        uint256 ownerBalanceAfter = token.balanceOf(users.owner);

        assertEq(multiDepositorVault.balanceOf(users.alice), UNITS_OUT, "User should get units back");
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE, "User should get tokens back");
        assertEq(ownerBalanceAfter, ownerBalanceBefore, "Solver should not receive tip");
        assertEq(provisioner.asyncRedeemHashes(redeemHash), false, "Hash should be unset");
    }

    function test_solveRequestsVault_deposit_revertsWith_VaultPaused() public {
        vm.mockCallRevert(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertTokenToUnitsIfActive.selector,
                address(multiDepositorVault),
                token,
                TOKENS_AMOUNT - SOLVER_TIP
            ),
            abi.encodeWithSelector(IPriceAndFeeCalculator.Aera__VaultPaused.selector)
        );
        _approveToken(users.alice, IERC20(address(token)), address(provisioner), TOKENS_AMOUNT);

        Request memory deposit = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            tokens: TOKENS_AMOUNT,
            units: UNITS_OUT,
            solverTip: SOLVER_TIP,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        vm.prank(users.alice);
        provisioner.requestDeposit(
            IERC20(address(token)),
            deposit.tokens,
            deposit.units,
            deposit.solverTip,
            deposit.deadline,
            deposit.maxPriceAge,
            false
        );

        Request[] memory requests = new Request[](1);
        requests[0] = deposit;

        vm.prank(users.owner);
        vm.expectRevert();
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
    }

    function test_solveRequestsVault_redeem_revertsWith_VaultPaused() public {
        vm.mockCallRevert(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToTokenIfActive.selector,
                address(multiDepositorVault),
                token,
                UNITS_OUT
            ),
            abi.encodeWithSelector(IPriceAndFeeCalculator.Aera__VaultPaused.selector)
        );
        multiDepositorVault.mint(users.alice, UNITS_OUT);
        _approveToken(users.alice, IERC20(address(multiDepositorVault)), address(provisioner), UNITS_OUT);

        Request memory redeem = _makeRequest({
            user: users.alice,
            requestType: RequestType.REDEEM_AUTO_PRICE,
            tokens: TOKENS_AMOUNT,
            units: UNITS_OUT,
            solverTip: SOLVER_TIP,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        vm.prank(users.alice);
        provisioner.requestRedeem(
            IERC20(address(token)),
            redeem.units,
            redeem.tokens,
            redeem.solverTip,
            redeem.deadline,
            redeem.maxPriceAge,
            false
        );

        Request[] memory requests = new Request[](1);
        requests[0] = redeem;

        vm.prank(users.owner);
        vm.expectRevert();
        provisioner.solveRequestsVault(IERC20(address(token)), requests);
    }

    ////////////////////////////////////////////////////////////
    //                  solveRequestsDirect                   //
    ////////////////////////////////////////////////////////////
    function test_solveRequestsDirect_success_all_solvable() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                syncDepositEnabled: false,
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        );

        Request memory deposit1 = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory deposit2 = _makeRequest({
            user: users.bob,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: 5000 ether,
            units: 4500 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory redeem1 = _makeRequest({
            user: users.charlie,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: 3300 ether,
            units: 3000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });
        Request memory redeem2 = _makeRequest({
            user: users.dan,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: 2200 ether,
            units: 2000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        ERC20Mock(address(token)).mint(deposit2.user, deposit2.tokens);
        _approveToken(deposit1.user, token, address(provisioner), deposit1.tokens);
        _approveToken(deposit2.user, token, address(provisioner), deposit2.tokens);

        multiDepositorVault.mint(redeem1.user, redeem1.units);
        _approveToken(redeem1.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem1.units);
        multiDepositorVault.mint(redeem2.user, redeem2.units);
        _approveToken(redeem2.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem2.units);

        vm.prank(deposit1.user);
        provisioner.requestDeposit(
            token, deposit1.tokens, deposit1.units, deposit1.solverTip, deposit1.deadline, deposit1.maxPriceAge, true
        );

        vm.prank(deposit2.user);
        provisioner.requestDeposit(
            token, deposit2.tokens, deposit2.units, deposit2.solverTip, deposit2.deadline, deposit2.maxPriceAge, true
        );

        // Make redeem requests
        vm.prank(redeem1.user);
        provisioner.requestRedeem(
            token, redeem1.units, redeem1.tokens, redeem1.solverTip, redeem1.deadline, redeem1.maxPriceAge, true
        );

        vm.prank(redeem2.user);
        provisioner.requestRedeem(
            token, redeem2.units, redeem2.tokens, redeem2.solverTip, redeem2.deadline, redeem2.maxPriceAge, true
        );

        multiDepositorVault.mint(users.eve, deposit1.units + deposit2.units);
        _approveToken(
            users.eve, IERC20(address(multiDepositorVault)), address(provisioner), deposit1.units + deposit2.units
        );

        _approveToken(users.eve, token, address(provisioner), redeem1.tokens + redeem2.tokens);

        Request[] memory requests = new Request[](4);
        requests[0] = deposit1;
        requests[1] = deposit2;
        requests[2] = redeem1;
        requests[3] = redeem2;

        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.DepositSolved(provisioner.getRequestHash(token, deposit1));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.DepositSolved(provisioner.getRequestHash(token, deposit2));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.RedeemSolved(provisioner.getRequestHash(token, redeem1));
        vm.expectEmit(true, false, false, true, address(provisioner));
        emit IProvisioner.RedeemSolved(provisioner.getRequestHash(token, redeem2));

        vm.prank(users.eve);
        provisioner.solveRequestsDirect(token, requests);
        vm.snapshotGasLastCall("solveRequestsDirect - success - all solvable");

        assertFalse(provisioner.asyncDepositHashes(provisioner.getRequestHash(token, deposit1)));
        assertFalse(provisioner.asyncDepositHashes(provisioner.getRequestHash(token, deposit2)));
        assertFalse(provisioner.asyncRedeemHashes(provisioner.getRequestHash(token, redeem1)));
        assertFalse(provisioner.asyncRedeemHashes(provisioner.getRequestHash(token, redeem2)));

        uint256 netTokens = deposit1.tokens + deposit2.tokens - redeem1.tokens - redeem2.tokens;

        assertEq(token.balanceOf(users.eve), netTokens);
        assertEq(token.balanceOf(address(multiDepositorVault)), 0);
        assertEq(token.balanceOf(address(provisioner)), 0);
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE - deposit1.tokens);
        assertEq(token.balanceOf(users.bob), 0);
        assertEq(token.balanceOf(users.charlie), redeem1.tokens);
        assertEq(token.balanceOf(users.dan), redeem2.tokens);

        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0);
        assertEq(multiDepositorVault.balanceOf(users.alice), deposit1.units);
        assertEq(multiDepositorVault.balanceOf(users.bob), deposit2.units);
        assertEq(multiDepositorVault.balanceOf(users.charlie), 0);
        assertEq(multiDepositorVault.balanceOf(users.dan), 0);
        assertEq(multiDepositorVault.balanceOf(users.eve), redeem1.units + redeem2.units);
    }

    function test_solveRequestsDirect_success_unsolvable_deposit_unitsOutNotMet() public {
        Request memory deposit = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        ERC20Mock(address(token)).mint(deposit.user, deposit.tokens);
        _approveToken(deposit.user, token, address(provisioner), deposit.tokens);

        vm.prank(deposit.user);
        provisioner.requestDeposit(
            token, deposit.tokens, deposit.units, deposit.solverTip, deposit.deadline, deposit.maxPriceAge, true
        );

        multiDepositorVault.mint(users.eve, deposit.units);
        _approveToken(users.eve, IERC20(address(multiDepositorVault)), address(provisioner), deposit.units - 1);

        Request[] memory requests = new Request[](1);
        requests[0] = deposit;

        vm.prank(users.eve);
        vm.expectRevert();
        provisioner.solveRequestsDirect(token, requests);
    }

    function test_solveRequestsDirect_success_unsolvable_deposit_hashNotSet() public {
        Request memory deposit = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        ERC20Mock(address(token)).mint(deposit.user, deposit.tokens);
        _approveToken(deposit.user, token, address(provisioner), deposit.tokens);

        _mockConvertTokenToUnits(token, deposit.tokens - deposit.solverTip, deposit.units - 1);

        vm.prank(deposit.user);
        provisioner.requestDeposit(
            token, deposit.tokens, deposit.units, deposit.solverTip, deposit.deadline, deposit.maxPriceAge, true
        );

        multiDepositorVault.mint(users.eve, deposit.units);
        _approveToken(users.eve, IERC20(address(multiDepositorVault)), address(provisioner), deposit.units);

        Request[] memory requests = new Request[](1);
        requests[0] = deposit;
        requests[0].maxPriceAge = 1;

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.InvalidRequestHash(provisioner.getRequestHash(token, requests[0]));

        vm.prank(users.eve);
        provisioner.solveRequestsDirect(token, requests);
        vm.snapshotGasLastCall("solveRequestsDirect - success - unsolvable deposit - hash not set");

        requests[0].maxPriceAge = UNIT_PRICE_AGE;
        assertTrue(provisioner.asyncDepositHashes(provisioner.getRequestHash(token, deposit)));

        assertEq(token.balanceOf(address(provisioner)), deposit.tokens);
        assertEq(token.balanceOf(users.eve), 0);
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE);

        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0);
        assertEq(multiDepositorVault.balanceOf(users.eve), deposit.units);
        assertEq(multiDepositorVault.balanceOf(users.alice), 0);
    }

    function test_solveRequestsDirect_success_unsolvable_deposit_deadlinePassed() public {
        Request memory deposit = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        ERC20Mock(address(token)).mint(deposit.user, deposit.tokens);
        _approveToken(deposit.user, token, address(provisioner), deposit.tokens);

        _mockConvertTokenToUnits(token, deposit.tokens - deposit.solverTip, deposit.units - 1);

        vm.prank(deposit.user);
        provisioner.requestDeposit(
            token, deposit.tokens, deposit.units, deposit.solverTip, deposit.deadline, deposit.maxPriceAge, true
        );

        multiDepositorVault.mint(users.eve, deposit.units);
        _approveToken(users.eve, IERC20(address(multiDepositorVault)), address(provisioner), deposit.units);

        Request[] memory requests = new Request[](1);
        requests[0] = deposit;

        vm.warp(deposit.deadline + 1);

        vm.prank(users.eve);
        vm.expectEmit(true, false, false, true);
        emit IProvisioner.DepositRefunded(provisioner.getRequestHash(token, deposit));
        provisioner.solveRequestsDirect(token, requests);

        assertFalse(provisioner.asyncDepositHashes(provisioner.getRequestHash(token, deposit)));

        assertEq(token.balanceOf(address(provisioner)), 0);
        assertEq(token.balanceOf(users.eve), 0);
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE + deposit.tokens);

        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0);
        assertEq(multiDepositorVault.balanceOf(users.eve), deposit.units);
        assertEq(multiDepositorVault.balanceOf(users.alice), 0);
    }

    function test_solveRequestsDirect_success_unsolvable_redeem_tokensOutNotMet() public {
        Request memory redeem = _makeRequest({
            user: users.alice,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        multiDepositorVault.mint(redeem.user, redeem.units);
        _approveToken(redeem.user, IERC20(multiDepositorVault), address(provisioner), redeem.units);

        _mockConvertUnitsToToken(token, redeem.units, redeem.tokens + redeem.solverTip - 1);

        vm.prank(redeem.user);
        provisioner.requestRedeem(
            token, redeem.units, redeem.tokens, redeem.solverTip, redeem.deadline, redeem.maxPriceAge, true
        );

        ERC20Mock(address(token)).mint(users.eve, redeem.tokens);
        _approveToken(users.eve, token, address(provisioner), redeem.tokens - 1);

        Request[] memory requests = new Request[](1);
        requests[0] = redeem;

        vm.prank(users.eve);
        vm.expectRevert();
        provisioner.solveRequestsDirect(token, requests);
    }

    function test_solveRequestsDirect_success_unsolvable_redeem_hashNotSet() public {
        Request memory redeem = _makeRequest({
            user: users.alice,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        multiDepositorVault.mint(redeem.user, redeem.units);
        _approveToken(redeem.user, IERC20(multiDepositorVault), address(provisioner), redeem.units);

        _mockConvertUnitsToToken(token, redeem.units, redeem.tokens + redeem.solverTip);

        vm.prank(redeem.user);
        provisioner.requestRedeem(
            token, redeem.units, redeem.tokens, redeem.solverTip, redeem.deadline, redeem.maxPriceAge, true
        );

        ERC20Mock(address(token)).mint(users.eve, redeem.tokens);
        _approveToken(users.eve, token, address(provisioner), redeem.tokens);

        Request[] memory requests = new Request[](1);
        requests[0] = redeem;
        requests[0].maxPriceAge = 1;

        vm.expectEmit(true, false, false, false);
        emit IProvisioner.InvalidRequestHash(provisioner.getRequestHash(token, requests[0]));

        vm.prank(users.eve);
        provisioner.solveRequestsDirect(token, requests);

        requests[0].maxPriceAge = UNIT_PRICE_AGE;
        assertTrue(provisioner.asyncRedeemHashes(provisioner.getRequestHash(token, redeem)));

        assertEq(token.balanceOf(address(provisioner)), 0);
        assertEq(token.balanceOf(users.eve), redeem.tokens);
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE);

        assertEq(multiDepositorVault.balanceOf(address(provisioner)), redeem.units);
        assertEq(multiDepositorVault.balanceOf(users.eve), 0);
        assertEq(multiDepositorVault.balanceOf(users.alice), 0);
    }

    function test_solveRequestsDirect_success_unsolvable_redeem_deadlinePassed() public {
        Request memory redeem = _makeRequest({
            user: users.alice,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        multiDepositorVault.mint(redeem.user, redeem.units);
        _approveToken(redeem.user, IERC20(multiDepositorVault), address(provisioner), redeem.units);

        _mockConvertUnitsToToken(token, redeem.units, redeem.tokens + redeem.solverTip - 1);

        vm.prank(redeem.user);
        provisioner.requestRedeem(
            token, redeem.units, redeem.tokens, redeem.solverTip, redeem.deadline, redeem.maxPriceAge, true
        );

        ERC20Mock(address(token)).mint(users.eve, redeem.tokens);
        _approveToken(users.eve, token, address(provisioner), redeem.tokens);

        Request[] memory requests = new Request[](1);
        requests[0] = redeem;

        vm.warp(redeem.deadline + 1);

        vm.prank(users.eve);
        vm.expectEmit(true, false, false, true);
        emit IProvisioner.RedeemRefunded(provisioner.getRequestHash(token, redeem));
        provisioner.solveRequestsDirect(token, requests);

        assertFalse(provisioner.asyncRedeemHashes(provisioner.getRequestHash(token, redeem)));

        assertEq(token.balanceOf(address(provisioner)), 0);
        assertEq(token.balanceOf(users.eve), redeem.tokens);
        assertEq(token.balanceOf(users.alice), ALICE_TOKEN_BALANCE);

        assertEq(multiDepositorVault.balanceOf(address(provisioner)), 0);
        assertEq(multiDepositorVault.balanceOf(users.eve), 0);
        assertEq(multiDepositorVault.balanceOf(users.alice), redeem.units);
    }

    function test_solveRequestsDirect_revertsWith_AsyncDepositDisabled() public {
        Request memory deposit = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        ERC20Mock(address(token)).mint(deposit.user, deposit.tokens);
        _approveToken(deposit.user, token, address(provisioner), deposit.tokens);

        vm.prank(deposit.user);
        provisioner.requestDeposit(
            token, deposit.tokens, deposit.units, deposit.solverTip, deposit.deadline, deposit.maxPriceAge, true
        );

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                syncDepositEnabled: false,
                asyncDepositEnabled: false,
                asyncRedeemEnabled: true,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        );

        Request[] memory requests = new Request[](1);
        requests[0] = deposit;

        vm.prank(deposit.user);
        vm.expectRevert(IProvisioner.Aera__AsyncDepositDisabled.selector);
        provisioner.solveRequestsDirect(token, requests);
    }

    function test_solveRequestsDirect_revertsWith_AsyncRedeemDisabled() public {
        Request memory redeem = _makeRequest({
            user: users.alice,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: 10_000 ether,
            units: 9000 ether,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        multiDepositorVault.mint(redeem.user, redeem.units);
        _approveToken(redeem.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem.units);

        vm.prank(redeem.user);
        provisioner.requestRedeem(
            token, redeem.units, redeem.tokens, redeem.solverTip, redeem.deadline, redeem.maxPriceAge, true
        );

        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                syncDepositEnabled: false,
                asyncDepositEnabled: true,
                asyncRedeemEnabled: false,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        );

        Request[] memory requests = new Request[](1);
        requests[0] = redeem;

        vm.prank(redeem.user);
        vm.expectRevert(IProvisioner.Aera__AsyncRedeemDisabled.selector);
        provisioner.solveRequestsDirect(token, requests);
    }

    function test_solveRequestsDirect_deposit_revertsWith_PriceAndFeeCalculatorVaultPaused() public {
        Request memory deposit = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_FIXED_PRICE,
            tokens: TOKENS_AMOUNT,
            units: UNITS_OUT,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        _approveToken(deposit.user, IERC20(address(token)), address(provisioner), deposit.tokens);

        vm.prank(deposit.user);
        provisioner.requestDeposit(
            token, deposit.tokens, deposit.units, deposit.solverTip, deposit.deadline, deposit.maxPriceAge, true
        );

        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(IPriceAndFeeCalculator.isVaultPaused.selector, address(multiDepositorVault)),
            abi.encode(true)
        );

        ERC20Mock(address(multiDepositorVault)).mint(users.eve, deposit.units);
        _approveToken(users.eve, IERC20(address(multiDepositorVault)), address(provisioner), deposit.units);

        Request[] memory requests = new Request[](1);
        requests[0] = deposit;

        vm.prank(users.eve);
        vm.expectRevert(IProvisioner.Aera__PriceAndFeeCalculatorVaultPaused.selector);
        provisioner.solveRequestsDirect(token, requests);
    }

    function test_solveRequestsDirect_redeem_revertsWith_PriceAndFeeCalculatorVaultPaused() public {
        Request memory redeem = _makeRequest({
            user: users.alice,
            requestType: RequestType.REDEEM_FIXED_PRICE,
            tokens: TOKENS_AMOUNT,
            units: UNITS_OUT,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        multiDepositorVault.mint(redeem.user, redeem.units);
        _approveToken(redeem.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem.units);

        vm.prank(redeem.user);
        provisioner.requestRedeem(
            token, redeem.units, redeem.tokens, redeem.solverTip, redeem.deadline, redeem.maxPriceAge, true
        );

        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(IPriceAndFeeCalculator.isVaultPaused.selector, address(multiDepositorVault)),
            abi.encode(true)
        );

        ERC20Mock(address(token)).mint(users.eve, redeem.tokens);
        _approveToken(users.eve, token, address(provisioner), redeem.tokens);

        Request[] memory requests = new Request[](1);
        requests[0] = redeem;

        vm.prank(users.eve);
        vm.expectRevert(IProvisioner.Aera__PriceAndFeeCalculatorVaultPaused.selector);
        provisioner.solveRequestsDirect(token, requests);
    }

    function test_solveRequestsDirect_deposit_revertsWith_AutoPriceSolveNotAllowed() public {
        Request memory deposit = _makeRequest({
            user: users.alice,
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            tokens: TOKENS_AMOUNT,
            units: UNITS_OUT,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        _approveToken(deposit.user, IERC20(address(token)), address(provisioner), deposit.tokens);

        vm.prank(deposit.user);
        provisioner.requestDeposit(
            token, deposit.tokens, deposit.units, deposit.solverTip, deposit.deadline, deposit.maxPriceAge, false
        );

        ERC20Mock(address(token)).mint(users.eve, deposit.tokens);
        _approveToken(users.eve, token, address(provisioner), deposit.tokens);

        Request[] memory requests = new Request[](1);
        requests[0] = deposit;

        vm.prank(users.eve);
        vm.expectRevert(IProvisioner.Aera__AutoPriceSolveNotAllowed.selector);
        provisioner.solveRequestsDirect(token, requests);
    }

    function test_solveRequestsDirect_redeem_revertsWith_AutoPriceSolveNotAllowed() public {
        Request memory redeem = _makeRequest({
            user: users.alice,
            requestType: RequestType.REDEEM_AUTO_PRICE,
            tokens: TOKENS_AMOUNT,
            units: UNITS_OUT,
            solverTip: 0,
            deadline: 1 days,
            maxPriceAge: UNIT_PRICE_AGE
        });

        multiDepositorVault.mint(redeem.user, redeem.units);
        _approveToken(redeem.user, IERC20(address(multiDepositorVault)), address(provisioner), redeem.units);

        vm.prank(redeem.user);
        provisioner.requestRedeem(
            token, redeem.units, redeem.tokens, redeem.solverTip, redeem.deadline, redeem.maxPriceAge, false
        );

        ERC20Mock(address(token)).mint(users.eve, redeem.tokens);
        _approveToken(users.eve, token, address(provisioner), redeem.tokens);

        Request[] memory requests = new Request[](1);
        requests[0] = redeem;

        vm.prank(users.eve);
        vm.expectRevert(IProvisioner.Aera__AutoPriceSolveNotAllowed.selector);
        provisioner.solveRequestsDirect(token, requests);
    }

    ////////////////////////////////////////////////////////////
    //                   removeTokenDetails                   //
    ////////////////////////////////////////////////////////////

    function test_removeToken_success() public {
        vm.expectEmit(true, false, false, false);
        emit IProvisioner.TokenRemoved(token);
        vm.prank(users.owner);
        provisioner.removeToken(token);

        (
            bool asyncDepositEnabled,
            bool asyncRedeemEnabled,
            bool syncDepositEnabled,
            uint16 depositMultiplier,
            uint16 redeemMultiplier
        ) = provisioner.tokensDetails(token);

        assertEq(asyncDepositEnabled, false, "asyncDepositEnabled should be false");
        assertEq(asyncRedeemEnabled, false, "asyncRedeemEnabled should be false");
        assertEq(syncDepositEnabled, false, "syncDepositEnabled should be false");
        assertEq(depositMultiplier, 0, "depositMultiplier should be zero");
        assertEq(redeemMultiplier, 0, "redeemMultiplier should be zero");
    }

    function test_removeToken_revertsWith_Unauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(users.alice);
        provisioner.removeToken(token);
    }

    ////////////////////////////////////////////////////////////
    //                       maxDeposit                       //
    ////////////////////////////////////////////////////////////

    function test_maxDeposit_success_depositCapGreaterThanTotalAssets() public view {
        uint256 maxDeposit = provisioner.maxDeposit();
        assertEq(
            maxDeposit,
            DEPOSIT_CAP - TOTAL_ASSETS,
            "maxDeposit should be the difference between the deposit cap and total assets"
        );
    }

    function test_maxDeposit_success_depositCapLessThanTotalAssets() public {
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToNumeraire.selector, address(multiDepositorVault), TOTAL_SUPPLY
            ),
            abi.encode(DEPOSIT_CAP)
        );
        uint256 maxDeposit = provisioner.maxDeposit();
        assertEq(maxDeposit, 0, "maxDeposit should be zero");
    }

    ////////////////////////////////////////////////////////////
    //                    Helper functions                    //
    ////////////////////////////////////////////////////////////

    function _mockConvertTokenToUnits(IERC20 token_, uint256 tokenAmount, uint256 unitsOut) internal {
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertTokenToUnitsIfActive.selector,
                address(multiDepositorVault),
                token_,
                tokenAmount
            ),
            abi.encode(unitsOut)
        );
    }

    function _mockConvertUnitsToNumeraire(uint256 unitsAmount, uint256 numeraireAmount) internal {
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToNumeraire.selector, address(multiDepositorVault), unitsAmount
            ),
            abi.encode(numeraireAmount)
        );
    }

    function _mockConvertUnitsToToken(IERC20 token_, uint256 unitsAmount, uint256 tokenOut) internal {
        vm.mockCall(
            PRICE_FEE_CALCULATOR,
            abi.encodeWithSelector(
                IPriceAndFeeCalculator.convertUnitsToTokenIfActive.selector,
                address(multiDepositorVault),
                token_,
                unitsAmount
            ),
            abi.encode(tokenOut)
        );
    }

    function _mockTransferFrom(IERC20 token_, address from, address to, uint256 amount) internal {
        vm.mockCall(
            address(token_), abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount), abi.encode(true)
        );
    }

    function _makeRequest(
        address user,
        RequestType requestType,
        uint256 tokens,
        uint256 units,
        uint256 solverTip,
        uint256 deadline,
        uint256 maxPriceAge
    ) internal view returns (Request memory) {
        return Request({
            requestType: requestType,
            user: user,
            tokens: tokens,
            units: units,
            solverTip: solverTip,
            deadline: vm.getBlockTimestamp() + deadline,
            maxPriceAge: maxPriceAge
        });
    }

    function _getRequestHash(IERC20 token_, Request memory request) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                token_,
                request.user,
                request.requestType,
                request.tokens,
                request.units,
                request.solverTip,
                request.deadline,
                request.maxPriceAge
            )
        );
    }

    function _isRequestTypeDeposit(RequestType requestType) internal pure returns (bool) {
        return uint8(requestType) & 1 == 0;
    }

    function _isRequestTypeFixedPrice(RequestType requestType) internal pure returns (bool) {
        return uint8(requestType) & 2 == 2;
    }
}
