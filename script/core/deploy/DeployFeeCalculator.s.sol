// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Authority } from "@solmate/auth/Auth.sol";

import { Script, console } from "forge-std/Script.sol";
import { DelayedFeeCalculator } from "src/core/DelayedFeeCalculator.sol";

contract DeployFeeCalculator is Script {
    function run() public returns (address deployedFeeCalculator) {
        address owner = vm.envAddress("OWNER");
        Authority auth = Authority(vm.envAddress("AUTHORITY"));
        uint256 disputePeriod = vm.envUint("DISPUTE_PERIOD");

        console.log("Owner address:", owner);
        console.log("Authority:", address(auth));
        console.log("Dispute period:", disputePeriod);
        vm.startBroadcast();
        DelayedFeeCalculator feeCalc = new DelayedFeeCalculator(owner, auth, disputePeriod);
        deployedFeeCalculator = address(feeCalc);
        vm.stopBroadcast();

        console.log("Deployed DelayedFeeCalculator contract at:", deployedFeeCalculator);
    }
}
