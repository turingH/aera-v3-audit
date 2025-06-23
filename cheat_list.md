## Aera V3 Audit Cheat List (Compressed)

### UniswapV3DexHooks
1. () Uses a numeraire token for unified value measurement.
2. () Loss control enforced in `_enforceSlippageLimitAndDailyLoss`.
3. () Multi-hop swaps validated by first/last token extraction.
4. () Only final value change matters; intermediate hops ignored.

### Uniswap V3 Path Validation
5. () Path length must be `23 * n + 20` bytes (n hops).
6. () `tokenIn` and `tokenOut` parsed from the path; invalid when equal.
7. () Combined checks reject 20‑byte paths automatically.

### Ownership Transfer Pattern
8. () `Auth2Step` implements two-step transfers allowing cancellation by setting `pendingOwner` to `address(0)`.
9. () Current owner retains control until `acceptOwnership`.

### Provisioner Request Flow
10. () Users create requests via `requestDeposit` or `requestRedeem` transferring tokens/units to the Provisioner.
11. () Vault solving (`solveRequestsVault`) mints/burns units through `enter()`/`exit()` using oracle-based pricing and is restricted by `requiresAuth` (see `Provisioner.sol` line 294).
12. () Direct solving supports only fixed-price requests and transfers existing vault units or tokens from the solver to `request.user`; no minting occurs (see `_solveDepositDirect` lines 776-782 and `_solveRedeemDirect` lines 816-820).
13. () Deposit cap enforcement occurs only when vault units are minted. `deposit` and `mint` call `_requireDepositCapNotExceeded` before `_syncDeposit` (see `Provisioner.sol` lines 117-128 and 141-150). Vault-solving functions `_solveDepositVaultAutoPrice` and `_solveDepositVaultFixedPrice` check `_guardDepositCapExceeded` before calling `enter()` (lines 541-552 and 598-610). `_solveDepositDirect` merely transfers existing units without minting, so the cap is unchanged (lines 764-791).
14. () There are **no reward or incentive contracts** anywhere in the code base.
    - Searching `src/` for keywords `reward`, `incentive`, or `staking` returns
      no results.
    - Request functions (`requestDeposit`, `requestRedeem`) simply transfer
      assets to the `Provisioner` and emit events; they do not increment any
      participation counters or call external reward modules.
    - Functions such as `solveRequestsVault` and `solveRequestsDirect` never
      allocate tokens beyond the requested amounts, and there is no
      `allocateRewards` or similar function in the repository.
15. () Solver tips are accumulated and paid once per batch.
16. () Deposits deduct tips before entering the vault; `_solveDepositVaultAutoPrice` keeps the tip and deposits `tokens - solverTip` (see `src/core/Provisioner.sol` lines 520-552).
17. () Redeems exit with the full amount, then transfer `tokenOut - solverTip` to the user; `_solveRedeemVaultAutoPrice` retains the tip (lines 650-681).
18. () `solveRequestsVault` sends the accumulated tips from the Provisioner to the solver at the end of the batch (lines 336-349).

### Fee Calculation
19. () `DelayedFeeCalculator` records snapshots; fees accrue after the dispute period.
20. () TVL and performance fees use time-weighted averages and monotonic highest profit tracking.
21. () Pausing halts price updates but fee claims remain allowed. `previewFees` simply reads accrued amounts, and `claimFees` is restricted to the fee recipient.

### Rounding & Numeraire
22. () Deposits and redemptions use floor rounding; mint calculations use ceiling rounding when required.
23. () `_convertToNumeraire` converts token amounts using the vault's oracle registry.

### Slippage Hooks
24. () Trades call `_enforceSlippageLimitAndDailyLoss` which
  1. checks per-trade slippage limit,
  2. updates and checks cumulative daily loss,
  3. resets daily counters when a new day starts.

### KyberSwapDexHooks Fee Configuration
25. () `_processSwapHooks` rejects any fee receivers:
  `require(desc.feeReceivers.length == 0)` in `KyberSwapDexHooks.sol` lines 45-52.
