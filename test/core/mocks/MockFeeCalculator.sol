// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

contract MockFeeCalculator {
    uint256 internal vaultFees;
    uint256 internal protocolFees;
    address public protocolFeeRecipient;

    function setMockState(uint256 vaultFees_, uint256 protocolFees_, address protocolFeeRecipient_) external {
        vaultFees = vaultFees_;
        protocolFees = protocolFees_;
        protocolFeeRecipient = protocolFeeRecipient_;
    }

    function registerVault() external {
        // Do nothing
    }

    function setVaultFeeRecipient() external {
        // Do nothing
    }

    function claimFees() external view returns (uint256, uint256, address) {
        return (vaultFees, protocolFees, protocolFeeRecipient);
    }

    function claimProtocolFees() external view returns (uint256, address) {
        return (protocolFees, protocolFeeRecipient);
    }
}
