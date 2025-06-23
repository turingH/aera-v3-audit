## Aera V3 Audit Cheat List (Compressed)

### UniswapV3DexHooks
- Uses a numeraire token for unified value measurement.
- Loss control enforced in `_enforceSlippageLimitAndDailyLoss`.
- Multi-hop swaps validated by first/last token extraction.
- Only final value change matters; intermediate hops ignored.

### Uniswap V3 Path Validation
- Path length must be `23 * n + 20` bytes (n hops).
- `tokenIn` and `tokenOut` parsed from the path; invalid when equal.
- Combined checks reject 20‑byte paths automatically.

### Ownership Transfer Pattern
- `Auth2Step` implements two-step transfers allowing cancellation by setting `pendingOwner` to `address(0)`.
- Current owner retains control until `acceptOwnership`.

### Provisioner Request Flow
- Users create requests via `requestDeposit` or `requestRedeem` transferring tokens/units to the Provisioner.
- Vault solving (`solveRequestsVault`) mints/burns units through `enter()`/`exit()` using oracle-based pricing.
- Direct solving supports only fixed-price requests and transfers existing units from solver to user.
- Deposit cap enforcement occurs only when vault units are minted. `deposit` and `mint` call `_requireDepositCapNotExceeded` before `_syncDeposit` (see `Provisioner.sol` lines 117-128 and 141-150). Vault-solving functions `_solveDepositVaultAutoPrice` and `_solveDepositVaultFixedPrice` check `_guardDepositCapExceeded` before calling `enter()` (lines 541-552 and 598-610). `_solveDepositDirect` merely transfers existing units without minting, so the cap is unchanged (lines 764-791).

- Solver tips are accumulated and paid once per batch.

### Fee Calculation
- `DelayedFeeCalculator` records snapshots; fees accrue after the dispute period.
- TVL and performance fees use time-weighted averages and monotonic highest profit tracking.
- Pausing mechanisms and price tolerance checks protect against manipulation.

### Rounding & Numeraire
- Deposits and redemptions use floor rounding; mint calculations use ceiling rounding when required.
- `_convertToNumeraire` converts token amounts using the vault's oracle registry.

### Slippage Hooks
- Trades call `_enforceSlippageLimitAndDailyLoss` which
  1. checks per-trade slippage limit,
  2. updates and checks cumulative daily loss,
  3. resets daily counters when a new day starts.

### KyberSwapDexHooks Fee Configuration
- `_processSwapHooks` rejects any fee receivers:
  `require(desc.feeReceivers.length == 0)` in `KyberSwapDexHooks.sol` lines 45-52.
- The interface declares `error AeraPeriphery__FeeReceiversNotEmpty()` in `IKyberSwapDexHooks.sol` line 15.
- Unit tests at `KyberSwapDexHooks.t.sol` lines 197-231 and 426-451 confirm swaps revert when fee receivers are provided.

### Deadline Validation
- All solver functions verify `request.deadline >= block.timestamp` and refund expired requests. Example check in `_solveDepositDirect` (see `Provisioner.sol` lines 768-790).
- `requestDeposit` and `requestRedeem` require the deadline to be in the future and within `MAX_SECONDS_TO_DEADLINE` (365 days). See `Provisioner.sol` lines 189-197 and 230-237; constant defined at `Constants.sol` line 140.
- `Request` struct stores this `deadline` parameter for each request (`Types.sol` lines 251-265).

### Request Cancellation Mechanics
- `refundRequest()` only permits early cancellation when the caller is authorized or the deadline has passed. See `Provisioner.sol` lines 262-289.
- Unit test `Provisioner.t.sol` lines 1737-1769 demonstrates unauthorized callers revert before the deadline.
- Regular users therefore cannot revoke pending requests; they remain valid until executed or expired.

### Vault Architecture
- Each `Provisioner` manages a single `MultiDepositorVault` deployed via the factory.
- Vault tokens are isolated per vault and cannot be shared across vaults.
- Batch operations cache price data once per batch to prevent intra-batch price changes.

### Atomicity & Reentrancy
- `nonReentrant` modifier guards `solveRequestsVault` and `solveRequestsDirect`.
- Request hashes are marked used before processing but revert on failure, preserving state.
- `MultiDepositorVault.exit` burns units before transferring tokens.

### Fee Accrual vs Claiming
- `_accrueFees` only updates accounting variables; actual token transfers occur in `claimFees`.
- Deposits or redeems after a snapshot do not alter fees. `_accrueFees` uses `Math.min` on unit price and total supply to compute TVL, isolating each accrual period. See `PriceAndFeeCalculator.sol` lines 332-369 and `DelayedFeeCalculator.sol` lines 68-90, 147-150.
### Fee Claims Caller Context
- `FeeVault.claimFees` invokes the calculator with the vault's balance. See `FeeVault.sol` lines 105-110.
- `BaseFeeCalculator.claimFees` indexes `_vaultAccruals[msg.sender]` because the vault contract calls this function. See `BaseFeeCalculator.sol` lines 102-118.
- Unit test `BaseFeeCalculator.t.sol` lines 188-198 calls `claimFees` with `vm.prank(BASE_VAULT)`, confirming the caller is the vault.


