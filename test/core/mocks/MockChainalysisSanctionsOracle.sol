// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Ownable } from "@oz/access/Ownable.sol";
import { IChainalysisSanctionsOracle } from "src/dependencies/chainalysis/IChainalysisSanctionsOracle.sol";

contract MockChainalysisSanctionsOracle is IChainalysisSanctionsOracle, Ownable {
    constructor() Ownable(msg.sender) { }

    mapping(address => bool) private sanctionedAddresses;

    function addToSanctionsList(address[] memory newSanctions) public onlyOwner {
        for (uint256 i = 0; i < newSanctions.length; i++) {
            sanctionedAddresses[newSanctions[i]] = true;
        }
    }

    function removeFromSanctionsList(address[] memory removeSanctions) public onlyOwner {
        for (uint256 i = 0; i < removeSanctions.length; i++) {
            sanctionedAddresses[removeSanctions[i]] = false;
        }
    }

    function isSanctioned(address addr) public view returns (bool) {
        return sanctionedAddresses[addr] == true;
    }
}
