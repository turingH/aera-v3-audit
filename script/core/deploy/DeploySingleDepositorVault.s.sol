// SPDX-License-Identifier: UNLICENSED
// solhint-disable no-console
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { Script, console, stdJson } from "forge-std/Script.sol";
import { BaseVaultParameters, FeeVaultParameters } from "src/core/Types.sol";
import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";
import { ISingleDepositorVaultFactory } from "src/core/interfaces/ISingleDepositorVaultFactory.sol";
import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

contract DeploySingleDepositorVault is Script {
    using stdJson for string;

    error ExpectedAddressRequired();
    error VaultDeploymentFailed();

    /// @notice Deploy a new SingleDepositorVault using the factory
    /// @return deployedVault The address of the deployed vault
    function run() public virtual returns (address deployedVault) {
        return runFromSpecifiedConfigPath("/config/DeploySingleDepositorVault.json", true);
    }

    /// @notice Deploy a new SingleDepositorVault using the factory with specified config path
    /// @param configPath Path to the configuration file
    /// @param broadcast Whether to broadcast the transaction
    /// @return deployedVault The address of the deployed vault
    function runFromSpecifiedConfigPath(string memory configPath, bool broadcast)
        public
        returns (address deployedVault)
    {
        // Get vault parameters and config from config file
        (
            address factory,
            bytes32 salt,
            string memory description,
            BaseVaultParameters memory baseVaultParameters,
            FeeVaultParameters memory feeVaultParameters,
            address expectedVaultAddress
        ) = _getVaultParams(configPath);

        if (broadcast) {
            vm.startBroadcast();
        }

        // Deploy vault using factory
        deployedVault = ISingleDepositorVaultFactory(factory).create(
            salt, description, baseVaultParameters, feeVaultParameters, expectedVaultAddress
        );

        console.log("Deployed vault address:", deployedVault);

        // Basic validation
        if (deployedVault == address(0)) {
            revert VaultDeploymentFailed();
        }

        if (broadcast) {
            vm.stopBroadcast();
        }
    }

    /// @notice Get vault parameters from config file
    /// @param relFilePath Relative path to config file
    /// @return factory Factory address
    /// @return salt Salt for deployment (0 if not specified)
    /// @return description Vault description
    /// @return baseVaultParameters Base vault parameters struct
    /// @return feeVaultParameters Single depositor vault parameters struct
    /// @return expectedVaultAddress Expected vault address (0 if not specified)
    function _getVaultParams(string memory relFilePath)
        internal
        view
        returns (
            address factory,
            bytes32 salt,
            string memory description,
            BaseVaultParameters memory baseVaultParameters,
            FeeVaultParameters memory feeVaultParameters,
            address expectedVaultAddress
        )
    {
        string memory path = string.concat(vm.projectRoot(), relFilePath);
        string memory json = vm.readFile(path);

        // Read basic parameters
        factory = json.readAddress(".factory");
        description = json.readString(".description");

        // Read optional salt and expected address
        // Note: readUint will revert if the value doesn't exist
        uint256 saltInt;
        bytes memory rawValue = vm.parseJson(json, ".salt");
        if (rawValue.length > 0) {
            saltInt = json.readUint(".salt");
            salt = bytes32(saltInt);

            expectedVaultAddress = json.readAddress(".expectedAddress");
        } else {
            salt = bytes32(0);
            expectedVaultAddress = address(0);
        }

        baseVaultParameters = BaseVaultParameters({
            owner: json.readAddress(".owner"),
            authority: Authority(json.readAddress(".authority")),
            submitHooks: ISubmitHooks(json.readAddress(".submitHooks")),
            whitelist: IWhitelist(json.readAddress(".whitelist"))
        });

        console.log("Factory:", factory);
        console.log("Owner:", baseVaultParameters.owner);
        console.log("Authority:", address(baseVaultParameters.authority));
        console.log("Hook:", address(baseVaultParameters.submitHooks));
        console.log("Description:", description);
        console.log("Salt (as bytes32):");
        console.logBytes32(salt);
        console.log("Salt (as uint):", uint256(salt));
        if (expectedVaultAddress != address(0)) {
            console.log("Expected address:", expectedVaultAddress);
        }

        // Read single depositor vault parameters
        feeVaultParameters = FeeVaultParameters({
            feeCalculator: IFeeCalculator(json.readAddress(".feeCalculator")),
            feeToken: IERC20(json.readAddress(".feeToken")),
            feeRecipient: json.readAddress(".feeRecipient")
        });
    }
}
