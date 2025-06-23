// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import { BaseFeeCalculator } from "src/core/BaseFeeCalculator.sol";
import { VaultAccruals } from "src/core/Types.sol";

contract MockBaseFeeCalculator is BaseFeeCalculator {
    constructor(address initialOwner, Authority initialAuthority) BaseFeeCalculator(initialOwner, initialAuthority) { }

    function previewFees(address, uint256) external pure override returns (uint256, uint256) {
        return (0, 0);
    }

    function vaultFeeState(address vault) external view returns (VaultAccruals memory) {
        return _vaultAccruals[vault];
    }

    function setVaultAccruals(address vault, VaultAccruals memory accruals) external {
        _vaultAccruals[vault] = accruals;
    }

    function calculateTvlFee(uint256 averageValue, uint256 tvlFee, uint256 timeDelta) external pure returns (uint256) {
        return _calculateTvlFee(averageValue, tvlFee, timeDelta);
    }

    function calculatePerformanceFee(uint256 profit, uint256 performanceFee) external pure returns (uint256) {
        return _calculatePerformanceFee(profit, performanceFee);
    }
}
