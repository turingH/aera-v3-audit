// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";
import { Script, console } from "forge-std/Script.sol";
import { Whitelist } from "src/core/Whitelist.sol";

contract DeployWhitelist is Script {
    function run() public returns (address deployedWhitelist) {
        address owner = vm.envAddress("OWNER");
        console.log("Owner address:", owner);

        address authority = vm.envAddress("AUTHORITY");
        console.log("Authority address:", authority);

        vm.startBroadcast();
        Whitelist whitelist = new Whitelist(owner, Authority(authority));
        deployedWhitelist = address(whitelist);
        vm.stopBroadcast();

        console.log("Deployed Whitelist contract at:", deployedWhitelist);
    }
}
