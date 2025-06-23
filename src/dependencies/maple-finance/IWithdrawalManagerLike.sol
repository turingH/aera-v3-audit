// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

interface IWithdrawalManagerLike {
    function processRedemptions(uint256 maxSharesToProcess) external;
    function setManualWithdrawal(address owner, bool isManual) external;
    function manualSharesAvailable(address owner) external view returns (uint256);
}
