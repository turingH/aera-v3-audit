# Smart Contract Audit Prior Knowledge

## Risk Management Architecture Understanding

### Two-Tier Risk Control Systems
The slippage hooks implement a two-tier risk management system by design:

1. **Per-trade slippage limits (percentage-based)**: Validates individual trade reasonableness
2. **Daily cumulative loss caps (absolute amount)**: Prevents excessive aggregate losses

These mechanisms serve different purposes and may legitimately conflict when daily limits are approached. This is intentional risk management behavior, not a contradiction.

**Code Reference**: `BaseSlippageHooks.sol` lines 175-210
- `_enforceSlippageLimitAndDailyLoss()` calls both checks sequentially
- Sequential validation is by design: slippage first, then daily loss accumulation
- Failure at daily loss stage is expected behavior when approaching daily limits

```solidity
// Line 185-197 in BaseSlippageHooks.sol
function _enforceSlippageLimitAndDailyLoss(uint256 valueBefore, uint256 valueAfter)
    internal
    returns (uint128 cumulativeDailyLossInNumeraire)
{
    State storage state = _vaultStates[msg.sender];
    uint256 loss;
    unchecked {
        loss = valueBefore - valueAfter;
    }
    
    // Requirements: enforce slippage
    _enforceSlippageLimit(state, loss, valueBefore);
    
    // Effects: increase cumulative daily loss
    cumulativeDailyLossInNumeraire = uint128(_enforceDailyLoss(state, loss));
    state.cumulativeDailyLossInNumeraire = cumulativeDailyLossInNumeraire;
}
```

## Sequential Validation Pattern Recognition

Sequential validation patterns where later checks may fail even when earlier checks pass are common in multi-tier risk management systems. This pattern should **NOT** be flagged as contradictory unless:

1. The later check invalidates the earlier check's purpose
2. There's actual economic harm to legitimate users  
3. The design creates exploitable attack vectors

**Code Reference**: `BaseSlippageHooks.sol` lines 185-197

The pattern: `_enforceSlippageLimit()` → `_enforceDailyLoss()` represents layered security, not conflicting requirements.

```solidity
// Line 219-225: Per-trade slippage validation
function _enforceSlippageLimit(State storage state, uint256 loss, uint256 valueBefore) internal view {
    require(
        loss * MAX_BPS <= valueBefore * state.maxSlippagePerTrade,
        AeraPeriphery__ExcessiveSlippage(loss, valueBefore, state.maxSlippagePerTrade)
    );
}

// Line 195-208: Daily cumulative loss validation  
function _enforceDailyLoss(State storage state, uint256 loss) internal returns (uint256 newLoss) {
    uint32 day = uint32(block.timestamp / 1 days);
    if (state.currentDay != day) {
        state.currentDay = day;
        state.cumulativeDailyLossInNumeraire = 0;
    }
    
    newLoss = state.cumulativeDailyLossInNumeraire + loss;
    
    require(
        newLoss <= state.maxDailyLossInNumeraire,
        AeraPeriphery__ExcessiveDailyLoss(newLoss, state.maxDailyLossInNumeraire)
    );
}
```

## Access Control and Attack Vector Analysis

When evaluating potential "attacks" involving exhausting limits or creating denial-of-service:

1. **Check if attackers need legitimate vault access** (`requiresVaultAuth`)
2. **Verify if attacks require attackers to incur real costs**
3. **Determine if there's actual profit motive for the attacker**

**Code Reference**: `BaseSlippageHooks.sol` lines 39, 46

Both `setMaxDailyLoss()` and `setMaxSlippagePerTrade()` require vault authorization, limiting who can manipulate these parameters.

```solidity
// Line 39: Requires vault owner authorization
function setMaxDailyLoss(address vault, uint128 maxLoss) external requiresVaultAuth(vault) {
    _vaultStates[vault].maxDailyLossInNumeraire = maxLoss;
    emit UpdateMaxDailyLoss(vault, maxLoss);
}

// Line 46: Requires vault owner authorization  
function setMaxSlippagePerTrade(address vault, uint16 newMaxSlippage) external requiresVaultAuth(vault) {
    require(newMaxSlippage < MAX_BPS, AeraPeriphery__MaxSlippagePerTradeTooHigh(newMaxSlippage));
    _vaultStates[vault].maxSlippagePerTrade = newMaxSlippage;
    emit UpdateMaxSlippage(vault, newMaxSlippage);
}
```

## Mathematical Validation Requirements

**CRITICAL**: Always verify mathematical examples in issue descriptions:

1. **Check arithmetic calculations for accuracy**
2. **Ensure comparison operators are correct** 
3. **Validate that claimed inequalities actually demonstrate the stated problem**

### Common Mathematical Errors to Watch For:

- Incorrect addition/subtraction in loss calculations
- Wrong inequality directions (< vs > vs ≤ vs ≥)
- Misunderstanding of percentage calculations
- Confusion between basis points and percentages

**Example of Invalid Math**: The claim "$99 + $0.10 = 99.10 > $100" contains a fundamental mathematical error that invalidates the entire attack scenario, since 99.10 < 100.

## State Management Understanding

### Daily Loss Reset Mechanism

**Code Reference**: `BaseSlippageHooks.sol` lines 195-200

```solidity
function _enforceDailyLoss(State storage state, uint256 loss) internal returns (uint256 newLoss) {
    uint32 day = uint32(block.timestamp / 1 days);
    if (state.currentDay != day) {
        // Effects: reset the current day and daily metrics
        state.currentDay = day;
        state.cumulativeDailyLossInNumeraire = 0;
    }
    // ... rest of function
}
```

Daily loss counters automatically reset at the start of each new day (based on `block.timestamp / 1 days`). This is normal behavior, not a vulnerability.

### State Structure Understanding

**Code Reference**: `IBaseSlippageHooks.sol` lines 12-23

```solidity
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
```

All loss calculations are performed in numeraire terms for consistency. The `maxSlippagePerTrade` is in basis points (1 = 0.01%, 10000 = 100%).

## Value Calculation Framework

### Numeraire Conversion Logic

**Code Reference**: `BaseSlippageHooks.sol` lines 232-240

```solidity
function _convertToNumeraire(uint256 amount, address token) internal view returns (uint256) {
    if (token == _getNumeraire()) {
        return amount;
    }
    
    IOracleRegistry oracleRegistry = _vaultStates[msg.sender].oracleRegistry;
    return IOracle(oracleRegistry).getQuote(amount, token, _getNumeraire());
}
```

All value comparisons use a consistent numeraire (base currency) to ensure accurate loss calculations across different tokens.

## Hook Execution Context

### Before/After Trade Flow

**Code Reference**: `BaseSlippageHooks.sol` lines 81-102 and 104-125

The hooks are designed to work with both exact input and exact output scenarios:

- `_handleBeforeExactInputSingle()`: For fixed input amount trades
- `_handleBeforeExactOutputSingle()`: For fixed output amount trades

Both functions call `_enforceSlippageLimitAndDailyLossLog()` which implements the two-tier validation system.

## Common Misunderstandings to Avoid

1. **Design vs Bug Confusion**: Multi-tier validation systems may appear contradictory but serve legitimate risk management purposes
2. **Access Control Assumptions**: Always check who can actually execute potentially harmful functions
3. **Cost-Benefit Analysis**: Real attacks must be profitable for the attacker after accounting for costs
4. **Mathematical Precision**: Verify all arithmetic before claiming numerical contradictions
5. **Temporal Mechanics**: Daily resets and time-based state changes are normal features, not vulnerabilities 