26. () The interface declares `error AeraPeriphery__FeeReceiversNotEmpty()` in `IKyberSwapDexHooks.sol` line 15.
27. () Unit tests at `KyberSwapDexHooks.t.sol` lines 197-231 and 426-451 confirm swaps revert when fee receivers are provided.

### Deadline Validation
28. () All solver functions verify `request.deadline >= block.timestamp` and refund expired requests. Example check in `_solveDepositDirect` (see `Provisioner.sol` lines 768-790).
29. () `requestDeposit` and `requestRedeem` require the deadline to be in the future and within `MAX_SECONDS_TO_DEADLINE` (365 days). See `Provisioner.sol` lines 189-197 and 230-237; constant defined at `Constants.sol` line 140.
30. () `Request` struct stores this `deadline` parameter for each request (`Types.sol` lines 251-265).

### Request Cancellation Mechanics
31. () `refundRequest()` only permits early cancellation when the caller is authorized or the deadline has passed. See `Provisioner.sol` lines 262-289.
32. () Unit test `Provisioner.t.sol` lines 1737-1769 demonstrates unauthorized callers revert before the deadline.
33. () Regular users therefore cannot revoke pending requests; they remain valid until executed or expired.

### Vault Architecture
34. () Each `Provisioner` manages a single `MultiDepositorVault` deployed via the factory.
35. () Vault tokens are isolated per vault and cannot be shared across vaults.
36. () Batch operations cache price data once per batch to prevent intra-batch price changes.

### Atomicity & Reentrancy
37. () `nonReentrant` modifier guards `solveRequestsVault` and `solveRequestsDirect`.
38. () Request hashes are marked used before processing but revert on failure, preserving state.
39. () In `_solveRedeemDirect`, the request hash is cleared before `safeTransfer`; if the vault's `beforeTransfer` hook reverts, `SafeERC20` reverts the entire call so the hash remains intact. See `Provisioner.sol` lines 812-830, `MultiDepositorVault.sol` lines 108-125, and `TransferWhitelistHook.sol` lines 49-54.
40. () `MultiDepositorVault.exit` burns units before transferring tokens.

### Fee Accrual vs Claiming
41. () `_accrueFees` only updates accounting variables; actual token transfers occur in `claimFees`.
42. () Deposits or redeems after a snapshot do not alter fees. `_accrueFees` uses `Math.min` on unit price and total supply to compute TVL, isolating each accrual period. See `PriceAndFeeCalculator.sol` lines 332-369 and `DelayedFeeCalculator.sol` lines 68-90, 147-150.
### Fee Claims Caller Context
43. () `FeeVault.claimFees` invokes the calculator with the vault's balance. See `FeeVault.sol` lines 105-110.
44. () `BaseFeeCalculator.claimFees` indexes `_vaultAccruals[msg.sender]` because the vault contract calls this function. See `BaseFeeCalculator.sol` lines 102-118.
45. () Unit test `BaseFeeCalculator.t.sol` lines 188-198 calls `claimFees` with `vm.prank(BASE_VAULT)`, confirming the caller is the vault.
46. () `FeeVault.claimProtocolFees` calls `feeCalculator.claimProtocolFees` using
    `FEE_TOKEN.balanceOf(address(this))`. Therefore `msg.sender` inside
    `claimProtocolFees` is the vault (see `FeeVault.sol` lines 129-144 and
    `BaseFeeCalculator.sol` lines 126-139).
47. () `_beforeClaimProtocolFees` in `DelayedFeeCalculator` accrues fees for
    `msg.sender`, which is always the vault. External callers therefore never
    corrupt `_vaultAccruals` or `_vaultSnapshots`; the protocol-fee recipient is
    checked only after the calculator call (see `DelayedFeeCalculator.sol`
    lines 154-158 and `FeeVault.sol` lines 135-136).

### Fee Claim Order
48. () `BaseFeeCalculator.claimFees` subtracts accrued amounts from storage before any transfer. The function decreases `accruedFees` and `accruedProtocolFees` in `_vaultAccruals[msg.sender]` before returning. See `BaseFeeCalculator.sol` lines 103-119.
49. () `FeeVault.claimFees` obtains claim amounts, then performs transfers. The fee token (`FEE_TOKEN`) is immutable and set in the constructor (see `FeeVault.sol` lines 26-74 and 108-124).
50. () `_beforeClaimFees` in `DelayedFeeCalculator` accrues the pending snapshot and deletes it so each period is claimed once. See `DelayedFeeCalculator.sol` lines 147-150 and 186-198.
51. () Because accrual and storage updates occur before external transfers—and the fee token cannot change—reentrancy during fee claims cannot replay stale balances.


