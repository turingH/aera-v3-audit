// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Create2 } from "@oz/utils/Create2.sol";
import { MultiDepositorVault } from "src/core/MultiDepositorVault.sol";
import { MultiDepositorVaultFactory } from "src/core/MultiDepositorVaultFactory.sol";

/// @title ComputeMultiDepositorVaultAddressLens
/// @notice A lens for computing the address of a MultiDepositorVault deployed by a MultiDepositorVaultFactory
contract ComputeMultiDepositorVaultAddressLens {
    /// @notice Computes the address of a MultiDepositorVault deployed by a MultiDepositorVaultFactory
    /// @param multiDepositorVaultFactory The address of the MultiDepositorVaultFactory
    /// @param salt The salt used to deploy the MultiDepositorVault
    /// @return The address of the MultiDepositorVault
    function computeMultiDepositorVaultAddress(MultiDepositorVaultFactory multiDepositorVaultFactory, bytes32 salt)
        public
        pure
        returns (address)
    {
        bytes32 creationCodeHash = keccak256(type(MultiDepositorVault).creationCode);

        return Create2.computeAddress(salt, creationCodeHash, address(multiDepositorVaultFactory));
    }
}
