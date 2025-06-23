// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Create2 } from "@oz/utils/Create2.sol";
import { BaseVault } from "src/core/BaseVault.sol";
import { BaseVaultFactory } from "src/core/BaseVaultFactory.sol";

/// @title ComputeBaseVaultAddressLens
/// @notice A lens for computing the address of a BaseVault deployed by a BaseVaultFactory
contract ComputeBaseVaultAddressLens {
    /// @notice Computes the address of a BaseVault deployed by a BaseVaultFactory
    /// @param baseVaultFactory The address of the BaseVaultFactory
    /// @param salt The salt used to deploy the BaseVault
    /// @return The address of the BaseVault
    function computeBaseVaultAddress(BaseVaultFactory baseVaultFactory, bytes32 salt) public pure returns (address) {
        bytes32 creationCodeHash = keccak256(type(BaseVault).creationCode);

        return Create2.computeAddress(salt, creationCodeHash, address(baseVaultFactory));
    }
}
