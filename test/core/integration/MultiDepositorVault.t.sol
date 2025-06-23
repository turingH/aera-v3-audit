// SPDX-License-Identifier: UNLICENSED
// solhint-disable max-states-count
pragma solidity 0.8.29;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { Create2 } from "@oz/utils/Create2.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { ONE_IN_BPS, UNIT_PRICE_PRECISION } from "src/core/Constants.sol";
import { MultiDepositorVault } from "src/core/MultiDepositorVault.sol";
import { MultiDepositorVaultDeployDelegate } from "src/core/MultiDepositorVaultDeployDelegate.sol";
import { MultiDepositorVaultFactory } from "src/core/MultiDepositorVaultFactory.sol";
import { PriceAndFeeCalculator } from "src/core/PriceAndFeeCalculator.sol";
import { Provisioner } from "src/core/Provisioner.sol";
import {
    BaseVaultParameters,
    ERC20Parameters,
    FeeVaultParameters,
    Request,
    RequestType,
    TokenDetails
} from "src/core/Types.sol";
import { Whitelist } from "src/core/Whitelist.sol";
import { IOracle } from "src/dependencies/oracles/IOracle.sol";

import { IFeeVault } from "src/core/interfaces/IFeeVault.sol";
import { IMultiDepositorVault } from "src/core/interfaces/IMultiDepositorVault.sol";
import { IPriceAndFeeCalculator } from "src/core/interfaces/IPriceAndFeeCalculator.sol";
import { IProvisioner } from "src/core/interfaces/IProvisioner.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { ERC20Mock } from "test/core/mocks/ERC20Mock.sol";

import { MultiDepositorVaultFactory } from "src/core/MultiDepositorVaultFactory.sol";

import { Whitelist } from "src/core/Whitelist.sol";
import { TransferBlacklistHook } from "src/periphery/hooks/transfer/TransferBlacklistHook.sol";

import { MockChainalysisSanctionsOracle } from "test/core/mocks/MockChainalysisSanctionsOracle.sol";
import { MockMultiDepositorVaultFactory } from "test/core/mocks/MockMultiDepositorVaultFactory.sol";

import { MockChainlink7726Adapter } from "test/periphery/mocks/MockChainlink7726Adapter.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { OracleMock } from "test/utils/OracleMock.sol";

