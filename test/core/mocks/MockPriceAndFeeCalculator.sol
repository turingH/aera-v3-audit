// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";

import { PriceAndFeeCalculator } from "src/core/PriceAndFeeCalculator.sol";
import { VaultAccruals, VaultPriceState } from "src/core/Types.sol";
import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";

contract MockPriceAndFeeCalculator is PriceAndFeeCalculator {
    constructor(IERC20 numeraire, IOracleRegistry oracleRegistry, address owner_, Authority authority_)
        PriceAndFeeCalculator(numeraire, oracleRegistry, owner_, authority_)
    { }

    function accrueFees(address vault, uint256 price, uint256 timestamp) external {
        _accrueFees(vault, price, timestamp);
    }

    function setVaultPriceState(address vault, VaultPriceState memory priceState) external {
        _vaultPriceStates[vault] = priceState;
    }

    function setVaultAccruals(address vault, VaultAccruals memory accruals) external {
        _vaultAccruals[vault] = accruals;
    }

    function getVaultPriceState(address vault) external view returns (VaultPriceState memory) {
        return _vaultPriceStates[vault];
    }

    function getVaultAccruals(address vault) external view returns (VaultAccruals memory) {
        return _vaultAccruals[vault];
    }
}
