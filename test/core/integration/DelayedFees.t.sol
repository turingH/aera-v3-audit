// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { DelayedFeeCalculator } from "src/core/DelayedFeeCalculator.sol";
import { BaseVaultParameters, FeeVaultParameters, VaultAccruals, VaultSnapshot } from "src/core/Types.sol";

import { IFeeCalculator } from "src/core/interfaces/IFeeCalculator.sol";

import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";
import { Authority } from "src/dependencies/solmate/auth/Auth.sol";

import { MockFeeVault } from "test/core/mocks/MockFeeVault.sol";
import { MockFeeVaultFactory } from "test/core/mocks/MockFeeVaultFactory.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract DelayedFeesTest is BaseTest, MockFeeVaultFactory {
    MockFeeVault public feeVault;

    uint256 internal constant DISPUTE_PERIOD = 15 days;

    DelayedFeeCalculator internal feeCalculator;

    function setUp() public override {
        super.setUp();

        feeCalculator = new DelayedFeeCalculator(address(this), Authority(address(0)), DISPUTE_PERIOD);

        setGuardian(users.guardian);
        setBaseVaultParameters(
            BaseVaultParameters({
                owner: users.owner,
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            })
        );
        setFeeVaultParameters(
            FeeVaultParameters({
                feeToken: feeToken,
                feeCalculator: IFeeCalculator(address(feeCalculator)),
                feeRecipient: users.feeRecipient
            })
        );

        feeVault = new MockFeeVault();

        vm.prank(users.owner);
        feeVault.acceptOwnership();
    }

    function test_deployment_success() public view {
        assertEq(address(feeVault.feeCalculator()), address(feeCalculator));
        assertEq(address(feeVault.FEE_TOKEN()), address(feeToken));

        (VaultSnapshot memory vaultSnapshotFeeState, VaultAccruals memory baseVaultFeeState) =
            feeCalculator.vaultFeeState(address(feeVault));
        assertEq(vaultSnapshotFeeState.timestamp, 0);
        assertEq(vaultSnapshotFeeState.finalizedAt, 0);
        assertEq(vaultSnapshotFeeState.averageValue, 0);
        assertEq(vaultSnapshotFeeState.highestProfit, 0);
        assertEq(vaultSnapshotFeeState.lastFeeAccrual, vm.getBlockTimestamp());
        assertEq(vaultSnapshotFeeState.lastHighestProfit, 0);

        assertEq(baseVaultFeeState.fees.tvl, 0);
        assertEq(baseVaultFeeState.fees.performance, 0);
        assertEq(baseVaultFeeState.accruedFees, 0);
        assertEq(baseVaultFeeState.accruedProtocolFees, 0);
    }
}
