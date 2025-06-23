// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";

import { SingleDepositorVaultDeployDelegate } from "src/core/SingleDepositorVaultDeployDelegate.sol";
import { SingleDepositorVaultFactory } from "src/core/SingleDepositorVaultFactory.sol";
import { ISingleDepositorVaultFactory } from "src/core/interfaces/ISingleDepositorVaultFactory.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract TestBaseFactory is BaseTest {
    address internal immutable FACTORY_OWNER = makeAddr("FACTORY_OWNER");
    address internal immutable HOOKS = makeAddr("HOOKS");
    address internal immutable ORACLE_REGISTRY = makeAddr("ORACLE_REGISTRY");

    ISingleDepositorVaultFactory public factory;

    function setUp() public virtual override {
        super.setUp();
        _deploySingleDepositorVaultFactory();
    }

    function _deploySingleDepositorVaultFactory() internal virtual {
        address deployDelegate = address(new SingleDepositorVaultDeployDelegate());
        factory = ISingleDepositorVaultFactory(
            address(new SingleDepositorVaultFactory(FACTORY_OWNER, Authority(address(0)), deployDelegate))
        );
    }
}
