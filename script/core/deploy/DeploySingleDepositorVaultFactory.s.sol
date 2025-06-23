// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import { Script, console, stdJson } from "forge-std/Script.sol";

import { SingleDepositorVault } from "src/core/SingleDepositorVault.sol";

import { SingleDepositorVaultDeployDelegate } from "src/core/SingleDepositorVaultDeployDelegate.sol";
import { SingleDepositorVaultFactory } from "src/core/SingleDepositorVaultFactory.sol";

contract DeploySingleDepositorVaultFactory is Script {
    using stdJson for string;

    function run() public returns (address v3FactoryAddress, bytes32 initCodeHash) {
        string memory path = string.concat(vm.projectRoot(), "/config/DeploySingleDepositorVaultFactory.json");
        string memory json = vm.readFile(path);

        address newOwner = json.readAddress(".newOwner");

        vm.startBroadcast();
        address deployDelegate = address(new SingleDepositorVaultDeployDelegate());
        v3FactoryAddress = address(new SingleDepositorVaultFactory(newOwner, Authority(address(0)), deployDelegate));
        vm.stopBroadcast();

        initCodeHash = keccak256(type(SingleDepositorVault).creationCode);

        console.log("SingleDepositorVaultFactory deployed at", v3FactoryAddress);
        console.log("SingleDepositorVaultFactory init-code-hash:");
        console.logBytes32(initCodeHash);
    }
}
