// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";

import { DelayedFeeCalculator } from "src/core/DelayedFeeCalculator.sol";
import { VaultAccruals, VaultSnapshot } from "src/core/Types.sol";

contract MockDelayedFeeCalculator is DelayedFeeCalculator {
    constructor(address owner_, Authority authority_, uint256 disputePeriod)
        DelayedFeeCalculator(owner_, authority_, disputePeriod)
    { }

    function setVaultSnapshot(address vault, VaultSnapshot memory snapshot) external {
        _vaultSnapshots[vault] = snapshot;
    }

    function setVaultAccruals(address vault, VaultAccruals memory accruals) external {
        _vaultAccruals[vault] = accruals;
    }

    function getVaultSnapshot(address vault) external view returns (VaultSnapshot memory) {
        return _vaultSnapshots[vault];
    }

    function getVaultAccruals(address vault) external view returns (VaultAccruals memory) {
        return _vaultAccruals[vault];
    }
}
