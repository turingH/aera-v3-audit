// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";

/// @title IBaseSlippageHooks
/// @notice Shared interface for all slippage hooks
interface IBaseSlippageHooks {
    ///////////////////////////////////////////////////////////
    //                         Types                         //
    ///////////////////////////////////////////////////////////

    struct State {
        /// @notice Cumulative daily loss in numeraire, used to track daily loss
        uint128 cumulativeDailyLossInNumeraire;
        /// @notice Maximum daily loss in numeraire
        uint128 maxDailyLossInNumeraire;
        /// @notice Maximum slippage per trade in basis points (1 = 0.01%)
        uint16 maxSlippagePerTrade;
        /// @notice Current day, used to track daily loss
        uint32 currentDay;
        /// @notice Oracle registry used to convert tokens to numeraire
        IOracleRegistry oracleRegistry;
    }

    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    event UpdateMaxDailyLoss(address indexed vault, uint256 maxLoss);
    event UpdateMaxSlippage(address indexed vault, uint256 maxSlippage);
    event UpdateOracleRegistry(address indexed vault, address indexed oracleRegistry);
    event TradeSlippageChecked(
        address indexed vault,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 valueBeforeNumeraire,
        uint256 valueAfterNumeraire,
        uint128 cumulativeDailyLossNumeraire
    );

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    error AeraPeriphery__CallerNotVaultOwner();
    error AeraPeriphery__ExcessiveDailyLoss(uint256 loss, uint256 maxLoss);
    error AeraPeriphery__MaxSlippagePerTradeTooHigh(uint256 maxSlippage);
    error AeraPeriphery__ExcessiveSlippage(uint256 loss, uint256 valueBefore, uint256 maxSlippage);
    error AeraPeriphery__ZeroAddressOracleRegistry();
    error AeraPeriphery__InputAmountIsZero();
    error AeraPeriphery__InputTokenIsETH();
    error AeraPeriphery__OutputTokenIsETH();

    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Set the maximum daily loss in numeraire terms
    /// @param vault The address of the vault
    /// @param maxLoss The maximum daily loss in numeraire terms
    function setMaxDailyLoss(address vault, uint128 maxLoss) external;

    /// @notice Set the maximum slippage per trade, expressed in basis points up to 10_000
    /// @param vault The address of the vault
    /// @param newMaxSlippage The new maximum slippage per trade
    function setMaxSlippagePerTrade(address vault, uint16 newMaxSlippage) external;

    /// @notice Set the oracle registry
    /// @param vault The address of the vault
    /// @param oracleRegistry The address of the oracle registry
    function setOracleRegistry(address vault, address oracleRegistry) external;

    /// @notice Get the state of a vault
    /// @param vault The address of the vault
    /// @return The state of the vault
    function vaultStates(address vault) external view returns (State memory);
}