### Validation Highlights
52. () Token multipliers checked against min/max bounds.
53. () Deposit caps enforce vault size limits whenever new units are minted.
54. () `_isDepositCapExceeded` cannot overflow because Solidity 0.8.29 reverts on
  arithmetic overflow. The deposit cap is configured via `setDepositDetails`
  which requires a non-zero value. See `Provisioner.sol` lines 1-2, 384-396,
  and 920-925.
55. () Deposit cap checks use `convertUnitsToNumeraire()` with the current `unitPrice`. `priceAge` caching is only for staleness; price updates during a batch adjust the cap automatically (see `Provisioner.sol` lines 540-545, 598-603 and `PriceAndFeeCalculator.sol` lines 250-267).
56. () Guard functions prevent solver tip underflow and deadline bypass.

### Transfer Whitelist Mechanics
57. () `updateWhitelist(address vault, address[] addresses, bool isWhitelisted)` toggles whitelist status for each address and can reverse previous removals. See `TransferWhitelistHook.sol` lines 22-39.
58. () Only callers with `requiresVaultAuth` may update the whitelist, preventing unauthorized freezes (line 25).
59. () `updateWhitelist` is executed on-chain and requires `requiresVaultAuth`; no off-chain signature or deadline exists. See `TransferWhitelistHook.sol` lines 22-39.
60. () `beforeTransfer` relies only on stored whitelist and transfer status, with no signature parameters. See `TransferWhitelistHook.sol` lines 41-55 and `AbstractTransferHook.sol` lines 24-33.
61. () `beforeTransfer()` checks both parties against the whitelist; re-whitelisting restores transfer ability. See `TransferWhitelistHook.sol` lines 41-55.
62. () The whitelist mapping is a simple boolean flag per address. Re-whitelisting sets `whitelist[vault][addr] = true` again, unlocking all vault units regardless of origin. See `TransferWhitelistHook.sol` lines 16-39.
63. () The two `require` statements in `beforeTransfer` mirror each other. Each verifies the non-`transferAgent` address is whitelisted, so skipping one check never allows both parties to bypass validation. See `TransferWhitelistHook.sol` lines 49-55 and `MultiDepositorVault.sol` lines 108-125.
64. () `MultiDepositorVault._update` always passes the vault's `provisioner` as `transferAgent`. The `from` whitelist check is skipped only when `from` equals this provisioner. If the provisioner calls `beforeTransfer` with any other `from` address, the call reverts unless that address is whitelisted. The recipient must still be whitelisted. See `MultiDepositorVault.sol` lines 108-115 and `TransferWhitelistHook.sol` lines 49-55. Unit tests at `BeforeTransferWhitelistHooks.t.sol` lines 72-98 confirm this behavior.
65. () `AbstractTransferHook.beforeTransfer` only enforces `isVaultUnitTransferable` when neither participant is the `transferAgent` nor `address(0)`. Derived hooks like `TransferWhitelistHook` and `TransferBlacklistHook` override this to validate the non-`transferAgent` address even during mint or burn. See `AbstractTransferHook.sol` lines 24-33, `TransferWhitelistHook.sol` lines 49-54, and `TransferBlacklistHook.sol` lines 41-43.

