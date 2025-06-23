# Prior Knowledge: Redemption Flow and State Management

## Overview
This document contains verified patterns and implementations in the Aera V3 protocol to prevent false positive vulnerability reports related to redemption flows and state inconsistencies.

## Token Flow Pattern Understanding

### Correct Redemption Flow Sequence
**File**: `src/core/Provisioner.sol`  
**Key Lines**: 239, 679-691

**CORRECT REDEMPTION FLOW:**
1. **Request Phase** (`requestRedeem()` line 239): Vault units transferred from user to Provisioner via `safeTransferFrom`
2. **Resolution Phase** (`exit()` call line 683): Units burned from Provisioner BEFORE any token transfer occurs
3. **Final Transfer** (line 690): Tokens transferred from Provisioner to user AFTER unit burning is complete

```solidity
// Line 239: Units already transferred to Provisioner during request
IERC20(MULTI_DEPOSITOR_VAULT).safeTransferFrom(msg.sender, address(this), unitsIn);

// Lines 683-690: Resolution flow
IMultiDepositorVault(MULTI_DEPOSITOR_VAULT).exit(
    address(this), token, tokenOut, request.units, address(this)  // Burns units FIRST
);
token.safeTransfer(request.user, tokenOutAfterTip);  // Then transfers tokens
```

### MultiDepositorVault Exit Function Atomicity
**File**: `src/core/MultiDepositorVault.sol`  
**Lines**: 77-88

The `exit()` function ensures atomic state consistency by burning units BEFORE transferring tokens:

```solidity
function exit(address sender, IERC20 token, uint256 tokenAmount, uint256 unitsAmount, address recipient)
    external
    whenNotPaused
    onlyProvisioner
{
    // Effects: burn units from the sender (FIRST)
    _burn(sender, unitsAmount);

    // Interactions: transfer tokens to the recipient (SECOND) 
    if (tokenAmount > 0) token.safeTransfer(recipient, tokenAmount);
}
```

**Key Point**: Units are destroyed before any external token transfers, eliminating double-spending opportunities.

## Reentrancy Protection Patterns

### Function-Level Protection
**File**: `src/core/Provisioner.sol`  
**Line**: 380

```solidity
function solveRequestsVault(IERC20 token, Request[] calldata requests) 
    external 
    requiresAuth 
    nonReentrant  // Prevents reentrancy during batch processing
{
    // Batch redemption logic
}
```

The `nonReentrant` modifier prevents reentrancy attacks during batch redemption processing.

## Unit Lifecycle State Management

### Pre-Transfer of Units During Request Creation
**File**: `src/core/Provisioner.sol`  
**Lines**: 239, 683

**Critical Understanding**: Vault units are transferred to Provisioner during request creation (`requestRedeem`), NOT during resolution (`solveRequestsVault`). This eliminates any window where:
- Units exist in user balance after token distribution
- Same units could be redeemed multiple times
- State inconsistencies could be observed

### State Transitions
```
User Balance → Provisioner Balance → Burned
     ^              ^                 ^
  Request Time   Resolution Time   Exit Function
   (line 239)     (line 683)       (line 80)
```

## Common False Positive Patterns to Avoid

### 1. "Transfer Before Burn" Misconception
**Incorrect Assumption**: Tokens are transferred to users before vault units are burned, creating inconsistent state.

**Reality**: Units are burned in the `exit()` function BEFORE any token transfers occur (MultiDepositorVault.sol lines 80-85).

### 2. "Reentrancy Window" Misconception  
**Incorrect Assumption**: There's a reentrancy window during redemption processing.

**Reality**: 
- `nonReentrant` modifier protects batch operations (Provisioner.sol line 380)
- Units are already in Provisioner's possession before resolution begins
- Atomic burn-then-transfer pattern in `exit()` function

### 3. "Double Redemption" Misconception
**Incorrect Assumption**: Same vault units could be redeemed multiple times due to delayed burning.

**Reality**:
- Units transferred to Provisioner during request creation (line 239)
- Request hash marked as used before any operations (line 665)
- Units burned atomically during `exit()` call

## Verification Checklist

When auditing redemption flows, verify:

1. ✅ Units are transferred to Provisioner during request creation
2. ✅ `exit()` function burns units before token transfers
3. ✅ `nonReentrant` modifier protects batch operations
4. ✅ Request hashes are invalidated before processing
5. ✅ No external calls between unit burning and token transfers

## Code References Summary

| File | Lines | Pattern | Description |
|------|-------|---------|-------------|
| `Provisioner.sol` | 239 | Pre-transfer | Units moved to Provisioner during request |
| `Provisioner.sol` | 380 | Reentrancy Protection | `nonReentrant` modifier on batch operations |
| `Provisioner.sol` | 665, 683-690 | Resolution Flow | Hash invalidation → exit() → token transfer |
| `MultiDepositorVault.sol` | 80-85 | Atomic Operations | Burn units before transferring tokens |

This knowledge base should prevent false positives related to redemption flow state inconsistencies and reentrancy concerns in the Aera V3 protocol. 