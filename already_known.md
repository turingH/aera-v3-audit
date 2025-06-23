# Already Known Issues

## Lack of User-Controlled Request Revocation

- **Root cause**: `refundRequest()` only allows early cancellation when the caller is authorized. The original request creator cannot revoke before the deadline expires.
- **Code reference**: [`Provisioner.sol` lines 262-266](./src/core/Provisioner.sol#L262-L266) enforce this restriction.
- **Impact**: Pending requests remain executable by solvers until expiration, exposing users to unwanted executions if market conditions change.

## Vault Unit Refund Blocked by Whitelist

- **Root cause**: `refundRequest()` sends vault units back with `safeTransfer`. The transfer triggers `beforeTransfer` checks that reject recipients not on the whitelist. Users removed from the whitelist after requesting a redeem cannot receive their units back.
- **Code reference**: [`Provisioner.sol` lines 281-286](./src/core/Provisioner.sol#L281-L286) handle the refund transfer. [`TransferWhitelistHook.sol` lines 49-54](./src/periphery/hooks/transfer/TransferWhitelistHook.sol#L49-L54) enforce whitelist status.
- **Impact**: Redeem refunds revert if the user is no longer whitelisted, leaving vault units stuck in the Provisioner until re-whitelisted.