### Bridge Transfer Restrictions
66. () `MultiDepositorVault._update` calls `hook.beforeTransfer(from, to, provisioner)` for every mint, burn, or transfer, ensuring hooks run for bridge operations. See `MultiDepositorVault.sol` lines 108-125.
67. () `TransferWhitelistHook.beforeTransfer` validates both parties even when minting or burning. The non-`transferAgent` party must be whitelisted. See `TransferWhitelistHook.sol` lines 49-54.
68. () During mint operations (`from == address(0)`), the second `require` enforces the recipient `to` is whitelisted. When burning (`to == address(0)`), the first `require` validates `from`. See `TransferWhitelistHook.sol` lines 49-54.
69. () `TransferBlacklistHook.beforeTransfer` blocks sanctioned addresses as `from` or `to` even during provisioner operations. See `TransferBlacklistHook.sol` lines 41-43.
70. () Unlike the whitelist hook, `TransferBlacklistHook` has no `transferAgent` exemption: both addresses are always checked against the sanctions oracle. See `TransferBlacklistHook.sol` lines 41-43 and `TransferWhitelistHook.sol` lines 49-54.
71. () Bridge contracts designated as provisioner therefore cannot mint or transfer vault units to restricted users.
72. () Cross-chain bridging mints vault units to the vault address first. `depositForBurn` encodes `bytes32(uint160(address(vault)))` as the recipient (see `CCTPHooks.fork.t.sol` lines 147-156). `MultiDepositorVault._update` then calls `beforeTransfer(0, vault, provisioner)` requiring the vault be whitelisted. When the vault later transfers units to the user, `_update` invokes `beforeTransfer(vault, user, provisioner)` so the user must also be whitelisted (see `MultiDepositorVault.sol` lines 108-125 and `TransferWhitelistHook.sol` lines 41-55). This two-step check prevents restricted users from receiving tokens via bridge.

### Cross-Chain Whitelist Limitations
73. () `TransferWhitelistHook` stores whitelist entries per chain with no automatic synchronization. See `TransferWhitelistHook.sol` line 16.
74. () Addresses bridged to another chain are not whitelisted by default; `updateWhitelist` must be called separately on each chain. See `TransferWhitelistHook.sol` lines 22-39.
75. () If the destination address is not whitelisted, `beforeTransfer()` reverts during mint or burn, preventing redemption. See `TransferWhitelistHook.sol` lines 49-54 and `MultiDepositorVault.sol` lines 108-125.

### Request Address Binding & Bridging Behavior
76. () `struct Request` includes `address user` storing the caller at creation. See `Types.sol` lines 251-265.
77. () `requestDeposit` and `requestRedeem` set the user to `msg.sender` via `_getRequestHashParams`. See `Provisioner.sol` lines 201-217 and 242-258.
78. () `_solveDepositDirect` and `_solveRedeemDirect` always deliver assets to `request.user`. See `Provisioner.sol` lines 776-787 and 815-826.
79. () CCTP bridging uses the vault address (`bytes32(uint160(address(vault)))`) as the cross-chain recipient, not user addresses. See `CCTPHooks.fork.t.sol` lines 147-156.
80. () Direct solving does not support cross-chain address mapping. Assets always return to `request.user` on the source chain. See `Provisioner.sol` lines 764-791 and 803-830.
81. () Requests move assets to the Provisioner and record the hash on-chain; there is no off-chain signature to replay across chains. See `requestDeposit` lines 201-217 and `requestRedeem` lines 242-258.
82. () Solving functions rebuild the hash from storage using `_getRequestHash` and track usage via `asyncDepositHashes` and `asyncRedeemHashes`, preventing cross-chain reuse. See `Provisioner.sol` lines 68-72 and 1005-1030.

### Transfer Hook Design
83. () `MultiDepositorVault` stores a single `beforeTransferHook` selected at deployment. `_update()` fetches this hook and calls `hook.beforeTransfer()` once per transfer. See `MultiDepositorVault.sol` lines 49-54 and 108-114.
84. () `_setBeforeTransferHook` updates the stored hook; only one hook runs at a time. See `MultiDepositorVault.sol` lines 128-135.
85. () `TransferWhitelistHook` checks `whitelist` mappings while `TransferBlacklistHook` checks the sanctions oracle. They are independent implementations of `IBeforeTransferHook` and do not combine automatically. See `TransferWhitelistHook.sol` lines 49-55 and `TransferBlacklistHook.sol` lines 39-43.

