// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase,ordering,foundry-test-functions
pragma solidity 0.8.29;

import { OracleData } from "src/core/Types.sol";
import { IOracle } from "src/dependencies/oracles/IOracle.sol";
import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";

import { BaseOracleRegistryTest } from "test/utils/BaseOracleRegistryTest.t.sol";

contract OracleRegistryHandler is BaseOracleRegistryTest {
    IOracleRegistry public oracleRegistry;

    address public base;
    address public quote;

    uint256 public constant BASE_DECIMALS = 18;
    uint256 public constant DEFAULT_QUOTE_AMOUNT = 1;
    uint256 public constant DEFAULT_BASE_AMOUNT = 10 ** BASE_DECIMALS;

    constructor(IOracleRegistry _oracleRegistry, address _base, address _quote) {
        oracleRegistry = _oracleRegistry;
        base = _base;
        quote = _quote;
    }

    function scheduleOracleUpdate(address oracle) external {
        if (oracle != address(0)) {
            _mockGetQuote(IOracle(oracle), DEFAULT_BASE_AMOUNT, base, quote, DEFAULT_QUOTE_AMOUNT);
        }

        vm.prank(users.owner);
        oracleRegistry.scheduleOracleUpdate(base, quote, IOracle(oracle));
    }

    function commitOracleUpdate() external {
        oracleRegistry.commitOracleUpdate(base, quote);
    }

    function cancelScheduledOracleUpdate() external {
        vm.prank(users.owner);
        oracleRegistry.cancelScheduledOracleUpdate(base, quote);
    }

    function acceptPendingOracle() external {
        OracleData memory oracleData = oracleRegistry.getOracleData(base, quote);
        oracleRegistry.acceptPendingOracle(base, quote, address(this), oracleData.pendingOracle);
    }
}
