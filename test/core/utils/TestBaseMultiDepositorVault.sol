// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import { MultiDepositorVault } from "src/core/MultiDepositorVault.sol";

import { Create2 } from "@oz/utils/Create2.sol";
import { MultiDepositorVaultDeployDelegate } from "src/core/MultiDepositorVaultDeployDelegate.sol";
import { MultiDepositorVaultFactory } from "src/core/MultiDepositorVaultFactory.sol";
import { BaseVaultParameters, ERC20Parameters, FeeVaultParameters } from "src/core/Types.sol";
import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";
import { IMultiDepositorVaultFactory } from "src/core/interfaces/IMultiDepositorVaultFactory.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

contract TestBaseMultiDepositorVault is BaseTest {
    address internal immutable FACTORY_OWNER = makeAddr("FACTORY_OWNER");
    address internal immutable HOOKS = makeAddr("HOOKS");

    address public hooks;
    MultiDepositorVault public vault;
    IBeforeTransferHook public beforeTransferHook;
    BaseVaultParameters public baseVaultParameters;
    FeeVaultParameters public feeVaultParameters;
    ERC20Parameters public erc20Parameters;
    IMultiDepositorVaultFactory public factory;
    address public deployDelegate;

    function setUp() public virtual override {
        super.setUp();

        _deployMultiDepositorVaultFactory();
        _init();

        address expectedVaultAddress =
            Create2.computeAddress(RANDOM_BYTES32, keccak256(type(MultiDepositorVault).creationCode), address(factory));

        vm.prank(FACTORY_OWNER);
        _deployAeraV3Contracts(RANDOM_BYTES32, expectedVaultAddress);
    }

    function _init() internal {
        baseVaultParameters = BaseVaultParameters({
            owner: users.owner,
            authority: Authority(address(0xabcd)),
            submitHooks: ISubmitHooks(address(0)),
            whitelist: IWhitelist(WHITELIST)
        });

        vm.mockCall(
            address(baseVaultParameters.whitelist),
            abi.encodeWithSelector(IWhitelist.isWhitelisted.selector, users.guardian),
            abi.encode(true)
        );

        feeVaultParameters = FeeVaultParameters({
            feeCalculator: mockFeeCalculator,
            feeToken: feeToken,
            feeRecipient: users.feeRecipient
        });
        erc20Parameters = ERC20Parameters({ name: "MultiDepositorERC20", symbol: "MDERC20" });
        beforeTransferHook = IBeforeTransferHook(HOOKS);
    }

    function _deployMultiDepositorVaultFactory() internal virtual {
        deployDelegate = address(new MultiDepositorVaultDeployDelegate());
        factory = IMultiDepositorVaultFactory(
            address(new MultiDepositorVaultFactory(FACTORY_OWNER, Authority(address(0)), deployDelegate))
        );
    }

    function _deployAeraV3Contracts(bytes32 salt_, address expectedAddress) internal {
        address deployedVault = factory.create(
            salt_,
            "Test Vault",
            erc20Parameters,
            baseVaultParameters,
            feeVaultParameters,
            beforeTransferHook,
            expectedAddress
        );

        vault = MultiDepositorVault(payable(deployedVault));
    }
}