### Forwarder Capability Scope
86. () The `_canCall` mapping is local to each deployment; there is no cross-chain synchronization. See `Forwarder.sol` lines 20-22.
87. () `addCallerCapability()` modifies this on-chain storage without bridging. See `Forwarder.sol` lines 61-69.
88. () `execute()` checks `_canCall[msg.sender][targetAndSelector]` using only on-chain data; no off-chain signatures are involved. See `Forwarder.sol` lines 33-57.
89. () Permissions must be granted separately per chain, so cross-chain replay attacks are not possible unless the owner intentionally duplicates permissions.
90. () `execute()` forwards calldata without parameter validation; permissions only reference target and selector. The target contract must handle argument checks. See `Forwarder.sol` lines 33-54.

### Request Hashing Without Signatures
91. () `asyncDepositHashes` and `asyncRedeemHashes` store used request hashes per chain. See `Provisioner.sol` lines 62-72.
92. () `_getRequestHashParams` and `_getRequestHash` compute `keccak256` over request parameters with no EIP‑712 domain. See `Provisioner.sol` lines 1005-1034.
93. () `requestDeposit` and `requestRedeem` generate these hashes and mark them used. See `Provisioner.sol` lines 204-217 and 247-249.
94. () Because no signatures are used, cross-chain domain separator vulnerabilities do not apply; each deployment tracks its own request hashes.

### Allowance Handling and Fee-on-Transfer Tokens
95. () `requestDeposit` pulls tokens with `token.safeTransferFrom(msg.sender, address(this), tokensIn)`; allowances are enforced by the token. See `Provisioner.sol` lines 201-202.
96. () `MultiDepositorVault.enter` similarly calls `token.safeTransferFrom(sender, address(this), tokenAmount)` before minting. See `MultiDepositorVault.sol` lines 67-71.
97. () Direct solving uses the same helpers: `_solveDepositDirect` (lines 776-781) and `_solveRedeemDirect` (lines 815-820) rely on `safeTransfer` and `safeTransferFrom`.
98. () The protocol never modifies allowances; standard ERC-20 tokens deduct fees from the transferred amount, so allowances remain accurate. Tokens that remove extra tokens are non-compliant and outside the threat model.

### Deposit Refund Timeout
99. () `_syncDeposit` sets `refundableUntil = block.timestamp + depositRefundTimeout` and stores it in `userUnitsRefundableUntil[msg.sender]`. See `Provisioner.sol` lines 479-489.
100. () Transfers query `areUserUnitsLocked` which returns `userUnitsRefundableUntil[user] >= block.timestamp`, so locks expire naturally when the timestamp passes. See `Provisioner.sol` lines 450-452.
101. () `depositRefundTimeout` is configured via `setDepositDetails` and must not exceed `MAX_DEPOSIT_REFUND_TIMEOUT = 30 days`. See `Provisioner.sol` lines 384-395 and `Constants.sol` lines 140-143.

### Guardian Submission Permissions
102. () `setGuardianRoot` is restricted by `requiresAuth`, so only the owner assigns each guardian's allowed operations. See `BaseVault.sol` lines 154-156.
103. () Each Merkle leaf hashes `target`, `selector`, `value`, hook addresses and optional callback data (see `BaseVault.sol` lines 608-624). This binds the exact call context to the owner's approved root.
104. () `_executeSubmit` verifies every non-static operation with `_verifyOperation`; only calls included in the guardian's root are executed. Static calls use `staticcall` and cannot modify state. See `BaseVault.sol` lines 382-418 and 608-640.
105. () Because guardians cannot change their root, they cannot add arbitrary calls. Any attempt to submit an unapproved operation fails proof verification.
106. () `_enforceDailyLoss` checks that `newLoss <= maxDailyLossInNumeraire` before returning. Both values are `uint128`, so the cast in `_enforceSlippageLimitAndDailyLoss` is safe. See `BaseSlippageHooks.sol` lines 186-212 and `IBaseSlippageHooks.sol` lines 13-23.
107. () Claiming fees is permitted while a vault is paused. `isVaultPaused` and `previewFees` simply expose stored values (see `PriceAndFeeCalculator.sol` lines 305-321). `FeeVault.claimFees` restricts withdrawals to the fee recipient via `onlyFeeRecipient` (see `FeeVault.sol` lines 43-46 and 105-116).

