// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Ownable } from "@oz/access/Ownable.sol";
import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@oz/token/ERC20/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { Test } from "forge-std/Test.sol";

import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";
import { MockFeeCalculator } from "test/core/mocks/MockFeeCalculator.sol";
import { WrappedNativeTokenMock } from "test/core/mocks/WrappedNativeTokenMock.sol";
import { Constants } from "test/utils/Constants.t.sol";

struct Users {
    address stranger;
    address guardian;
    address owner;
    address alice;
    address bob;
    address charlie;
    address dan;
    address eve;
    address feeRecipient;
    address protocolFeeRecipient;
    address accountant;
}

abstract contract BaseTest is Test, Constants {
    Users public users;
    address public wrappedNative;

    ERC20Mock public feeToken;
    IFeeCalculator public mockFeeCalculator;

    address internal immutable WHITELIST = makeAddr("whitelist");
    address internal immutable BEFORE_TRANSFER_HOOK = makeAddr("beforeTransferHook");
    address internal immutable PROVISIONER = makeAddr("provisioner");
    address payable internal immutable BASE_VAULT = payable(makeAddr("baseVault"));
    address internal immutable TOKEN = makeAddr("token");
    address internal immutable AUTHORITY = makeAddr("authority");

    function setUp() public virtual {
        users = Users({
            stranger: makeAddr("stranger"),
            guardian: makeAddr("guardian"),
            owner: makeAddr("owner"),
            alice: makeAddr("alice"),
            bob: makeAddr("bob"),
            charlie: makeAddr("charlie"),
            dan: makeAddr("dan"),
            eve: makeAddr("eve"),
            feeRecipient: makeAddr("feeRecipient"),
            protocolFeeRecipient: makeAddr("protocolFeeRecipient"),
            accountant: makeAddr("accountant")
        });

        vm.mockCall(BASE_VAULT, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(users.owner));

        vm.mockCall(BASE_VAULT, abi.encodeWithSelector(bytes4(keccak256("authority()"))), abi.encode(AUTHORITY));

        feeToken = new ERC20Mock();
        mockFeeCalculator = IFeeCalculator(address(new MockFeeCalculator()));

        vm.prank(users.owner);
        wrappedNative = address(new WrappedNativeTokenMock());

        // Set the timestamp to May 1, 2024
        vm.warp(_MAY_1_2024);
    }

    function _isEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _calculateLoss(uint256 valueBefore, uint256 valueAfter) internal pure returns (uint256) {
        if (valueAfter >= valueBefore) {
            return 0;
        }
        return valueBefore - valueAfter;
    }

    function _approveToken(address from, IERC20 token, address spender, uint256 amount) internal {
        vm.prank(from);
        token.approve(spender, amount);
    }

    function _mockCanCall(address caller, address target, bytes4 selector, bool canCall) internal {
        vm.mockCall(
            AUTHORITY, abi.encodeWithSelector(Authority.canCall.selector, caller, target, selector), abi.encode(canCall)
        );
    }
}