contract MultiDepositorVaultTest is BaseTest, MockMultiDepositorVaultFactory {
    MockChainalysisSanctionsOracle internal sanctionsOracle;
    TransferBlacklistHook internal transferBlacklistHook;
    MultiDepositorVault internal multiDepositorVault;
    Provisioner internal provisioner;
    PriceAndFeeCalculator internal priceAndFeeCalculator;
    OracleRegistry internal oracleRegistry;
    MultiDepositorVaultFactory internal multiDepositorVaultFactory;
    Whitelist internal whitelist;

    ERC20Mock internal WETH;
    ERC20Mock internal USDC;
    ERC20Mock internal LINK;
    ERC20Mock internal BTC;

    OracleMock internal linkEthOracle;
    OracleMock internal ethLinkOracle;
    OracleMock internal usdcEthOracle;
    OracleMock internal ethUsdcOracle;
    OracleMock internal btcEthOracle;
    OracleMock internal ethBtcOracle;

    MockChainlink7726Adapter internal mockChainlink7726Adapter;

    address internal constant FACTORY_ADDRESS = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;
    bytes32 internal constant SALT = 0xcbab1e31b750e888c4c9f53975e93018ddd9361f2ab2a0b34a76bedfbb57b301;

    uint16 internal constant MAX_PRICE_TOLERANCE_RATIO = 11_000;
    uint16 internal constant MIN_PRICE_TOLERANCE_RATIO = 9000;
    uint16 internal constant MIN_UPDATE_INTERVAL_MINUTES = 1000;
    uint8 internal constant MAX_PRICE_AGE = 24;
    uint8 internal constant MAX_UPDATE_DELAY_DAYS = 15;

    uint16 internal constant VAULT_TVL_FEE = 100;
    uint16 internal constant VAULT_PERFORMANCE_FEE = 1000;
    uint16 internal constant PROTOCOL_TVL_FEE = 50;
    uint16 internal constant PROTOCOL_PERFORMANCE_FEE = 200;
    uint256 internal constant DEPOSIT_CAP = 100_000e18;
    uint256 internal constant DEPOSIT_REFUND_TIMEOUT = 2 days;

    uint128 internal currentPrice;
    address internal numeraire;

    function setUp() public override {
        super.setUp();

        WETH = new ERC20Mock();
        WETH.initialize("WETH", "WETH", 18);
        vm.label(address(WETH), "WETH");
        USDC = new ERC20Mock();
        USDC.initialize("USDC", "USDC", 6);
        vm.label(address(USDC), "USDC");
        LINK = new ERC20Mock();
        LINK.initialize("LINK", "LINK", 18);
        vm.label(address(LINK), "LINK");
        BTC = new ERC20Mock();
        BTC.initialize("BTC", "BTC", 8);
        vm.label(address(BTC), "BTC");

        whitelist = new Whitelist(users.owner, Authority(address(0)));
        vm.prank(users.owner);
        whitelist.setWhitelisted(users.guardian, true);

        MultiDepositorVaultDeployDelegate deployDelegate = new MultiDepositorVaultDeployDelegate();
        deployCodeTo(
            "MultiDepositorVaultFactory",
            abi.encode(users.owner, Authority(address(0)), address(deployDelegate)),
            FACTORY_ADDRESS
        );
        multiDepositorVaultFactory = MultiDepositorVaultFactory(FACTORY_ADDRESS);

        sanctionsOracle = new MockChainalysisSanctionsOracle();
        transferBlacklistHook = new TransferBlacklistHook(sanctionsOracle);

        _setupOracleRegistry();

        numeraire = address(WETH);

        priceAndFeeCalculator =
            new PriceAndFeeCalculator(IERC20(numeraire), oracleRegistry, users.owner, Authority(address(0)));

        vm.prank(users.owner);
        multiDepositorVault = MultiDepositorVault(
            payable(
                multiDepositorVaultFactory.create(
                    SALT,
                    "MultiDepositorVault",
                    ERC20Parameters({ name: "MultiDepositorVault Token", symbol: "MDVT" }),
                    BaseVaultParameters({
                        owner: users.owner,
                        authority: Authority(address(0)),
                        submitHooks: ISubmitHooks(address(0)),
                        whitelist: whitelist
                    }),
                    FeeVaultParameters({
                        feeToken: IERC20(numeraire),
                        feeCalculator: priceAndFeeCalculator,
                        feeRecipient: users.feeRecipient
                    }),
                    transferBlacklistHook,
                    Create2.computeAddress(
                        SALT, keccak256(type(MultiDepositorVault).creationCode), address(multiDepositorVaultFactory)
                    )
                )
            )
        );

        provisioner =
            new Provisioner(priceAndFeeCalculator, address(multiDepositorVault), users.owner, Authority(address(0)));

        vm.startPrank(users.owner);
        multiDepositorVault.acceptOwnership();
        multiDepositorVault.setGuardianRoot(users.guardian, RANDOM_BYTES32);
        multiDepositorVault.setProvisioner(address(provisioner));
        priceAndFeeCalculator.setVaultAccountant(address(multiDepositorVault), users.accountant);

        priceAndFeeCalculator.setThresholds(
            address(multiDepositorVault),
            MIN_PRICE_TOLERANCE_RATIO,
            MAX_PRICE_TOLERANCE_RATIO,
            MIN_UPDATE_INTERVAL_MINUTES,
            MAX_PRICE_AGE,
            MAX_UPDATE_DELAY_DAYS
        );
        priceAndFeeCalculator.setInitialPrice(
            address(multiDepositorVault), uint128(UNIT_PRICE_PRECISION), uint32(vm.getBlockTimestamp())
        );
        currentPrice = uint128(UNIT_PRICE_PRECISION);
        priceAndFeeCalculator.setProtocolFeeRecipient(users.protocolFeeRecipient);
        priceAndFeeCalculator.setProtocolFees(PROTOCOL_TVL_FEE, PROTOCOL_PERFORMANCE_FEE);
        priceAndFeeCalculator.setVaultFees(address(multiDepositorVault), VAULT_TVL_FEE, VAULT_PERFORMANCE_FEE);

        provisioner.setDepositDetails(DEPOSIT_CAP, DEPOSIT_REFUND_TIMEOUT);
        vm.stopPrank();
    }

    function test_asyncDeposit() public {
        _setTokenDetails(IERC20(address(WETH)), false, ONE_IN_BPS, ONE_IN_BPS);
        _setTokenDetails(IERC20(address(USDC)), false, ONE_IN_BPS, ONE_IN_BPS);
        _setTokenDetails(IERC20(address(LINK)), false, 9900, 9900);

        Request memory deposit1 = _requestDeposit(users.alice, IERC20(address(WETH)), 10 ether);
        Request memory deposit2 = _requestDeposit(users.bob, IERC20(address(USDC)), 15_000e6);
        Request memory deposit3 = _requestDeposit(users.charlie, IERC20(address(LINK)), 1000 ether);
        skip(1 minutes);

        _solveRequestVault(IERC20(address(WETH)), deposit1);
        _solveRequestVault(IERC20(address(USDC)), deposit2);
        _solveRequestVault(IERC20(address(LINK)), deposit3);

        skip(10 days);
        _simulateVaultValueChange(100);

        _claimFees(false);

        skip(10 days);
        _simulateVaultValueChange(-50);

        Request memory redeem =
            _requestRedeem(users.alice, IERC20(address(WETH)), multiDepositorVault.balanceOf(users.alice), false);
        skip(1 minutes);
        _solveRequestDirect(users.bob, IERC20(address(WETH)), redeem);
    }

    function test_syncDeposit() public {
        vm.prank(users.owner);
        transferBlacklistHook.setIsVaultUnitsTransferable(address(multiDepositorVault), true);

        _setTokenDetails(IERC20(address(WETH)), true, ONE_IN_BPS, ONE_IN_BPS);
        _setTokenDetails(IERC20(address(USDC)), true, ONE_IN_BPS, ONE_IN_BPS);
        _setTokenDetails(IERC20(address(LINK)), true, 9900, 9900);

        uint256 aliceUnits = _deposit(users.alice, IERC20(address(WETH)), 10 ether);
        _deposit(users.bob, IERC20(address(USDC)), 15_000e6);
        _deposit(users.charlie, IERC20(address(LINK)), 1000 ether);
        uint256 danUnits = _deposit(users.dan, IERC20(address(LINK)), 1000 ether);
        uint256 refundableUntil = vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT;

        skip(DEPOSIT_REFUND_TIMEOUT);
        _refundDeposit(users.dan, IERC20(address(LINK)), 1000 ether, danUnits, refundableUntil);

        vm.prank(users.alice);
        multiDepositorVault.approve(address(provisioner), aliceUnits);
        vm.prank(users.alice);
        vm.expectRevert(IMultiDepositorVault.Aera__UnitsLocked.selector);
        provisioner.requestRedeem(
            IERC20(address(WETH)), aliceUnits, 1, 1, uint32(vm.getBlockTimestamp() + 1 days), 1 minutes, false
        );

        uint256 aliceUnitsBalance = multiDepositorVault.balanceOf(users.alice);
        vm.prank(users.alice);
        vm.expectRevert(IMultiDepositorVault.Aera__UnitsLocked.selector);
        multiDepositorVault.transfer(users.bob, aliceUnitsBalance);

        skip(10 days);
        _simulateVaultValueChange(100);

        _claimFees(false);

        skip(10 days);
        _simulateVaultValueChange(-50);

        _claimFees(true);

        Request memory redeem1 =
            _requestRedeem(users.alice, IERC20(address(WETH)), multiDepositorVault.balanceOf(users.alice), true);
        Request memory redeem2 =
            _requestRedeem(users.bob, IERC20(address(USDC)), multiDepositorVault.balanceOf(users.bob), true);

        skip(1 minutes);
        _solveRequestVault(IERC20(address(WETH)), redeem1);
        _solveRequestVault(IERC20(address(USDC)), redeem2);

        skip(10 days);
        _simulateVaultValueChange(100);

        _claimFees(true);

        Request memory redeem3 =
            _requestRedeem(users.charlie, IERC20(address(LINK)), multiDepositorVault.balanceOf(users.charlie), true);

        skip(1 minutes);
        _solveRequestVault(IERC20(address(LINK)), redeem3);

        assertEq(multiDepositorVault.totalSupply(), 0);
    }

    function test_pausedVault() public {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            IERC20(address(WETH)),
            TokenDetails({
                asyncDepositEnabled: true,
                asyncRedeemEnabled: true,
                syncDepositEnabled: true,
                depositMultiplier: uint16(ONE_IN_BPS),
                redeemMultiplier: uint16(ONE_IN_BPS)
            })
        );

        skip(10 days);
        _simulateVaultValueChange(int16(MAX_PRICE_TOLERANCE_RATIO) + 1);

        assertTrue(priceAndFeeCalculator.isVaultPaused(address(multiDepositorVault)));

        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultPaused.selector);
        vm.prank(users.alice);
        provisioner.deposit(IERC20(address(WETH)), 10 ether, 10 ether);

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__PriceAndFeeCalculatorVaultPaused.selector);
        provisioner.requestDeposit(
            IERC20(address(WETH)),
            10 ether,
            10 ether,
            10 ether,
            uint32(vm.getBlockTimestamp() + 1 days),
            1 minutes,
            false
        );

        vm.prank(users.alice);
        vm.expectRevert(IProvisioner.Aera__PriceAndFeeCalculatorVaultPaused.selector);
        provisioner.requestRedeem(
            IERC20(address(WETH)),
            10 ether,
            10 ether,
            10 ether,
            uint32(vm.getBlockTimestamp() + 1 days),
            1 minutes,
            false
        );

        vm.prank(users.owner);
        priceAndFeeCalculator.unpauseVault(address(multiDepositorVault), currentPrice, uint32(vm.getBlockTimestamp()));
        uint256 aliceUnits = _deposit(users.alice, IERC20(address(WETH)), 10 ether);

        skip(DEPOSIT_REFUND_TIMEOUT + 1);
        Request memory redeem = _requestRedeem(users.alice, IERC20(address(WETH)), aliceUnits, true);

        _simulateVaultValueChange(int16(MAX_PRICE_TOLERANCE_RATIO) + 1);

        Request[] memory requests = new Request[](1);
        requests[0] = redeem;

        vm.prank(users.owner);
        vm.expectRevert(IPriceAndFeeCalculator.Aera__VaultPaused.selector);
        provisioner.solveRequestsVault(IERC20(address(WETH)), requests);
    }

    function _solveRequestVault(IERC20 token, Request memory request) internal {
        Request[] memory requests = new Request[](1);
        requests[0] = request;

        uint256 solverBefore = token.balanceOf(address(users.owner));
        uint256 provisionerTokensBefore = token.balanceOf(address(provisioner));
        uint256 provisionerUnitsBefore = multiDepositorVault.balanceOf(address(provisioner));
        uint256 userTokensBefore = token.balanceOf(request.user);
        uint256 userUnitsBefore = multiDepositorVault.balanceOf(request.user);

        vm.prank(users.owner);
        provisioner.solveRequestsVault(token, requests);

        if (_isRequestTypeDeposit(request.requestType)) {
            assertFalse(provisioner.asyncDepositHashes(_getRequestHash(token, request)));
            assertEq(token.balanceOf(address(provisioner)), provisionerTokensBefore - request.tokens);

            assertEq(multiDepositorVault.balanceOf(request.user), userUnitsBefore + request.units);
        } else {
            assertFalse(provisioner.asyncRedeemHashes(_getRequestHash(token, request)));
            assertEq(multiDepositorVault.balanceOf(address(provisioner)), provisionerUnitsBefore - request.units);
            assertEq(token.balanceOf(request.user), userTokensBefore + request.tokens);
        }
        assertEq(token.balanceOf(address(users.owner)), solverBefore + request.solverTip);
    }

    function _solveRequestDirect(address user, IERC20 token, Request memory request) internal {
        Request[] memory requests = new Request[](1);
        requests[0] = request;

        uint256 provisionerTokensBefore = token.balanceOf(address(provisioner));
        uint256 provisionerUnitsBefore = multiDepositorVault.balanceOf(address(provisioner));
        uint256 userTokensBefore = token.balanceOf(request.user);
        uint256 userUnitsBefore = multiDepositorVault.balanceOf(request.user);

        if (_isRequestTypeDeposit(request.requestType)) {
            ERC20Mock(address(multiDepositorVault)).mint(user, request.units);
            vm.prank(user);
            multiDepositorVault.approve(address(provisioner), request.units);
        } else {
            ERC20Mock(address(token)).mint(user, request.tokens);
            vm.prank(user);
            token.approve(address(provisioner), request.tokens);
        }

        vm.prank(user);
        provisioner.solveRequestsDirect(token, requests);

        if (_isRequestTypeDeposit(request.requestType)) {
            assertFalse(provisioner.asyncDepositHashes(_getRequestHash(token, request)));
            assertEq(token.balanceOf(address(provisioner)), provisionerTokensBefore - request.tokens);
            assertEq(multiDepositorVault.balanceOf(request.user), userUnitsBefore + request.units);
        } else {
            assertFalse(provisioner.asyncRedeemHashes(_getRequestHash(token, request)));
            assertEq(multiDepositorVault.balanceOf(address(provisioner)), provisionerUnitsBefore - request.units);
            assertEq(token.balanceOf(request.user), userTokensBefore + request.tokens);
        }
        assertEq(token.balanceOf(user), 0);
    }

    function _requestDeposit(address user, IERC20 token, uint256 tokensIn) internal returns (Request memory request) {
        uint256 solverTip = tokensIn / 100; // 1%

        (,,, uint16 depositMultiplier,) = provisioner.tokensDetails(token);
        uint256 tokensCountedForDeposit = (tokensIn - solverTip) * depositMultiplier / ONE_IN_BPS;

        uint256 numeraireAmount;
        if (address(token) == numeraire) {
            numeraireAmount = tokensCountedForDeposit;
        } else {
            numeraireAmount = oracleRegistry.getQuote(tokensCountedForDeposit, address(token), address(numeraire));
        }

        ERC20Mock(address(token)).mint(user, tokensIn);

        uint256 minUnitsOut = numeraireAmount * UNIT_PRICE_PRECISION / currentPrice;

        vm.prank(user);
        token.approve(address(provisioner), tokensIn);

        request = Request({
            requestType: RequestType.DEPOSIT_AUTO_PRICE,
            user: user,
            units: minUnitsOut,
            tokens: tokensIn,
            solverTip: solverTip,
            deadline: uint32(vm.getBlockTimestamp() + 1 days),
            maxPriceAge: 1 minutes
        });

        uint256 balanceBefore = token.balanceOf(address(provisioner));

        vm.prank(user);
        provisioner.requestDeposit(
            token, request.tokens, request.units, request.solverTip, request.deadline, request.maxPriceAge, false
        );

        assertEq(token.balanceOf(address(provisioner)), balanceBefore + request.tokens);
        assertTrue(provisioner.asyncDepositHashes(_getRequestHash(token, request)));
    }

    function _requestRedeem(address user, IERC20 token, uint256 unitsIn, bool isAutoPrice)
        internal
        returns (Request memory request)
    {
        uint256 numeraireAmount = unitsIn * currentPrice / UNIT_PRICE_PRECISION;
        uint256 minTokenOut;
        if (address(token) == numeraire) {
            minTokenOut = numeraireAmount;
        } else {
            minTokenOut = oracleRegistry.getQuote(numeraireAmount, address(numeraire), address(token));
        }

        (,,,, uint16 redeemMultiplier) = provisioner.tokensDetails(token);
        minTokenOut = minTokenOut * redeemMultiplier / ONE_IN_BPS;

        uint256 solverTip = minTokenOut / 100; // 1%
        minTokenOut -= solverTip;

        vm.prank(user);
        multiDepositorVault.approve(address(provisioner), unitsIn);

        request = Request({
            requestType: isAutoPrice ? RequestType.REDEEM_AUTO_PRICE : RequestType.REDEEM_FIXED_PRICE,
            user: user,
            units: unitsIn,
            tokens: minTokenOut,
            solverTip: isAutoPrice ? solverTip : 0,
            deadline: uint32(vm.getBlockTimestamp() + 1 days),
            maxPriceAge: 1 minutes
        });

        uint256 balanceBefore = multiDepositorVault.balanceOf(address(provisioner));

        vm.prank(user);
        provisioner.requestRedeem(
            token, request.units, request.tokens, request.solverTip, request.deadline, request.maxPriceAge, !isAutoPrice
        );

        assertEq(multiDepositorVault.balanceOf(address(provisioner)), balanceBefore + request.units);
        assertTrue(provisioner.asyncRedeemHashes(_getRequestHash(token, request)));
    }

    function _claimFees(bool expectFeesToBeClaimed) internal {
        if (!expectFeesToBeClaimed) {
            vm.expectRevert(IFeeVault.Aera__NoFeesToClaim.selector);
            vm.prank(users.feeRecipient);
            multiDepositorVault.claimFees();
            return;
        }
        uint256 balanceBefore = WETH.balanceOf(users.feeRecipient);
        uint256 protocolBefore = WETH.balanceOf(users.protocolFeeRecipient);
        (uint256 vaultFees, uint256 protocolFees) = priceAndFeeCalculator.previewFees(
            address(multiDepositorVault), IERC20(numeraire).balanceOf(address(multiDepositorVault))
        );
        vm.prank(users.feeRecipient);
        multiDepositorVault.claimFees();

        assertTrue(vaultFees > 0);
        assertTrue(protocolFees > 0);
        assertEq(WETH.balanceOf(users.feeRecipient), balanceBefore + vaultFees);
        assertEq(WETH.balanceOf(users.protocolFeeRecipient), protocolBefore + protocolFees);
    }

    function _simulateVaultValueChange(int256 percentageBps) internal {
        if (percentageBps > 0) {
            currentPrice = currentPrice * uint128((ONE_IN_BPS + uint256(percentageBps)) / ONE_IN_BPS);
            WETH.mint(
                address(multiDepositorVault),
                WETH.balanceOf(address(multiDepositorVault)) * uint256(percentageBps) / ONE_IN_BPS
            );
            USDC.mint(
                address(multiDepositorVault),
                USDC.balanceOf(address(multiDepositorVault)) * uint256(percentageBps) / ONE_IN_BPS
            );
            LINK.mint(
                address(multiDepositorVault),
                LINK.balanceOf(address(multiDepositorVault)) * uint256(percentageBps) / ONE_IN_BPS
            );
        } else {
            percentageBps = -percentageBps;

            currentPrice = uint128(currentPrice * (ONE_IN_BPS - uint256(percentageBps)) / ONE_IN_BPS);
            WETH.burn(
                address(multiDepositorVault),
                WETH.balanceOf(address(multiDepositorVault)) * uint256(percentageBps) / ONE_IN_BPS
            );
            USDC.burn(
                address(multiDepositorVault),
                USDC.balanceOf(address(multiDepositorVault)) * uint256(percentageBps) / ONE_IN_BPS
            );
            LINK.burn(
                address(multiDepositorVault),
                LINK.balanceOf(address(multiDepositorVault)) * uint256(percentageBps) / ONE_IN_BPS
            );
        }
        vm.prank(users.accountant);
        priceAndFeeCalculator.setUnitPrice(address(multiDepositorVault), currentPrice, uint32(vm.getBlockTimestamp()));
    }

    function _setTokenDetails(IERC20 token, bool isSyncDeposit, uint256 depositMultiplier, uint256 redeemMultiplier)
        internal
    {
        vm.prank(users.owner);
        provisioner.setTokenDetails(
            token,
            TokenDetails({
                asyncDepositEnabled: !isSyncDeposit,
                asyncRedeemEnabled: true,
                syncDepositEnabled: isSyncDeposit,
                depositMultiplier: uint16(depositMultiplier),
                redeemMultiplier: uint16(redeemMultiplier)
            })
        );
    }

    function _deposit(address user, IERC20 token, uint256 amount) internal returns (uint256 unitsOut) {
        (,,, uint16 depositMultiplier,) = provisioner.tokensDetails(token);

        uint256 numeraireAmount;
        if (address(token) == address(numeraire)) {
            numeraireAmount = amount;
        } else {
            numeraireAmount = oracleRegistry.getQuote(amount, address(token), address(numeraire));
        }

        ERC20Mock(address(token)).mint(user, amount);
        vm.prank(user);
        token.approve(address(multiDepositorVault), amount);
        unitsOut = numeraireAmount * depositMultiplier / ONE_IN_BPS * uint128(UNIT_PRICE_PRECISION) / currentPrice;
        uint256 balanceBefore = multiDepositorVault.balanceOf(user);
        vm.prank(user);
        provisioner.deposit(token, amount, unitsOut);

        assertEq(multiDepositorVault.balanceOf(user), balanceBefore + unitsOut);
        assertTrue(
            provisioner.syncDepositHashes(
                _getDepositHash(user, token, amount, unitsOut, uint32(vm.getBlockTimestamp() + DEPOSIT_REFUND_TIMEOUT))
            )
        );
    }

    function _refundDeposit(
        address user,
        IERC20 token,
        uint256 tokenAmount,
        uint256 unitsAmount,
        uint256 refundableUntil
    ) internal {
        uint256 tokensBefore = token.balanceOf(user);
        uint256 unitsBefore = multiDepositorVault.balanceOf(user);
        vm.prank(users.owner);
        provisioner.refundDeposit(user, token, tokenAmount, unitsAmount, refundableUntil);

        assertEq(multiDepositorVault.balanceOf(user), unitsBefore - unitsAmount);
        assertEq(token.balanceOf(user), tokensBefore + tokenAmount);
    }

    function _getRequestHash(IERC20 token, Request memory request) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                token,
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

    function _getDepositHash(
        address user,
        IERC20 token,
        uint256 tokenAmount,
        uint256 unitsAmount,
        uint256 refundableUntil
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, token, tokenAmount, unitsAmount, refundableUntil));
    }

    function _isRequestTypeDeposit(RequestType requestType) internal pure returns (bool) {
        return uint8(requestType) & 1 == 0;
    }

    function _isRequestTypeFixedPrice(RequestType requestType) internal pure returns (bool) {
        return uint8(requestType) & 2 == 2;
    }

    function _setupOracleRegistry() internal {
        linkEthOracle = new OracleMock(18);
        linkEthOracle.setLatestAnswer(8_284_400_447_024_800);
        ethLinkOracle = new OracleMock(18);
        ethLinkOracle.setLatestAnswer(int256(1e36) / 8_284_400_447_024_800);
        usdcEthOracle = new OracleMock(18);
        usdcEthOracle.setLatestAnswer(556_769_095_215_166);
        ethUsdcOracle = new OracleMock(18);
        ethUsdcOracle.setLatestAnswer(int256(1e36) / 556_769_095_215_166);
        btcEthOracle = new OracleMock(18);
        btcEthOracle.setLatestAnswer(52_534_412_552_440_540_000);
        ethBtcOracle = new OracleMock(8);
        ethBtcOracle.setLatestAnswer(1_877_000);

        mockChainlink7726Adapter = new MockChainlink7726Adapter();
        mockChainlink7726Adapter.setFeed(address(LINK), address(WETH), address(linkEthOracle));
        mockChainlink7726Adapter.setFeed(address(WETH), address(LINK), address(ethLinkOracle));
        mockChainlink7726Adapter.setFeed(address(USDC), address(WETH), address(usdcEthOracle));
        mockChainlink7726Adapter.setFeed(address(WETH), address(USDC), address(ethUsdcOracle));
        mockChainlink7726Adapter.setFeed(address(BTC), address(WETH), address(btcEthOracle));
        mockChainlink7726Adapter.setFeed(address(WETH), address(BTC), address(ethBtcOracle));

        oracleRegistry = new OracleRegistry(address(this), Authority(address(0)), 15 days);
        oracleRegistry.addOracle(address(LINK), address(WETH), IOracle(address(mockChainlink7726Adapter)));
        oracleRegistry.addOracle(address(WETH), address(LINK), IOracle(address(mockChainlink7726Adapter)));
        oracleRegistry.addOracle(address(USDC), address(WETH), IOracle(address(mockChainlink7726Adapter)));
        oracleRegistry.addOracle(address(WETH), address(USDC), IOracle(address(mockChainlink7726Adapter)));
        oracleRegistry.addOracle(address(BTC), address(WETH), IOracle(address(mockChainlink7726Adapter)));
        oracleRegistry.addOracle(address(WETH), address(BTC), IOracle(address(mockChainlink7726Adapter)));
    }
}
