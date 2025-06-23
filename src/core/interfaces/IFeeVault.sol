// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";

/// @title IFeeVault
/// @notice Interface for vaults that support fees but don't have multiple depositors
interface IFeeVault {
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    event FeesClaimed(address indexed feeRecipient, uint256 fees);
    event ProtocolFeesClaimed(address indexed protocolFeeRecipient, uint256 protocolEarnedFees);
    event FeeRecipientUpdated(address indexed newFeeRecipient);
    event FeeCalculatorUpdated(address indexed newFeeCalculator);

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    error Aera__ZeroAddressFeeCalculator();
    error Aera__ZeroAddressFeeToken();
    error Aera__ZeroAddressFeeRecipient();
    error Aera__NoFeesToClaim();
    error Aera__CallerIsNotFeeRecipient();
    error Aera__CallerIsNotProtocolFeeRecipient();

    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Set the fee recipient
    /// @param newFeeRecipient The new fee recipient address
    function setFeeRecipient(address newFeeRecipient) external;

    /// @notice Claim accrued fees for msg.sender
    /// @dev Automatically claims any earned protocol fees for the protocol
    /// @return feeRecipientFees The amount of fees to be claimed by the fee recipient
    /// @return protocolFees The amount of protocol fees to be claimed by the protocol
    function claimFees() external returns (uint256 feeRecipientFees, uint256 protocolFees);

    /// @notice Claim accrued protocol fees
    /// @return protocolFees The amount of protocol fees to be claimed by the protocol
    function claimProtocolFees() external returns (uint256 protocolFees);

    /// @notice Set the fee calculator
    /// @dev newFeeCalculator can be zero, which has the effect as disabling the fee calculator
    /// @param newFeeCalculator The new fee calculator
    function setFeeCalculator(IFeeCalculator newFeeCalculator) external;

    /// @notice Get the fee calculator
    // solhint-disable-next-line func-name-mixedcase
    function feeCalculator() external view returns (IFeeCalculator);

    /// @notice Get the fee token
    // solhint-disable-next-line func-name-mixedcase
    function FEE_TOKEN() external view returns (IERC20);
}