### Validation Highlights
- Token multipliers checked against min/max bounds.
- Deposit caps enforce vault size limits whenever new units are minted.
- `_isDepositCapExceeded` cannot overflow because Solidity 0.8.29 reverts on
  arithmetic overflow. The deposit cap is configured via `setDepositDetails`
  which requires a non-zero value. See `Provisioner.sol` lines 1-2, 384-396,
  and 920-925.
- Guard functions prevent solver tip underflow and deadline bypass.

### Transfer Whitelist Mechanics
- `updateWhitelist(address vault, address[] addresses, bool isWhitelisted)` toggles whitelist status for each address and can reverse previous removals. See `TransferWhitelistHook.sol` lines 22-39.
- Only callers with `requiresVaultAuth` may update the whitelist, preventing unauthorized freezes (line 25).
- `beforeTransfer()` checks both parties against the whitelist; re-whitelisting restores transfer ability. See `TransferWhitelistHook.sol` lines 41-55.
- The two `require` statements operate independently. If `from` equals `transferAgent`, only the sender check is skipped; the recipient must still be whitelisted (and vice versa). See `TransferWhitelistHook.sol` lines 41-55 and `MultiDepositorVault.sol` lines 109-125.
- `AbstractTransferHook.beforeTransfer` only enforces `isVaultUnitTransferable` when neither participant is the `transferAgent` nor `address(0)`. Derived hooks like `TransferWhitelistHook` and `TransferBlacklistHook` override this to validate the non-`transferAgent` address even during mint or burn. See `AbstractTransferHook.sol` lines 24-33, `TransferWhitelistHook.sol` lines 49-54, and `TransferBlacklistHook.sol` lines 41-43.

### Bridge Transfer Restrictions
- `MultiDepositorVault._update` calls `hook.beforeTransfer(from, to, provisioner)` for every mint, burn, or transfer, ensuring hooks run for bridge operations. See `MultiDepositorVault.sol` lines 108-125.
- `TransferWhitelistHook.beforeTransfer` validates both parties even when minting or burning. The non-`transferAgent` party must be whitelisted. See `TransferWhitelistHook.sol` lines 49-54.
- During mint operations (`from == address(0)`), the second `require` enforces the recipient `to` is whitelisted. When burning (`to == address(0)`), the first `require` validates `from`. See `TransferWhitelistHook.sol` lines 49-54.
- `TransferBlacklistHook.beforeTransfer` blocks sanctioned addresses as `from` or `to` even during provisioner operations. See `TransferBlacklistHook.sol` lines 41-43.
- Bridge contracts designated as provisioner therefore cannot mint or transfer vault units to restricted users.

### Request Address Binding & Bridging Behavior
- `struct Request` includes `address user` storing the caller at creation. See `Types.sol` lines 251-265.
- `requestDeposit` and `requestRedeem` set the user to `msg.sender` via `_getRequestHashParams`. See `Provisioner.sol` lines 201-217 and 242-258.
- `_solveDepositDirect` and `_solveRedeemDirect` always deliver assets to `request.user`. See `Provisioner.sol` lines 776-787 and 815-826.
- CCTP bridging uses the vault address (`bytes32(uint160(address(vault)))`) as the cross-chain recipient, not user addresses. See `CCTPHooks.fork.t.sol` lines 147-156.

### Transfer Hook Design
- `MultiDepositorVault` stores a single `beforeTransferHook` selected at deployment. `_update()` fetches this hook and calls `hook.beforeTransfer()` once per transfer. See `MultiDepositorVault.sol` lines 49-54 and 108-114.
- `_setBeforeTransferHook` updates the stored hook; only one hook runs at a time. See `MultiDepositorVault.sol` lines 128-135.
- `TransferWhitelistHook` checks `whitelist` mappings while `TransferBlacklistHook` checks the sanctions oracle. They are independent implementations of `IBeforeTransferHook` and do not combine automatically. See `TransferWhitelistHook.sol` lines 49-55 and `TransferBlacklistHook.sol` lines 39-43.

### Forwarder Capability Scope
- The `_canCall` mapping is local to each deployment; there is no cross-chain synchronization. See `Forwarder.sol` lines 20-22.
- `addCallerCapability()` modifies this on-chain storage without bridging. See `Forwarder.sol` lines 61-69.
- `execute()` checks `_canCall[msg.sender][targetAndSelector]` using only on-chain data; no off-chain signatures are involved. See `Forwarder.sol` lines 33-57.
- Permissions must be granted separately per chain, so cross-chain replay attacks are not possible unless the owner intentionally duplicates permissions.
