// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { OracleData } from "src/core/Types.sol";
import { IOracle } from "src/dependencies/oracles/IOracle.sol";
import { OracleRegistry } from "src/periphery/OracleRegistry.sol";
import { OracleRegistryHandler } from "test/periphery/invariant/OracleRegistry/OracleRegistryHandler.t.sol";
import { BaseOracleRegistryTest } from "test/utils/BaseOracleRegistryTest.t.sol";

contract OracleRegistryInvariantTest is BaseOracleRegistryTest {
    OracleRegistry public oracleRegistry;

    address public base = makeAddr("base");
    address public quote = makeAddr("quote");
    address public oracle = makeAddr("oracle");

    OracleRegistryHandler public handler;

    uint256 public constant BASE_DECIMALS = 18;
    uint256 public constant DEFAULT_QUOTE_AMOUNT = 1;
    uint256 public constant DEFAULT_BASE_AMOUNT = 10 ** BASE_DECIMALS;

    function setUp() public virtual override {
        super.setUp();

        _mockGetQuote(IOracle(oracle), DEFAULT_BASE_AMOUNT, base, quote, DEFAULT_QUOTE_AMOUNT);

        vm.prank(users.owner);
        oracleRegistry = new OracleRegistry(users.owner, Authority(address(0)), ORACLE_UPDATE_DELAY);
        vm.prank(users.owner);
        oracleRegistry.addOracle(base, quote, IOracle(oracle));

        vm.mockCall(base, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(BASE_DECIMALS));

        handler = new OracleRegistryHandler(oracleRegistry, base, quote);

        targetContract(address(handler));
    }

    function invariant_OracleCannotBeInstantlyChanged() public view {
        // ignore deprecation flag as it is set when the oracle data is scheduled for update
        OracleData memory oracleData = oracleRegistry.getOracleData(base, quote);

        assertEq(address(oracleData.oracle), oracle);

        assertEq(oracleRegistry.getQuote(DEFAULT_BASE_AMOUNT, base, quote), DEFAULT_QUOTE_AMOUNT);
    }

    function invariant_PendingOracleAndCommitTimestampMustBothBeSetOrUnset() public view {
        OracleData memory oracleData = oracleRegistry.getOracleData(base, quote);

        if (oracleData.isScheduledForUpdate) {
            assertNotEq(oracleData.commitTimestamp, 0);
            assertNotEq(address(oracleData.pendingOracle), address(0));
        } else {
            assertEq(oracleData.commitTimestamp, 0);
            assertEq(address(oracleData.pendingOracle), address(0));
        }
    }
}
