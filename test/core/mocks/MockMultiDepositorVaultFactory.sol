// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IBeforeTransferHook } from "src/core/interfaces/IBeforeTransferHook.sol";
import { IMultiDepositorVaultFactory } from "src/core/interfaces/IMultiDepositorVaultFactory.sol";
import { IProvisioner } from "src/core/interfaces/IProvisioner.sol";
import { MockFeeVaultFactory } from "test/core/mocks/MockFeeVaultFactory.sol";

contract MockMultiDepositorVaultFactory is MockFeeVaultFactory {
    string internal _name;
    string internal _symbol;
    IBeforeTransferHook internal _hooks;

    function setMultiDepositorVaultParameters(string memory name_, string memory symbol_, IBeforeTransferHook hooks_)
        internal
    {
        _name = name_;
        _symbol = symbol_;
        _hooks = hooks_;
    }

    function getERC20Name() external view returns (string memory) {
        return _name;
    }

    function getERC20Symbol() external view returns (string memory) {
        return _symbol;
    }

    function multiDepositorVaultParameters() external view returns (IBeforeTransferHook beforeTransferHook) {
        beforeTransferHook = _hooks;
    }
}
