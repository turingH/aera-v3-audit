// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Create2 } from "@oz/utils/Create2.sol";
import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";
import { SingleDepositorVaultFactory } from "src/core/SingleDepositorVaultFactory.sol";

/// @title ComputeSingleDepositorVaultAddressLens
/// @notice A lens for computing the address of a SingleDepositorVault deployed by a SingleDepositorVaultFactory
contract ComputeSingleDepositorVaultAddressLens {
    /// @notice Computes the address of a SingleDepositorVault deployed by a SingleDepositorVaultFactory
    /// @param singleDepositorVaultFactory The address of the SingleDepositorVaultFactory
    /// @param salt The salt used to deploy the SingleDepositorVault
    /// @return The address of the SingleDepositorVault
    function computeSingleDepositorVaultAddress(SingleDepositorVaultFactory singleDepositorVaultFactory, bytes32 salt)
        public
        pure
        returns (address)
    {
        bytes32 creationCodeHash = keccak256(type(SingleDepositorVault).creationCode);

        return Create2.computeAddress(salt, creationCodeHash, address(singleDepositorVaultFactory));
    }
}
