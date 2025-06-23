// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";

import { TestBaseFactory } from "test/core/utils/TestBaseFactory.sol";

import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { BaseVaultParameters, FeeVaultParameters } from "src/core/Types.sol";

import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { Create2 } from "@oz/utils/Create2.sol";

contract TestBaseSingleDepositorVault is TestBaseFactory {
    SingleDepositorVault public vault;

    BaseVaultParameters public baseVaultParameters;
    FeeVaultParameters public feeVaultParameters;

    function setUp() public virtual override {
        super.setUp();

        _deploySingleDepositorVaultFactory();
        _init();

        address expectedVaultAddress =
            Create2.computeAddress(RANDOM_BYTES32, keccak256(type(SingleDepositorVault).creationCode), address(factory));

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
    }

    function _deployAeraV3Contracts(bytes32 salt_, address expectedAddress) internal {
        address deployedVault =
            factory.create(salt_, "Test Vault", baseVaultParameters, feeVaultParameters, expectedAddress);
        vault = SingleDepositorVault(payable(deployedVault));
    }
}
