# Already Known Issues

## Lack of User-Controlled Request Revocation

- **Root cause**: `refundRequest()` only allows early cancellation when the caller is authorized. The original request creator cannot revoke before the deadline expires.
- **Code reference**: [`Provisioner.sol` lines 262-266](./src/core/Provisioner.sol#L262-L266) enforce this restriction.
- **Impact**: Pending requests remain executable by solvers until expiration, exposing users to unwanted executions if market conditions change.

