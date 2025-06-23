    This is the prior knowledge required when auditing the contract.
    Each group of prior knowledge is separated by `##########`


    ##########
    ## UniswapV3DexHooks 

      1.	Value Calculation Framework

      •	Uses a numeraire token (i.e., a unified pricing token) to measure the value of all transactions consistently
      •	Token value conversion is handled via the OracleRegistry
      •	BaseSlippageHooks._convertToNumeraire() is responsible for converting all tokens into the numeraire value



      2.	Loss Control Mechanism

      •	BaseSlippageHooks._enforceSlippageLimitAndDailyLoss() enforces overall loss control per transaction
      •	Loss is calculated based on the difference in numeraire value before and after the transaction
      •	Both per-trade slippage limit and daily cumulative loss limit are enforced simultaneously
      •	Loss calculations are strictly based on input vs. output value difference, and are independent of the intermediate swap path



      3.	Multi-hop Support in UniswapV3DexHooks

      •	exactInput and exactOutput functions validate token paths by extracting the first and last tokens
      •	Unified loss control is enforced through _handleBeforeExactInputSingle / _handleBeforeExactOutputSingle
      •	Multi-hop scenarios are covered by test cases such as test_exactInput_success_MultiHop



      4.	Risk Control Philosophy of the Project

      •	Does not monitor intermediate swap paths or mid-route tokens
      •	Only monitors whether the final value change is within acceptable limits
      •	Relies on Oracle-based pricing to ensure accurate value calculations
      •	Enforces daily cumulative loss limits to manage systemic risk

    ##########

    # Prior Knowledge for Uniswap V3 Path Validation Audit

    ## 1. Uniswap V3 Path Encoding Format
    Location: src/periphery/Constants.sol (lines 11-14)
    ```solidity
    // Size of the address in the path
    uint256 constant UNISWAP_PATH_ADDRESS_SIZE = 20;
    // Size of the chunk in the path (20 bytes for address + 3 bytes for uint24 fee)
    uint256 constant UNISWAP_PATH_CHUNK_SIZE = 23;
    ```

    Key Points:
    - Each path must contain at least 2 token addresses
    - Each hop requires: address(20 bytes) + fee(3 bytes) = 23 bytes
    - The final token only requires address(20 bytes)
    - Valid path length formula: 23 * n + 20 (where n is number of hops)

    ## 2. Path Length Validation Context
    Location: src/periphery/hooks/slippage/UniswapV3DexHooks.sol (lines 31-33)
    ```solidity
    require(pathLength % UNISWAP_PATH_CHUNK_SIZE == UNISWAP_PATH_ADDRESS_SIZE, AeraPeriphery__BadPathFormat());
    ```

    Common Misconceptions:
    - FALSE: The modulo check alone is insufficient for path validation
    - FALSE: A path length of 20 bytes could pass validation and execute
    - FALSE: The validation doesn't enforce minimum path requirements

    ## 3. Additional Path Processing Safeguards
    Location: src/periphery/hooks/slippage/UniswapV3DexHooks.sol (lines 35-39)
    ```solidity
    tokenIn = address(bytes20(params.path[:20]));
    tokenOut = address(bytes20(params.path[pathLength - 20:]));
    ```

    Important Context:
    - Even if a 20-byte path passes length validation, it would fail here because:
      1. Both slices would reference the same bytes
      2. This would make tokenIn == tokenOut
      3. Subsequent hooks would reject this as invalid

    ## 4. Path Encoding Implementation
    Location: test/periphery/utils/SwapUtils.sol (lines 61-77)
    ```solidity
    function encodePath(address[] memory tokens, uint24[] memory fees) internal pure returns (bytes memory) {
        require(tokens.length >= 2 && tokens.length - 1 == fees.length, "Invalid path");
        // ... path encoding logic
    }
    ```

    Key Validation:
    - Path encoding requires minimum 2 tokens
    - Number of fees must match number of hops (tokens.length - 1)

    ## 5. Common Audit Mistakes to Avoid
    1. Don't evaluate path validation in isolation
    2. Consider the entire execution flow, including:
      - Initial validation checks
      - Path byte slicing operations
      - Subsequent hook validations
    3. Verify actual path encoding/decoding implementation
    4. Test with minimum valid path length (43 bytes = 20 + 3 + 20)

    ## 6. Corrected Assumptions
    The following assumptions in the original audit report were incorrect:
    1. "Validation only checks the remainder" - It's part of a multi-layer validation system
    2. "20-byte paths could be valid" - They would fail in token extraction
    3. "No minimum length enforcement" - The code enforces it through multiple mechanisms

    ##########

    # Smart Contract Audit Prior Knowledge

    ## Contract-Specific Design Patterns
    1. Two-Step Ownership Transfer Pattern
    - File: src/core/Auth2Step.sol
    - Context: The pattern allows cancellation of pending transfers
    - Design Decision: Zero address checks are intentionally omitted for pendingOwner
    - Rationale: Enables transfer cancellation through address(0) assignment
    - Security Impact: No permanent state lock possible as owner retains control

    ## Common False Positives in Security Analysis
    1. Missing Zero Address Checks
    - Not all zero address checks are necessary
    - Context matters - some variables are designed to be freely settable
    - Example: src/core/Auth2Step.sol:46 intentionally allows address(0) for pendingOwner

    ## Security Model Assumptions
    1. Ownership Control
    - Owner maintains full control until acceptOwnership is called
    - Intermediate states (like pending transfers) should be reversible
    - Zero address assignments may be valid control mechanisms

    ## Documentation Requirements
    1. Intentional Pattern Deviations
    - Must be documented in code comments
    - Example: src/core/Auth2Step.sol:48 documents why zero check is omitted
    - Slither annotations (like slither-disable-next-line) should be explained

    ##########

    [Prior Knowledge for Smart Contract Ownership Transfer Patterns]

    1. Two-Step Ownership Transfer Pattern Context:
    - File: src/core/Auth2Step.sol
    - Purpose: Implements secure ownership transfer with confirmation step
    - Industry Standard: Widely adopted by OpenZeppelin, Solmate and other major protocols

    2. Key Security Properties:
    - Atomic Ownership Transfer is Anti-Pattern:
      - Direct transfer risks permanent loss from address errors
      - No confirmation from new owner increases operational risk
      - Example: 0xE76f5e59F26F4631D0c4e4E0C2c0Bc8d2D0B0C2D (real case of lost contract ownership due to typo)

    3. Transition Period Security Model:
    - Original owner maintains control until acceptance
    - Pending owner only has acceptance capability
    - This is NOT a security flaw but a safety feature
    - Reference Implementation: OpenZeppelin Ownable2Step.sol

    4. Common False Positives to Avoid:
    - "Multiple privileged accounts" during transition
    - "Race conditions" in acceptance process
    - "Immediate privilege revocation" recommendations

    5. Verification Points:
    - Check onlyOwner modifier on transferOwnership()
    - Verify pendingOwner can only accept ownership
    - Confirm proper event emissions
    - Test ownership transfer scenarios including:
      - Failed transfers
      - Unaccepted transfers
      - Multiple pending transfers

    ##########

    Prior Knowledge for Smart Contract Audit:

    1. Direct Solving Flow Context:
    - File: src/core/Provisioner.sol
    - Key functions: _solveDepositDirect (764-814), solveRequestsDirect (615-644)
    - Direct solving is a P2P mechanism where solvers provide existing vault shares
    - Only fixed price requests can be solved directly (checked in solveRequestsDirect)

    2. Request Creation Flow:
    - File: src/core/Provisioner.sol
    - Key function: requestDeposit (269-321)
    - All requests, including those for direct solving, must first go through request creation
    - Share/token ratios are validated during request creation

    3. Share Minting Controls:
    - Shares can only be minted through:
      a) Sync deposit flow using _syncDeposit (436-467)
      b) Vault solving flow using _solveDepositVaultAutoPrice (492-556) or _solveDepositVaultFixedPrice (558-614)
    - Direct solving transfers existing shares rather than minting new ones

    4. Common Audit Misconceptions:
    - Direct solving does NOT bypass share calculation
    - Direct solving does NOT allow arbitrary share minting
    - Direct solving is a P2P transfer mechanism, not a minting mechanism

    ##########

    Prior Knowledge for Auditing Aera V3:

    1. Architecture Isolation:
    - Each MultiDepositorVault is independently deployed via MultiDepositorVaultFactory
    - Location: MultiDepositorVaultFactory.sol L96-L178
    - Each vault has its own ERC20 token contract initialized in constructor
    - Location: MultiDepositorVault.sol L38-L44
    - Each vault has a dedicated provisioner
    - Location: MultiDepositorVault.sol L25

    2. Permission Control:
    - Vault mint/burn can only be called by its provisioner
    - Location: MultiDepositorVault.sol L31-L35
    - Provisioner is bound to specific vault at construction
    - Location: Provisioner.sol L89-L94
    - Token operations require registration in tokensDetails
    - Location: Provisioner.sol L384-L429

    3. Value Isolation:
    - Unit calculations are vault-specific via PRICE_FEE_CALCULATOR
    - Location: Provisioner.sol L924-L939
    - Deposit caps are tracked per vault
    - Location: Provisioner.sol L915-L922

    4. Request Isolation:
    - Each deposit/redeem request has unique hash bound to token
    - Location: Provisioner.sol L977-L1050
    - Request processing is token-specific
    - Location: Provisioner.sol L294-L357

    ##########

    Prior Knowledge for Smart Contract Audit:

    1. Token Flow Pattern in Provisioner.sol:
    - Location: src/core/Provisioner.sol:739-747
    - The vault exit function always transfers tokens to the specified recipient (address(this) for provisioner)
    - Token flow sequence: Vault -> Provisioner -> (User + Solver)
    - All solver tips are handled after user transfers

    2. Common Implementation Patterns:
    - Intermediary contracts (like Provisioner) typically receive assets first before distribution
    - Exit functions with recipient parameter don't bypass the contract's own balance

    3. Incorrect Assumptions to Avoid:
    - Don't assume vault functions transfer tokens directly to end users
    - Don't confuse function parameters (like recipient) with actual token flow
    - Always trace the complete token flow through all steps

    4. Critical Context:
    - The provisioner contract acts as an intermediary for all vault operations
    - Token balances are managed explicitly through the contract's own balance
    - Solver tips are calculated and distributed from the contract's remaining balance

    ##########

    Key contract validations to consider:

    1. Input Validation:
    - File: src/core/Provisioner.sol
    - Lines: 202-203
    - Context: requestDeposit() requires both tokensIn and minUnitsOut to be non-zero

    2. Price Conversion Safety:
    - File: src/core/Provisioner.sol  
    - Lines: 676-682
    - Context: Token price conversion is validated before enabling any deposit functionality

    3. Multiplier Constraints:
    - File: src/core/Provisioner.sol
    - Lines: 642-646 
    - Context: depositMultiplier has strict bounds between MIN_DEPOSIT_MULTIPLIER and ONE_IN_BPS

    4. Output Validation:
    - File: src/core/Provisioner.sol
    - Lines: 328-332
    - Context: unitsOut must meet user's minUnitsOut requirement

    Common audit misconceptions to avoid:
    1. Don't assume lack of zero-value checks without reviewing input validation
    2. Consider the full validation flow including setup requirements
    3. Check for minimum value constraints before reporting rounding issues
    4. Verify price conversion validation in token setup process

    ##########

    Prior Knowledge for Smart Contract Audit:

    1. Rounding Direction Analysis
    - Check the consistency of rounding directions across related operations
    - Example: In Provisioner.sol, both deposit and redeem use Math.Rounding.Floor
    - Location: _tokensToUnitsFloorIfActive() and _unitsToTokensFloorIfActive()

    2. Minimum Value Constraints  
    - Verify minimum value checks for critical parameters
    - Example: Provisioner.sol enforces non-zero checks for deposits and minimum multiplier thresholds
    - Location: Lines 121-122 for deposit checks, Lines 573-576 for multiplier thresholds

    3. External Dependencies
    - Understand the role of external price calculators and oracles
    - Example: PRICE_FEE_CALCULATOR handles core conversion logic with its own precision controls
    - Location: Line 121 shows delegation to external calculator

    4. Common False Positives
    - Share inflation through micro-deposits is unlikely when:
      a) Rounding directions are consistent
      b) Minimum value checks exist
      c) External price sources handle precision

    ##########

    Prior Knowledge for Smart Contract Auditing:

    1. Solidity Version Context
    - For contracts using Solidity >=0.8.0, arithmetic operations have built-in overflow checks
    - Example: src/core/Provisioner.sol uses 0.8.29, all math operations are safe by default

    2. Common Security Patterns Already Present
    - Deposit caps: src/core/Provisioner.sol:920-926 implements deposit cap validation
    - Access control: Uses Auth2Step (line 13) for critical operations
    - Price validation: Uses PriceAndFeeCalculator for safe price conversions
    - Multiplier bounds: Lines 516-524 enforce safe multiplier ranges

    3. False Assumptions in Previous Reports
    - Assumption: "Raw addition without overflow checks" - Incorrect for Solidity >=0.8.0
    - Assumption: "Silent overflow possible" - Prevented by compiler checks
    - Assumption: "No bounds on share minting" - Multiple bounds exist (caps, multipliers)

    4. Contract Interactions Context
    - MultiDepositorVault integration points
    - PriceAndFeeCalculator dependencies
    - How deposit/withdrawal flows work end-to-end

    Please validate findings against these established security patterns and version-specific features before reporting.

    ##########

    Prior Knowledge for Smart Contract Auditing:

    1. Rounding Strategies Context:
    - File: src/core/Provisioner.sol
    - Lines: 920-950
    - Floor rounding for deposits and Ceil rounding for withdrawals is a common security pattern in DeFi
    - This pattern protects the protocol by ensuring rounding always favors the vault

    2. Multiplier Safety Mechanisms:
    - File: src/core/Provisioner.sol
    - Lines: 450-460
    - Strict bounds checking for multipliers (MIN_DEPOSIT_MULTIPLIER to ONE_IN_BPS)
    - Usage of OpenZeppelin's safe math libraries

    3. Common False Positives to Avoid:
    - Assuming directional rounding is a bug when it's a security feature
    - Reporting "precision loss" without considering the intentional protective rounding mechanisms
    - Overlooking built-in compensation mechanisms like complementary rounding directions

    4. Required Analysis Steps:
    - Always check for bounds validation before reporting multiplier-related issues
    - Verify the mathematical libraries being used
    - Consider the security implications of rounding directions

    ##########

    1. Contract Design Patterns:
    - Batch processing functions may use soft-fail patterns (return without revert) when:
      * Each failure is properly logged via events
      * The function processes multiple independent items
      * Example: src/core/Provisioner.sol solveRequestsVault() 

    2. Event Logging:
    - Events are a valid form of failure notification
    - Not all failures require reverts, especially in batch operations
    - Example: src/core/Provisioner.sol _guardAmountBound() emits AmountBoundExceeded

    3. Return Values:
    - Return 0 can be a valid failure indicator when:
      * The context is clear (e.g. solver tips)
      * The failure is logged
      * The operation is part of a batch
    - Example: src/core/Provisioner.sol _solveDepositVaultAutoPrice() returns 0 on guard failures

    4. Batch Processing Requirements:
    - Individual item failures should not halt the entire batch
    - Each failure must be traceable (via events)
    - The return value should indicate success/failure
    - Example: src/core/Provisioner.sol solveRequestsVault() continues processing after individual failures

    ##########

    # Prior Knowledge for Smart Contract Auditing

    ## Contract-Specific Knowledge
    1. CalldataReader Type System
    - Location: `src/core/libraries/CalldataReader.sol`
    - Purpose: A uint256 wrapper type specifically designed for calldata offset tracking
    - Key operations: All comparisons are intentionally based on raw uint256 values
    - Usage context: Only used for calldata navigation, not for general data comparison

    2. Operation Context Handling
    - Location: `src/core/BaseVault.sol`
    - Packed data structures (like OperationContext) are processed through dedicated encoding/decoding paths
    - No direct interaction between packed data comparisons and CalldataReader operations

    3. Data Flow Separation
    - CalldataReader operations are isolated to calldata parsing
    - Packed struct comparisons use standard Solidity comparison operators
    - Merkle leaf generation uses abi.encodePacked for consistent hashing

    ## Common Audit Misconceptions
    1. Type System Assumptions
    - Custom types don't always need semantic comparison
    - Raw value comparison is valid for offset tracking
    - Not all wrapped uint256 types need normalization

    2. Packed Data Handling
    - Packed fields in structs don't affect unrelated type operations
    - Different comparison contexts (calldata vs storage) can use different comparison strategies

    3. Security Boundary Analysis
    - Separate the concerns of data parsing from data validation
    - Consider the actual data flow rather than theoretical type interactions

    ##########

    Prior Knowledge for Smart Contract Audit:

    1. Code Context Validation:
    - File: src/core/Provisioner.sol
    - The contract implements strict input validation through guard functions that are called BEFORE any mathematical operations
    - Example: _guardInsufficientTokensForTip() at line 537 validates tokens >= solverTip before unchecked subtraction

    2. Parameter Validation:
    - File: src/core/Provisioner.sol
    - Token multipliers are validated in setTokenDetails() at lines 790-797
    - MIN_DEPOSIT_MULTIPLIER, MIN_REDEEM_MULTIPLIER, and ONE_IN_BPS constants define valid ranges
    - All multipliers must be > 0 and <= ONE_IN_BPS

    3. Mathematical Safety:
    - Unchecked blocks are used intentionally after validation
    - Example: tokens - solverTip at line 537 is safe because _guardInsufficientTokensForTip ensures tokens >= solverTip
    - All mathematical operations have proper validation either through require statements or guard functions

    4. Common Audit Misconceptions:
    - The presence of unchecked does not automatically indicate missing validation
    - Guard functions should be traced to understand validation flow
    - Constants and configuration parameters may provide implicit validation

    ##########

    Prior Knowledge for Smart Contract Auditing:

    1. State Modification Scope
    - Contract: src/core/Provisioner.sol
    - Key Point: TokenDetails can only be modified through setTokenDetails() with requiresAuth modifier
    - Line Reference: Line 398-428
    - Context: This ensures multipliers cannot be changed during batch processing

    2. Transaction Atomicity
    - All operations within the same transaction are atomic
    - State changes from other transactions cannot interfere
    - This means cached values (memory) of storage variables are safe to use within a transaction

    3. Performance Optimizations
    - Using memory instead of storage for frequently accessed, read-only values is a valid optimization
    - Example: Line 302 in Provisioner.sol caches TokenDetails in memory
    - This is safe when the value cannot be modified during the transaction

    4. Authorization Patterns
    - Functions with requiresAuth modifier require separate transactions
    - Changes to authorized-only state variables cannot occur during normal operation functions
    - This creates a clear separation between state-changing admin functions and normal operations

    5. Common False Positives to Avoid
    - Assuming storage values can change during a transaction without explicit modification
    - Treating memory caching of storage values as a potential security risk
    - Overlooking transaction atomicity when analyzing state changes

    ##########

    Prior Knowledge for Smart Contract Audit:

    1. Contract-Specific Context:
      File: src/core/Provisioner.sol
      - The contract implements two separate request solving paths:
        a) solveRequestsVault (L464-L571): Authorized path through vault
        b) solveRequestsDirect (L573-L627): Direct path without vault
      - Different error handling strategies are intentional:
        - Vault path: Uses continue to handle multiple requests in batch
        - Direct path: Uses require to fail fast for individual requests
      
    2. Identified False Assumptions:
      - Assumption: Multiple implementations in same function
        Reality: Separate functions with different purposes
      - Assumption: Inconsistent error handling is a flaw
        Reality: Intentional design for different use cases
      - Assumption: Storage vs Memory usage is conflicting
        Reality: Appropriate for respective function needs

    3. Key Implementation Details:
      - Authorization:
        Line 464: `requiresAuth` for vault path
        Line 573: No auth required for direct path
      - Error Handling:
        Lines 489-493: Batch processing with continue
        Lines 575-577: Individual processing with require
      - State Management:
        Line 467: Memory for batch processing
        Line 574: Storage for single operations

    4. Business Logic Separation:
      - Vault Path: For authorized batch processing with price calculations
      - Direct Path: For permissionless direct token swaps

    ##########

    # Prior Knowledge for Fee Calculation Audits

    ## Access Control Context
    - File: src/core/DelayedFeeCalculator.sol
    - Line: 61-85
    - Key Point: Fee snapshots can only be submitted by authorized vault accountants via `onlyVaultAccountant` modifier
    - Impact: Regular users cannot manipulate fee calculations directly

    ## Time-Weighted Calculations
    - File: src/core/DelayedFeeCalculator.sol
    - Line: 172-190
    - Key Point: TVL fees use average values over time periods, not point-in-time values
    - Impact: Short-term TVL manipulation has minimal effect on fee calculations

    ## Dispute Mechanism
    - File: src/core/DelayedFeeCalculator.sol
    - Line: 76-79
    - Key Point: All snapshots have a mandatory dispute period before finalization
    - Impact: Incorrect submissions can be challenged before fees are finalized

    ## Monotonic Constraints
    - File: src/core/DelayedFeeCalculator.sol
    - Line: 73
    - Key Point: `highestProfit` must be monotonically increasing
    - Impact: Prevents manipulation through temporary profit spikes

    ## Incorrect Assumptions to Avoid
    1. Do not assume fee calculations use point-in-time TVL values
    2. Do not assume regular users can submit snapshots
    3. Do not assume snapshots are immediately finalized
    4. Do not assume profit values can be arbitrarily manipulated

    ##########

    # Prior Knowledge for Smart Contract Auditing

    ## Economic Value Focus
    - Slippage checks should focus on the final economic outcome rather than intermediate steps
    - Example: In UniswapV3DexHooks.sol, multi-hop trades only need to verify the value change between input and output tokens
    - Reference: src/periphery/hooks/slippage/UniswapV3DexHooks.sol:26-40

    ## DEX Trading Mechanics
    - Multi-hop trades aggregate slippage across all hops
    - Final slippage reflects the cumulative effect of all intermediate pools
    - Reference: test/periphery/unit/hooks/slippage/UniswapV3DexHooks.t.sol:236-280

    ## Common False Positives
    - Assuming intermediate token validation is required for multi-hop trades
    - Mistaking transaction path validation for economic validation
    - Example: The reported issue about "Multi-hop swap validation bypasses intermediate token checks"

    ## Contract Context
    - Check if the contract is focused on economic security (like slippage protection) or technical security (like pool validation)
    - Example: BaseSlippageHooks focuses on economic security through numeraire conversion
    - Reference: src/periphery/hooks/slippage/BaseSlippageHooks.sol:80-120

    ##########

    Prior Knowledge for Smart Contract Auditing:

    1. Protocol-Specific Path Encoding:
      - File: src/periphery/Constants.sol
      - Context: Uniswap V3 path encoding uses a specific format where each hop consists of a 20-byte address followed by a 3-byte fee, except for the final address
      - Constants: 
        ```solidity
        uint256 constant UNISWAP_PATH_ADDRESS_SIZE = 20;
        uint256 constant UNISWAP_PATH_CHUNK_SIZE = 23;
        ```

    2. Path Validation Mathematics:
      - For a path with N tokens and N-1 fees:
        * Total length = 20N + 3(N-1) bytes
        * When total length % 23 == 20, it guarantees:
          - At least 2 tokens (N ≥ 2)
          - Proper format of [token0, fee0, token1, ..., feeN-1, tokenN]

    3. Common False Positives:
      - Modulo-based length validation is often misunderstood as insufficient
      - When analyzing path validation, consider:
        * The protocol's path encoding format
        * The mathematical properties of the validation formula
        * Additional validation layers in related functions

    ##########

    <prior_knowledge>
    1. Contract State Management:
      - File: src/core/PriceAndFeeCalculator.sol
      - Key state variables:
        - accrualLag (line 339): Represents accumulated active time periods, not paused time
        - timestamp (line 192-213): Used for tracking state transitions
      - State transitions:
        - Active -> Paused: Records active time in accrualLag
        - Paused -> Active: Uses accumulated accrualLag for fee calculation then resets

    2. Fee Calculation Principles:
      - Fees are only calculated during active periods
      - Time delta includes both current period and previously accumulated active periods
      - accrualLag is used to ensure no fee period is double counted or missed

    3. Common Misunderstandings:
      - accrualLag does NOT represent paused time
      - Time accumulation during pauses is for tracking purposes, not fee calculation
      - The addition of accrualLag in time delta calculation is intentional and correct

    4. Code Context Dependencies:
      - The fee calculation system relies on proper state transitions
      - All time-based calculations must be viewed in context of the vault's state
      - State changes (pause/unpause) have specific effects on time tracking
    </prior_knowledge>

    ##########

    Prior Knowledge for Fee Calculation in Aera V3:

    1. TVL Fee Calculation (src/core/PriceAndFeeCalculator.sol:341-348):
      - Uses minimum of current and last total supply
      - Uses minimum of current and last price
      - This mechanism prevents gaming through supply manipulation

    2. Time Accounting (src/core/PriceAndFeeCalculator.sol:334-337):
      - Tracks accrualLag for paused periods
      - Only accrues fees for active periods
      - Prevents fee accumulation during paused states

    3. State Transition Protection (src/core/PriceAndFeeCalculator.sol:196-200):
      - Requires owner/authority approval for unpause
      - Validates price and timestamp matching
      - Prevents unauthorized state changes

    4. Fee Distribution Safety (src/core/BaseFeeCalculator.sol:126-142):
      - Fees are calculated proportionally to TVL
      - Uses min() function for safe calculations
      - Prevents claiming more than available balance

    ##########

    Prior Knowledge for Batch Processing in Provisioner:

    1. Request Isolation
    - Each request in a batch has a unique hash that must be verified before processing
    - File: src/core/Provisioner.sol, Lines: 570-580
    - Hash verification prevents duplicate processing of requests

    2. Asset Transfer Flow
    - All deposits and redemptions must go through MultiDepositorVault
    - File: src/core/Provisioner.sol, Lines: 363-370
    - Vault maintains accurate asset balances independent of batch processing

    3. Request State Management
    - Request hashes are marked as used immediately after processing
    - File: src/core/Provisioner.sol, Lines: 590-600
    - Prevents any form of request replay or double processing

    4. Vault Unit Requirements
    - Redemption requests require pre-existing vault units
    - File: src/core/Provisioner.sol, Lines: 240-250
    - Units must be transferred to Provisioner before redemption processing

    5. Deposit Cap Enforcement
    - Each deposit is checked against the total deposit cap
    - File: src/core/Provisioner.sol, Lines: 890-900
    - Prevents over-deposit regardless of batch composition

    ##########

    Prior Knowledge for Fee Calculation:
    1. Snapshot Mechanism:
      - File: src/core/DelayedFeeCalculator.sol
      - Context: The fee calculation is based on snapshots, not individual operations
      - Key function: submitSnapshot(address vault, uint160 averageValue, uint128 highestProfit, uint32 timestamp)
      - averageValue represents the time-weighted average value over a period

    2. TVL Fee Calculation:
      - File: src/core/DelayedFeeCalculator.sol
      - Function: _calculateTvlFees
      - Uses time-weighted average value that already accounts for offsetting deposits and withdrawals
      - Fees are calculated based on the net effect over time, not individual operations

    3. Performance Fee Calculation:
      - File: src/core/DelayedFeeCalculator.sol
      - Function: _calculatePerformanceFees
      - Only charges fees on actual profit increases
      - Offsetting operations do not create artificial profit

    ##########
    
    Prior Knowledge for Fee Calculation:

    1. Snapshot-based Fee Calculation
    - File: src/core/DelayedFeeCalculator.sol
    - Context: Fees are calculated based on periodic snapshots, not individual transactions
    - Key function: submitSnapshot() (lines 71-94)
    - Snapshot includes: averageValue and highestProfit

    2. TVL Fee Calculation
    - File: src/core/DelayedFeeCalculator.sol
    - Context: TVL fees are calculated using time-weighted average value
    - Key function: _calculateTvlFees() (lines 236-246)
    - Uses averageValue parameter which already accounts for deposits/withdrawals netting

    3. Performance Fee Calculation
    - File: src/core/DelayedFeeCalculator.sol
    - Context: Performance fees are based on profit growth
    - Key function: _calculatePerformanceFees() (lines 199-217)
    - Only charges fees on actual profit increase (newHighestProfit > oldHighestProfit)

    4. Fee Accrual Mechanism
    - File: src/core/DelayedFeeCalculator.sol
    - Context: Fees are accrued after dispute period
    - Key function: _accrueFees() (lines 171-196)
    - Fees are calculated on finalized snapshots, not individual transactions
    
    ##########

    Prior Knowledge for Auditing Context
    1. Vault Architecture (src/core/MultiDepositorVault.sol:55-85)
    - MultiDepositorVault is NOT an ERC4626 vault
    - The enter() function directly mints the specified unitsAmount without recalculating based on ERC4626 formulas
    - All pricing and fee logic is delegated to the Provisioner contract
    The vault acts as a simple token mint/burn mechanism controlled by the Provisioner

    2. Fee Handling Mechanism (src/core/Provisioner.sol:932-940)
    - Fee adjustments are handled via depositMultiplier and redeemMultiplier parameters
    - These multipliers are applied before calling the PriceAndFeeCalculator
    - The system uses: tokensAdjusted = tokens * multiplier / ONE_IN_BPS
    - This is the protocol's built-in fee/premium mechanism, not ERC4626 fees

    3. Pricing System (src/core/PriceAndFeeCalculator.sol:391-408)
    - Uses oracle-based pricing via ORACLE_REGISTRY.getQuoteForUser()
    - Does not follow ERC4626 previewDeposit() or similar mechanisms
    - Conversion formula: Math.mulDiv(tokenAmount, UNIT_PRICE_PRECISION, unitPrice, rounding)
    - This is a custom pricing system, not ERC4626 compliant

    4. Token-to-Units Flow (src/core/Provisioner.sol:541)
    - Flow: _tokensToUnitsFloorIfActive() → PRICE_FEE_CALCULATOR.convertTokenToUnitsIfActive() → vault.enter()
    - The calculated units are directly minted by the vault
    - No recalculation or additional fee deduction occurs at the vault level
    - This is by design - the Provisioner pre-calculates everything

    5. System Contract Roles
    - Provisioner: Handles all pricing, fee calculations, and user interactions
    - MultiDepositorVault: Simple mint/burn mechanism with access control
    - PriceAndFeeCalculator: Oracle-based pricing engine
    - NOT an ERC4626 ecosystem - custom vault system with different fee mechanisms

    ##########

    **Prior Knowledge for Smart Contract Auditing - Call Chain Analysis:**

    1. **Complete Call Chain Analysis Requirement:**
      - Always trace the complete execution path before identifying vulnerabilities
      - Check all calling functions for preconditions and guards
      - File: `src/periphery/hooks/slippage/BaseSlippageHooks.sol`, lines 130-140
      - Pattern: Guard condition `if (valueBefore <= valueAfter) return;` prevents problematic state

    2. **Unchecked Arithmetic Safety Patterns:**
      - Unchecked arithmetic is safe when preconditions guarantee no overflow/underflow
      - File: `src/periphery/hooks/slippage/BaseSlippageHooks.sol`, lines 175-185
      - Context: `loss = valueBefore - valueAfter` in unchecked block is safe because caller ensures `valueBefore > valueAfter`

    3. **Early Return Pattern Recognition:**
      - Functions may use early returns to handle edge cases before main logic
      - File: `src/periphery/hooks/slippage/BaseSlippageHooks.sol`, line 138
      - Pattern: Profitable trades (gains) are handled by early return, not loss calculation logic

    4. **Comment-Driven Design Verification:**
      - Code comments often reveal intended behavior and design assumptions
      - File: `src/periphery/hooks/slippage/BaseSlippageHooks.sol`, lines 133-135
      - Evidence: Comments explicitly state gains are "discarded" while losses are processed

    5. **Function Isolation vs Integration Analysis:**
      - Vulnerabilities in isolated functions may be mitigated by integration patterns
      - Context: `_enforceSlippageLimitAndDailyLoss` appears vulnerable in isolation but is protected by caller guards
      - Requirement: Always analyze functions within their actual usage context, not in isolation

    ##########

    *Prior Knowledge for Accurate Audit Analysis:**

    1. **Guard Function Pattern Recognition:**
      - File: `src/core/Provisioner.sol`, lines 861-869
      - The `_guardInsufficientTokensForTip` function properly validates that `tokens >= solverTip` before any subtraction
      - When validation fails, the function returns `true` causing early termination of the calling function
      - This pattern is consistently applied in both deposit and redeem flows

    2. **Deposit Flow Protection:**
      - File: `src/core/Provisioner.sol`, lines 535-536
      - The `_solveDepositVaultAutoPrice` function includes the guard call `if (_guardInsufficientTokensForTip(tokens, solverTip, index)) return 0;`
      - This occurs BEFORE the unchecked subtraction at line 539-541
      - The protection prevents underflow by ensuring `tokens >= solverTip` before the operation

    3. **Redeem Flow Consistency:**
      - File: `src/core/Provisioner.sol`, lines 644
      - The `_solveRedeemVaultAutoPrice` function uses identical protection with `_guardInsufficientTokensForTip`
      - Both deposit and redeem flows implement the same safety pattern

    4. **Early Return Mechanism:**
      - All guard functions in the Provisioner contract follow the pattern of returning boolean values
      - When a guard returns `true`, the main function immediately returns 0, preventing further execution
      - This design pattern ensures unsafe operations are never reached when validation fails

    5. **Mathematical Operation Safety:**
      - File: `src/core/Provisioner.sol`, lines 539-541
      - The unchecked arithmetic block `unchecked { tokensAfterTip = tokens - solverTip; }` is safe due to the preceding validation
      - The validation guarantees `tokens >= solverTip`, making the subtraction safe from underflow

    ##########
    
    ### Prior Knowledge for Future Audits:

    **1. Request Processing Independence in Aera Provisioner**
    - File: `src/core/Provisioner.sol`, lines 293-346
    - Each request in `solveRequestsVault()` is processed independently via separate vault interactions
    - No shared liquidity pool or cross-request dependencies exist
    - Skipped requests only return 0 solver tip without affecting subsequent requests

    **2. Vault Interaction Model**
    - File: `src/core/Provisioner.sol`, lines 675, 722
    - Each redeem calls `IMultiDepositorVault.exit()` independently
    - No batch-level state modifications or liquidity calculations
    - Price data (`priceAge`) is fetched once per batch and remains constant

    **3. Absence of Tier/Layer Concepts**  
    - File: `src/core/Provisioner.sol` (entire contract)
    - No tier distribution or layered processing mechanisms exist
    - The contract uses simple linear request processing without hierarchical structures
    - Token/unit conversions are calculated per-request basis using consistent price feeds

    **4. Solver Tip Accumulation Mechanism**
    - File: `src/core/Provisioner.sol`, lines 337, 340
    - Solver tips are simply accumulated (`solverTip +=`) from successful operations
    - Failed/skipped requests contribute 0 to the total without side effects
    - No rebalancing or redistribution of tips based on batch composition

    **5. Error Condition Handling Pattern**
    - File: `src/core/Provisioner.sol`, lines 651-656, 694-699  
    - Guard functions return early with 0 tip when conditions fail
    - No cascading effects or state corrections for subsequent requests
    - Each request's success/failure is isolated from others in the batch

    **False Assumption to Avoid:**
    Do not assume that batch processing implies inter-request dependencies or shared state modifications in the Aera Provisioner system. Each async request maintains complete independence throughout the solving process.

    ##########

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

    ##########

    ### Prior Knowledge for Future Audits (English Output)

    **Title: Oracle Architecture Patterns and Price Manipulation Risk Assessment**

    **Context:** When auditing DeFi protocols for oracle manipulation risks, particularly those involving Uniswap V3 tick boundary exploitation.

    **Key Prior Knowledge Points:**

    1. **Dual Price Architecture Recognition (src/core/PriceAndFeeCalculator.sol:168-198)**
      - Many protocols use separate pricing mechanisms for internal unit valuation vs external token conversions
      - Vault unit prices may be set manually by authorized entities rather than derived from external oracles
      - External oracles may only be used for cross-token conversions, not primary price discovery

    2. **Oracle Interface Abstraction (src/dependencies/oracles/IOracle.sol:1-22)**
      - ERC-7726 compliant systems use abstract oracle interfaces
      - The specific oracle implementation (Chainlink, Uniswap TWAP, custom) is deployment-specific
      - Cannot assume Uniswap V3 slot0 usage without confirming the actual oracle implementation

    3. **Oracle Registry Pattern (src/periphery/OracleRegistry.sol:199-212)**
      - Modern systems often use oracle registries that allow for multiple oracle types
      - Oracle selection and validation happens at the registry level
      - Price manipulation risks depend on the specific oracle implementation, not the consuming contract

    4. **Price Update Authorization (src/core/PriceAndFeeCalculator.sol:168-198)**
      - Look for manual price setting mechanisms vs automatic oracle-derived prices
      - Authorized price setters (accountants) may provide additional security layers
      - Price validation and pause mechanisms may mitigate manipulation risks

    5. **Scope of Oracle Usage (src/core/PriceAndFeeCalculator.sol:58-71)**
      - Distinguish between oracles used for primary pricing vs secondary conversions
      - Token-to-numeraire conversions may use oracles while unit pricing uses different mechanisms
      - Limited oracle scope reduces attack surface

    6. **Missing Implementation Evidence**
      - Always verify actual oracle implementation before assuming manipulation vectors
      - Search for specific vulnerable patterns (slot0 usage, tick manipulation) in codebase
      - Don't assume vulnerability based on theoretical attack scenarios without code evidence

    **Recommendation:** Before reporting oracle manipulation risks, always:
    1. Identify the specific oracle implementation used
    2. Verify the scope of oracle usage in price calculations
    3. Check for manual price setting mechanisms
    4. Look for protective measures like pause functionality and validation checks
    5. Ensure the claimed attack vector has actual code support

    ##########

    To avoid this type of false positive in future audits, include the following prior knowledge in the audit prompt:

    **Rounding Direction Prior Knowledge:**
    - **File**: `src/core/Provisioner.sol`, lines 948-991
    - **Deposit rounding**: `_tokensToUnitsFloorIfActive()` uses Floor rounding (vault-favorable)  
    - **Redemption rounding**: `_unitsToTokensFloorIfActive()` uses Floor rounding (vault-favorable)
    - **Mint operation**: `_unitsToTokensCeilIfActive()` uses Ceiling rounding only for calculating required tokens in mint operations (vault-favorable)
    - **Design principle**: ALL rounding operations favor the vault to prevent rounding exploits

    **Pricing Mechanism Prior Knowledge:**
    - **File**: `src/core/PriceAndFeeCalculator.sol`, lines 390-430
    - **Price source**: Uses `ORACLE_REGISTRY.getQuoteForUser()` for token price conversion
    - **No Uniswap V3 ticks**: System does not use Uniswap V3 tick-based pricing or have tick boundary vulnerabilities
    - **External oracle**: Prices come from external oracle registry, not AMM calculations

    **Protection Mechanisms Prior Knowledge:**
    - **File**: `src/core/PriceAndFeeCalculator.sol`, lines 460-485
    - **Price tolerance**: System has built-in price tolerance ratios that limit extreme price movements
    - **Vault pausing**: Automatic pausing when price changes exceed tolerance thresholds
    - **Conservative design**: All precision loss favors the protocol, not attackers

    **Key Context for Rounding Analysis:**
    When analyzing rounding vulnerabilities, verify:
    1. Which direction each rounding operation goes (Floor vs Ceiling)
    2. Who benefits from each rounding direction (user vs protocol)
    3. Whether the pricing mechanism actually has boundary conditions
    4. Whether existing protections prevent the claimed exploit path
    
    ##########


    ### Prior Knowledge for Future Audits:

    **1. Fee/Premium Multipliers vs Leverage Controls (src/core/Provisioner.sol:1001-1010)**
    - `depositMultiplier` and `redeemMultiplier` in Provisioner are fee calculation mechanisms, not leverage controls
    - They adjust token amounts for premium/discount calculation before conversion to vault units
    - Actual risk controls in this system are deposit caps and token-specific limits, not leverage ratios

    **2. PriceAndFeeCalculator Interface Limitations (src/core/Provisioner.sol:464)**
    - PriceAndFeeCalculator primarily handles price conversions and vault pause status
    - It does NOT implement leverage limits or position-based risk controls
    - Available methods: `getVaultsPriceAge()`, `convertUnitsToNumeraire()`, `convertTokenToUnitsIfActive()`, `isVaultPaused()`

    **3. Deposit Cap vs Leverage Management (src/core/Provisioner.sol:942-949)**
    - The system uses total deposit caps (`depositCap`) rather than leverage ratios
    - Risk is controlled by limiting total vault size in numeraire terms
    - Individual position leverage is not tracked or limited at the Provisioner level

    **4. Batch Processing Price Consistency (src/core/Provisioner.sol:464)**
    - Caching `priceAge` at batch start is intentional design for transaction atomicity
    - Using consistent price data across batch prevents intra-transaction arbitrage
    - This is a feature, not a vulnerability, ensuring fair batch processing

    **5. Request Type Classification (src/core/Provisioner.sol:1041-1050)**
    - Request types (DEPOSIT_AUTO_PRICE, DEPOSIT_FIXED_PRICE, etc.) control pricing method, not risk limits
    - Auto-price requests use current market rates; fixed-price requests use user-specified rates
    - Neither implements leverage-based position limits

    **6. Vault Entry/Exit Flow (src/core/Provisioner.sol:294-362)**
    - All deposits/redeems flow through Provisioner to MultiDepositorVault
    - Vault itself may have separate risk controls, but Provisioner's role is request processing and fee calculation
    - Leverage management, if any, would be implemented in the vault contract, not the Provisioner


    ##########

    #### Ethereum Transaction Atomicity Knowledge
    - **Core Principle**: All Ethereum transactions are atomic - if any operation within a transaction fails and reverts, the entire transaction state is rolled back to its initial state
    - **State Rollback**: When a transaction reverts, ALL state changes within that transaction are undone, including mappings, storage variables, and balances
    - **Contract Location**: This applies to all contracts including `src/core/Provisioner.sol` lines 1-1050
    - **Specific Pattern**: Setting a hash to false before external calls (like lines 547, 604, 667, 738) does NOT create permanent state if subsequent operations fail - the hash setting will be reverted

    #### ReentrancyGuardTransient Protection
    - **Implementation**: `src/core/Provisioner.sol` line 32 shows the contract inherits `ReentrancyGuardTransient` 
    - **Guarantee**: This modifier ensures transaction integrity and prevents state inconsistencies
    - **Function Coverage**: Functions like `solveRequestsVault` (line 308) and `refundRequest` (line 285) are protected by `nonReentrant`

    #### Hash State Management Logic
    - **Location**: `src/core/Provisioner.sol` lines 60-70 define the hash mappings
    - **Behavior**: Hash invalidation (setting to false) only persists if the entire transaction succeeds
    - **Recovery**: Failed transactions automatically restore hash state, allowing users to retry operations
    - **No Permanent Lock**: There is no scenario where funds are permanently locked due to hash invalidation in failed transactions

    #### Vault Operation Flow
    - **Enter Operation**: `src/core/Provisioner.sol` lines 547-550 show vault.enter() calls after hash invalidation
    - **Exit Operation**: `src/core/Provisioner.sol` lines 719-725 show vault.exit() followed by token transfers
    - **Recipient Parameter**: Note that vault.exit() calls use `address(this)` as recipient (line 722), meaning tokens go to Provisioner first, then to users
    - **Failure Handling**: Any failure in this chain reverts the entire transaction, including hash changes

    #### False Positive Pattern Recognition
    - **Common Misconception**: Reports claiming "premature state changes before external calls lead to permanent fund loss" often misunderstand transaction atomicity
    - **CEI Pattern Confusion**: While Checks-Effects-Interactions is good practice, violating it doesn't automatically create fund loss if transaction atomicity protects against partial execution
    - **Assessment Approach**: Always verify if the claimed "permanent" state changes can actually persist after transaction failure

    ##########

    **Prior Knowledge for Deadline Validation Pattern:**

    - **Context**: In Provisioner.sol, ALL solver functions (`_solveDepositVaultAutoPrice`, `_solveDepositVaultFixedPrice`, `_solveRedeemVaultAutoPrice`, `_solveRedeemVaultFixedPrice`) implement IDENTICAL deadline validation patterns
    - **Pattern**: Lines 669, 752, 798, 838 - Each function uses `if (request.deadline >= block.timestamp)` to distinguish between valid and expired requests
    - **Behavior**: Valid requests are processed normally; expired requests trigger refund logic and emit corresponding Refunded events
    - **Evidence**: 
      - Lines 669-686: Auto-price deposit deadline check and refund logic
      - Lines 752-768: Fixed-price deposit deadline check and refund logic  
      - Lines 798-814: Auto-price redeem deadline check and refund logic
      - Lines 838-854: Fixed-price redeem deadline check and refund logic
    - **Verification**: Before claiming deadline bypass vulnerabilities, verify the actual presence/absence of `request.deadline >= block.timestamp` conditional checks in solver functions
    - **Note**: The deadline validation is NOT missing in fixed-price functions - this is a common misconception when reviewing similar codebases

    ##########

    **Provisioner Contract Token Flow Patterns (Lines 643-743)**:
    - **Batch Solver Tip Accumulation**: In solveRequestsVault() function, solver tips from individual redeem requests are accumulated and transferred once at the end (line 331), not per-request
    - **Correct Accounting Guards**: 
      - _guardInsufficientTokensForTip(tokenOut, solverTip) ensures tokenOut >= solverTip (line 662)
      - _guardAmountBound(tokenOutAfterTip, request.tokens) where tokenOutAfterTip = tokenOut - solverTip ensures (tokenOut - solverTip) >= request.tokens (line 670)
      - Combined effect: tokenOut >= solverTip + request.tokens, which is mathematically correct
    - **Vault Exit Flow**: vault.exit() transfers exactly tokenOut tokens to Provisioner (line 674), then Provisioner transfers tokenOutAfterTip to user (line 677), leaving exactly solverTip tokens for solver
    - **Token Balance Preservation**: The sequence vault_exit(tokenOut) → user_transfer(tokenOutAfterTip) → solver_transfer(solverTip) where tokenOut = tokenOutAfterTip + solverTip maintains perfect token accounting

    ##########

    **Prior Knowledge for Future Audits:**

    1. **Direct Solving vs Vault Solving Architecture (Provisioner.sol)**:
      - Direct solving (`solveRequestsDirect`, lines 356-377) is a peer-to-peer exchange mechanism that only supports fixed-price requests
      - Vault solving (`solveRequestsVault`, lines 295-355) involves price calculations, premiums, and solver tips
      - These are fundamentally different mechanisms with different logic flows

    2. **Fixed Price Request Constraints (Provisioner.sol, lines 198, 239)**:
      - Fixed price requests MUST have `solverTip == 0` as enforced by `require(solverTip == 0 || !isFixedPrice, Aera__FixedPriceSolverTipNotAllowed())`
      - Direct solving only accepts fixed-price requests (`require(!_isRequestTypeAutoPrice(requests[i].requestType), Aera__AutoPriceSolveNotAllowed())` at line 368)
      - Therefore, direct solving never involves solver tip calculations by design

    3. **Direct Deposit Solving Flow (_solveDepositDirect, lines 764-797)**:
      - User creates deposit request with exact token/unit amounts via `requestDeposit` (line 206: tokens transferred to provisioner)
      - Solver provides exact `request.units` to user via `safeTransferFrom(msg.sender, request.user, request.units)`
      - Solver receives exact `request.tokens` from provisioner via `safeTransfer(msg.sender, request.tokens)`
      - This is an intentional 1:1 exchange with no additional calculations

    4. **Token Flow in Async Requests (Provisioner.sol)**:
      - For deposits: User transfers tokens to provisioner in `requestDeposit` (line 206)
      - For redeems: User transfers units to provisioner in `requestRedeem` (line 247)
      - The provisioner holds these assets until solved or refunded

    5. **Request Type Validation Logic (Provisioner.sol)**:
      - `_isRequestTypeDeposit()` and `_isRequestTypeAutoPrice()` helper functions determine request handling
      - Direct solving explicitly excludes auto-price requests to maintain deterministic exchange rates

    ##########

    **Prior Knowledge for Aera V3 Audit - Payment Flow Patterns:**

    1. **Solver Tip Accumulation Pattern (src/core/Provisioner.sol:358-361):**
      - Individual solving functions (_solveRedeemVaultAutoPrice, _solveDepositVaultAutoPrice) do NOT transfer solver tips directly
      - They return solver tip amounts to be accumulated in the calling function
      - solveRequestsVault() accumulates all tips and transfers once at the end
      - This pattern reduces gas costs and ensures atomic batch processing

    2. **Token Balance Validation in Redeem Flow (src/core/Provisioner.sol:679-687):**
      - _guardInsufficientTokensForTip() validates total output covers solver tip
      - tokenOutAfterTip is calculated as (tokenOut - solverTip)
      - _guardAmountBound() validates remaining balance covers user minimum
      - Combined validation ensures: tokenOut >= solverTip + request.tokens
      - Only tokenOutAfterTip is transferred to user, not request.tokens

    3. **Mathematical Equivalence in Validation (src/core/Provisioner.sol:681-687):**
      - Checking (tokenOut >= solverTip) AND (tokenOut - solverTip >= request.tokens)
      - Is mathematically equivalent to (tokenOut >= solverTip + request.tokens)
      - This pattern appears throughout solver functions for both deposits and redeems

    4. **Transfer Patterns in Solver Functions:**
      - Vault solving: Single user transfer per request, accumulated tip transfer
      - Direct solving: Two transfers per request (user + solver)
      - Never assume multiple transfers without examining actual safeTransfer calls

   ##########

   **ERC20 Token State Management:**
    - Standard ERC20 implementations immediately update `totalSupply` when `_mint()` is called
    - The `MultiDepositorVault.enter()` function at lines 56-65 in `src/core/MultiDepositorVault.sol` calls `_mint()` which immediately updates the vault's `totalSupply`
    - Each subsequent call to `IERC20(vault).totalSupply()` returns the current updated value, not cached state
    - The `_isDepositCapExceeded()` function at lines 915-919 in `src/core/Provisioner.sol` makes fresh external calls to `totalSupply()` for each deposit cap check

    **Batch Processing State Updates:**
    - In `solveRequestsVault()` batch processing, each deposit request is processed sequentially
    - Each successful deposit at lines 549-551 (auto-price) and 595-597 (fixed-price) in `src/core/Provisioner.sol` immediately updates vault state
    - Subsequent requests in the same batch use the updated `totalSupply` value, not stale state
    - No caching mechanisms exist that would preserve old `totalSupply` values across batch iterations

    **Deposit Cap Validation Logic:**
    - The `_guardDepositCapExceeded()` function at lines 886-893 calls `_isDepositCapExceeded()` which performs live state reads
    - Each cap check adds current units to the live `totalSupply()` value from the vault contract
    - The assumption that "subsequent requests use stale totalUnits data" is incorrect for standard ERC20 implementations

    ##########

    #### Contract-Specific Prior Knowledge for Provisioner.sol:

    **Token Distribution Logic in Redeem Operations:**
    - File: `src/core/Provisioner.sol`, lines 628-750
    - In `_solveRedeemVaultAutoPrice` (lines 644-694): Users receive `tokenOutAfterTip = tokenOut - solverTip`, NOT `request.tokens`. The function ensures `tokenOut >= solverTip` first, then `tokenOutAfterTip >= request.tokens`, guaranteeing sufficient funds for both user and solver.
    - In `_solveRedeemVaultFixedPrice` (lines 704-750): Users receive exactly `request.tokens`, and `solverTip = tokenOut - request.tokens` is calculated as remainder, ensuring non-negative tips.

    **Solver Tip Validation Patterns:**
    - File: `src/core/Provisioner.sol`, lines 663, 718  
    - Auto price redeems use `_guardInsufficientTokensForTip(tokenOut, solverTip, index)` to verify adequate funds before deduction
    - Fixed price redeems use `_guardAmountBound(tokenOut, request.tokens, index)` to ensure user entitlement is covered before tip calculation

    **Request Type Distinctions:**
    - File: `src/core/Provisioner.sol`, lines 1031-1042
    - `_isRequestTypeAutoPrice()` and fixed price modes have fundamentally different distribution mechanics
    - Auto price: user amount is variable (after tip deduction), tip is fixed
    - Fixed price: user amount is fixed, tip is variable (remainder)

    **Batch Processing Context:**  
    - File: `src/core/Provisioner.sol`, lines 337-344
    - Solver tips are accumulated across multiple requests and transferred once at batch completion
    - Individual request solving functions return tip amounts, they don't execute tip transfers

    ##########

    Prior Knowledge for Security Auditing:

    1. **Access Control Patterns in PriceAndFeeCalculator (src/core/PriceAndFeeCalculator.sol)**:
      - Line 17: PriceAndFeeCalculator inherits from BaseFeeCalculator and HasNumeraire
      - Line 17 in BaseFeeCalculator.sol: BaseFeeCalculator inherits from VaultAuth
       Lines 21-26 in VaultAuth.sol: requiresVaultAuth modifier requires caller to be vault owner OR have explicit authority permission
      - Line 219: resetHighestPrice function HAS requiresVaultAuth(vault) modifier, providing proper access control
      - Line 67: setVaultAccountant function also uses requiresVaultAuth(vault)
      - Line 78: setVaultFees function also uses requiresVaultAuth(vault)

    2. **Vault State Management Authorization (src/core/PriceAndFeeCalculator.sol)**:
      - Line 89: setInitialPrice requires requiresVaultAuth(vault)
      - Line 110: setThresholds requires requiresVaultAuth(vault) 
      - Line 188: unpauseVault requires requiresVaultAuth(vault)
      - Line 219: resetHighestPrice requires requiresVaultAuth(vault)
      - Pattern: All critical vault state modifications require vault authorization

    3. **Function Signature Verification**:
      - Always verify the complete function signature including modifiers before claiming missing access control
      - Check inheritance chain for access control patterns: VaultAuth -> BaseFeeCalculator -> PriceAndFeeCalculator
      - Line 219 in PriceAndFeeCalculator.sol: resetHighestPrice DOES have access control via requiresVaultAuth modifier

    4. **Code Review Best Practices**:
      - Never assume missing access control without checking the complete function definition
      - Verify inheritance relationships for access control modifiers
      - Cross-reference actual implementation with reported vulnerabilities

    ##########

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

    ##########

    ### Prior Knowledge for Provisioner Contract Deadline Validation

    **Context**: All async request solving functions in Provisioner.sol implement consistent deadline validation patterns.

    **Key Facts**:
    1. **Uniform Deadline Checking**: Both auto-price and fixed-price solving functions implement identical deadline validation using `request.deadline >= block.timestamp` (lines 598, 673, 725 in src/core/Provisioner.sol)

    2. **Function Implementation Patterns**:
      - `_solveDepositVaultAutoPrice` (line 528): Has deadline check at line 548
      - `_solveDepositVaultFixedPrice` (line 582): Has deadline check at line 598  
      - `_solveRedeemVaultAutoPrice` (line 654): Has deadline check at line 673
      - `_solveRedeemVaultFixedPrice` (line 710): Has deadline check at line 725

    3. **Consistent Control Flow**: All solving functions follow the same pattern:
      - Price age validation via `_guardPriceAge`
      - Hash existence validation via `_guardInvalidRequestHash` 
      - Deadline check with if/else branching for process vs refund logic

    4. **Code Location Reference**: The deadline validation logic is consistently implemented across all vault solving functions in src/core/Provisioner.sol, making claims of missing deadline validation in fixed-price functions factually incorrect.

    **Conclusion**: Any vulnerability report claiming missing deadline validation in fixed-price request functions should be immediately flagged as potential false positive, as the codebase demonstrates uniform implementation of deadline checks across all solving function variants.

    ##########

    Prior Knowledge for ERC4626 vs Custom Vault Systems:

    1. System Architecture Identification:
      - File: cheat_list.md:764
      - Key indicator: "NOT an ERC4626 ecosystem - custom vault system with different fee mechanisms"
      - Aera V3 uses custom vault architecture, not ERC4626 standards

    2. Token Conversion Logic (src/core/PriceAndFeeCalculator.sol:391-408):
      - All tokens treated as independent assets priced via oracle
      - Conversion path: Token → Oracle Price → Numeraire → Vault Units
      - No special handling for wrapped/share tokens required

    3. Fee/Premium Application (src/core/Provisioner.sol:932-940):
      - Multipliers applied before price conversion: tokensAdjusted = tokens * multiplier / ONE_IN_BPS
      - This is the protocol's fee mechanism, not ERC4626 preview functions
      - Single conversion path without double share calculations

    4. MultiDepositorVault Role (src/core/MultiDepositorVault.sol:55-85):
      - Acts as simple mint/burn mechanism controlled by Provisioner
      - Direct minting of calculated units without recalculation
      - All pricing logic delegated to Provisioner contract

    5. Oracle-Based Pricing System:
      - Uses ORACLE_REGISTRY.getQuoteForUser() for all non-numeraire tokens
      - Custom pricing system independent of ERC4626 share/asset conversions
      - Designed to treat wrapped tokens as first-class assets with oracle prices

    6. Common False Positive Patterns:
      - Assuming wrapper tokens require special share-to-asset conversion
      - Misinterpreting oracle-based pricing as "double conversion"
      - Applying ERC4626 semantics to custom vault systems
      - Confusing fee multipliers with share conversion errors

    ##########

    **Daily Loss Limit Reset Mechanism Prior Knowledge:**

    - **Daily Reset is Expected Behavior**: In `BaseSlippageHooks.sol` lines 198-215, the `_enforceDailyLoss` function correctly resets `cumulativeDailyLossInNumeraire` to 0 when `state.currentDay != day`. This is the intended design for daily loss limits, not a vulnerability.

     - **Test Confirmation**: `test/periphery/unit/hooks/slippage/BaseSlippageHooks.t.sol` lines 132-150 specifically tests and validates that `cumulativeDailyLossInNumeraire` resets to 0 after day changes (see `test_vaultStates_success_nextDay`).

    - **View Function Consistency**: The `vaultStates()` external view function in `BaseSlippageHooks.sol` lines 68-78 implements identical reset logic, confirming this is the expected behavior across the contract.

    - **Design Intent**: The system implements "daily loss limits" (reset each day) rather than "cumulative loss limits" (never reset). Cross-day boundary trading is normal user behavior, not an attack vector.

    - **False Positive Pattern**: Do not flag day-boundary reset mechanisms as vulnerabilities when they are explicitly designed and tested to work this way. The reset prevents previous day's losses from affecting new day's trading limits.


    ##########

    ## Prior Knowledge to Prevent False Positives

    **Contract Architecture and Rounding Strategies:**
    1. **Provisioner Rounding Logic** (src/core/Provisioner.sol:931-972):
      - `_tokensToUnitsFloorIfActive()` uses Floor rounding to favor vault
      - `_unitsToTokensFloorIfActive()` uses Floor rounding to favor vault  
      - `_unitsToTokensCeilIfActive()` uses Ceil rounding for fixed-price deposits
      - This is intentional design to prevent value extraction, not a bug

    2. **Deposit Cap Validation** (src/core/Provisioner.sol:912-921):
      - `_isDepositCapExceeded()` validates total vault value against cap
      - `_requireDepositCapNotExceeded()` enforces the cap before deposits
      - System does have invariant checking, contrary to audit assumptions

    3. **Fee Accrual Mechanism** (src/core/PriceAndFeeCalculator.sol:327-372):
      - `_accrueFees()` only updates accounting state, doesn't mint tokens
      - Fee tokens are minted during `claimFees()` calls, not during accrual
      - No direct unit supply manipulation during fee calculation

    4. **Direct Solving Constraints** (src/core/Provisioner.sol:358-378):
      - Direct solving only accepts fixed-price requests: `require(!_isRequestTypeAutoPrice())`
      - Auto-price requests cannot bypass vault pricing mechanisms
      - Peer-to-peer transfers don't create new units, only transfer existing ones

    5. **Batch Processing Price Consistency** (src/core/Provisioner.sol:294-297):
      - Single `priceAge` snapshot per batch is intentional for consistent pricing
      - Prevents price manipulation within batch execution
      - Design choice for operational efficiency, not a vulnerability

    6. **Slippage Hook Execution Order** (src/periphery/hooks/slippage/BaseSlippageHooks.sol:172-183):
      - Sequential validation (_enforceSlippageLimit → _enforceDailyLoss) is confirmed real issue
      - This creates the contradiction scenario described in audit
      - Legitimate vulnerability requiring mitigation

    **True Vulnerabilities Confirmed:**
      - Slippage/Daily Loss enforcement conflict
      - Batch processing rounding amplification potential

    **False Positives Due to Misunderstanding:**
      - Fee accrual "minting" units without backing
      - Direct solving bypassing invariant checks  
      - Complete absence of value synchronization validation

    ##########
    
    ### Prior Knowledge for Smart Contract Auditing

    **Fee Accrual vs Fee Claiming Mechanisms:**
    - Fee accrual functions typically only update storage variables to track earned fees without minting tokens or units
    - Actual fee distribution occurs in separate claiming functions that transfer existing tokens
    - Look for actual token transfers (`transfer`, `mint`, `burn`) rather than storage updates when analyzing value flow
    - Reference: `PriceAndFeeCalculator._accrueFees()` (lines 333-371) only updates `vaultAccruals.accruedFees` and `vaultAccruals.accruedProtocolFees` without any token operations

    **Vault Unit Supply vs Fee Tracking:**
    - Vault unit supply is managed by separate mint/burn operations in vault contracts
    - Fee calculations are independent accounting operations that don't directly affect unit supply
    - Fee tokens are typically separate from vault units and handled through different mechanisms
    - Reference: `FeeVault.claimFees()` (lines 103-126) transfers existing `FEE_TOKEN` balances, not vault units

    **Code Citation Requirements:**
    - Always verify function calls and contract interactions exist in the actual codebase before reporting
    - Use grep/file search to confirm external contract calls and function signatures
    - Fabricated code examples without actual contract references indicate potential false positives
    - Reference: The claimed `IMultiDepositorVault(vault).enter()` call in fee accrual context does not exist in the codebase

    **Value Invariant Analysis:**
    - Distinguish between accounting operations (storage updates) and token operations (transfers, mints, burns)
    - Fee accrual is typically accounting-only and doesn't immediately affect token balances or unit supplies
    - Invariant violations require actual token/unit movement, not just storage variable updates
    - Reference: `BaseFeeCalculator.claimFees()` (lines 100-120) shows the clear separation between fee accounting and token transfers

    ##########
    
    **Prior Knowledge for Audit Prompts:**

    1. **Architecture Pattern Recognition**
      - Before analyzing diamond proxy vulnerabilities, always verify the actual implementation pattern
      - Check for diamond-specific imports: `IDiamondCut`, `IDiamondLoupe`, `LibDiamond`
      - Look for facet-related functionality: `diamondCut`, `facets()`, `facetAddresses()`
      - Code reference: `src/core/BaseVault.sol:49` - Standard inheritance pattern, not diamond proxy

    2. **Contract Inheritance Analysis**
      - Examine actual inheritance chains before assuming proxy patterns
      - Direct inheritance provides all parent contract functions automatically
      - Code reference: `src/core/BaseVault.sol:49` shows `Auth2Step` is directly inherited
      - Code reference: `src/core/Auth2Step.sol:8` shows complete implementation with both functions

    3. **Two-Step Ownership Implementation Verification**
      - Verify both `transferOwnership` and `acceptOwnership` are available in the same contract
      - Check constructor logic for proper ownership initialization
      - Code reference: `src/core/Auth2Step.sol:31-61` - Complete implementation
      - Code reference: `src/core/BaseVault.sol:100` - Proper initialization via `transferOwnership(initialOwner)`

    4. **Test Coverage Validation**
      - Check for comprehensive test coverage of ownership transfer functionality
      - Code reference: `test/core/unit/Auth2Step.t.sol` - Complete test suite covering all scenarios
      - Tests demonstrate both functions work correctly without any accessibility issues

    5. **Proxy Pattern Differentiation**
      - Distinguish between different proxy patterns (Transparent, UUPS, Diamond, Beacon)
      - Only apply diamond-specific vulnerabilities to actual diamond implementations
      - This project uses standard deployment pattern, not proxy pattern

    ##########

    **Prior Knowledge for Audit Prompts:**

    1. **Architecture Pattern Recognition:**
      - **Location**: `src/core/Provisioner.sol:929-940` and `src/core/PriceAndFeeCalculator.sol:396-407`
      - **Key Context**: This vault system uses an external price calculator with preset unit prices rather than asset/share ratio calculations typical in ERC4626
      - **Critical Detail**: Share calculations use `Math.mulDiv(tokenAmount, UNIT_PRICE_PRECISION, unitPrice, rounding)` where `unitPrice` is manually set by authorized accounts, not derived from vault balances

    2. **Share Minting Mechanism:**
      - **Location**: `src/core/MultiDepositorVault.sol:56-67`
      - **Key Context**: The vault's `enter()` function only executes pre-calculated share amounts determined by the Provisioner
      - **Critical Detail**: `_mint(recipient, unitsAmount)` where `unitsAmount` is calculated externally, vault doesn't perform ratio calculations

    3. **Price Determination Independence:**
      - **Location**: `src/core/PriceAndFeeCalculator.sol:383-407`
      - **Key Context**: Price conversions use `ORACLE_REGISTRY.getQuoteForUser()` and preset `unitPrice` values
      - **Critical Detail**: No dependency on vault's token balances in price calculation - direct transfers cannot manipulate share pricing

    4. **Access Control Constraints:**
      - **Location**: `src/core/MultiDepositorVault.sol:32-36`
      - **Key Context**: Only the provisioner can call `enter()`/`exit()` functions via `onlyProvisioner` modifier
      - **Critical Detail**: Direct token transfers cannot trigger share minting - all deposits must go through controlled Provisioner flow

    5. **Donation Attack Prevention by Design:**
      - **Key Context**: The system inherently prevents donation attacks because:
        - Share calculations are oracle-based, not balance-based
        - Unit prices are manually set by authorized accounts
        - Direct transfers don't affect pricing mechanisms
        - All share operations require Provisioner authorization

    ##########

    ## Prior Knowledge for Accurate Multi-Vault System Analysis

    ### Architecture Understanding
    - **One-to-One Relationship**: Each `Provisioner` contract manages exactly one `MultiDepositorVault` instance, established at deployment via constructor parameters (lines 88-100 in `src/core/Provisioner.sol`)
    - **Multi-Token Single Vault**: The system supports multiple token types within a single vault, not multiple independent pools. The `tokensDetails` mapping (line 52 in `src/core/Provisioner.sol`) stores token-specific parameters for the same vault
    - **Factory Pattern**: Multiple vaults can be deployed via `MultiDepositorVaultFactory`, but each vault operates independently with its own `Provisioner` and token set

    ### Token Flow Architecture  
    - **Single Vault Operations**: All `enter()` and `exit()` calls in `solveRequestsVault()` (line 294) target the same `MULTI_DEPOSITOR_VAULT` immutable address
    - **Token-Specific Risk Parameters**: `depositMultiplier` and `redeemMultiplier` in `TokenDetails` struct are token-type specific within a vault, not pool-specific across vaults
    - **No Cross-Vault Token Sharing**: ERC20 vault tokens are minted/burned within the same vault instance, preventing cross-vault arbitrage

    ### Value Calculation Context
    - **Vault-Specific Pricing**: `PRICE_FEE_CALCULATOR.convertTokenToUnitsIfActive()` and related functions operate within the context of a single vault (lines 952-965 in `src/core/Provisioner.sol`)
    - **Deposit Cap Enforcement**: `depositCap` (line 50) applies to the single vault managed by the Provisioner, not across multiple vaults
    - **Unit Token Isolation**: Each `MultiDepositorVault` mints its own ERC20 tokens via the factory pattern, preventing cross-vault token fungibility

    ### Key Code References
    - Constructor binding: `src/core/Provisioner.sol:88-100`
    - Single vault operations: `src/core/Provisioner.sol:294-373` 
    - Token details structure: `src/core/Provisioner.sol:52`
    - Multi-vault factory pattern: `src/core/MultiDepositorVaultFactory.sol:20-75`
    - Vault-specific ERC20 minting: `src/core/MultiDepositorVault.sol:58-77`

    ### False Positive Prevention
    When analyzing cross-pool vulnerabilities, verify:
    1. Whether multiple pools actually exist sharing the same liquidity token
    2. If token operations can span across different vault instances  
    3. Whether the architecture supports cross-vault value extraction mechanisms
    4. If the one-to-one Provisioner-Vault relationship is maintained throughout the codebase

    ##########

    ### Vault Architecture and Isolation Patterns

    **Code Reference**: `BaseSlippageHooks.sol` lines 32-33
    ```solidity
    mapping(address vault => State state) internal _vaultStates;
    ```

    Each vault maintains completely independent state including:
    - Slippage limits (`maxSlippagePerTrade`)  
    - Daily loss limits (`maxDailyLossInNumeraire`)
    - Oracle registry configuration
    - Cumulative loss tracking

    **CRITICAL**: Vaults are isolated instances - there is NO cross-vault token sharing, liquidity sharing, or state sharing mechanisms.

    ### Value Calculation Context Isolation

    **Code Reference**: `BaseSlippageHooks.sol` lines 232-240
    ```solidity
    function _convertToNumeraire(uint256 amount, address token) internal view returns (uint256) {
        IOracleRegistry oracleRegistry = _vaultStates[msg.sender].oracleRegistry;
        return IOracle(oracleRegistry).getQuote(amount, token, _getNumeraire());
    }
    ```

    All value calculations (`valueBefore`, `valueAfter`) use the **same vault's oracle registry** (`msg.sender` context). Cross-vault price manipulation is architecturally impossible.

    ### Vault Types and Boundaries

    **Code Reference**: 
    - `SingleDepositorVault.sol` - Single owner vaults with deposit/withdraw functions
    - `MultiDepositorVault.sol` - Multi-user vaults with ERC20-like units, but still vault-isolated

    Each vault type maintains strict boundaries:
    1. **No shared tokens between vaults**
    2. **No cross-vault liquidity mechanisms** 
    3. **Independent risk management parameters**

    ### Common Architecture Misunderstandings to Avoid

    1. **Vault vs Pool Confusion**: Aera vaults are asset management containers, NOT AMM liquidity pools
    2. **Token Sharing Assumptions**: No mechanism exists for tokens to be "minted in vault A and used in vault B"
    3. **Cross-Vault Attack Vectors**: The isolated architecture prevents cross-vault exploits
    4. **Oracle Manipulation**: Each vault uses its own oracle configuration, preventing cross-vault price attacks

    ### Slippage Enforcement Scope

    **Code Reference**: `BaseSlippageHooks.sol` lines 178-190
    ```solidity
    function _enforceSlippageLimitAndDailyLoss(uint256 valueBefore, uint256 valueAfter)
        internal returns (uint128 cumulativeDailyLossInNumeraire) {
        State storage state = _vaultStates[msg.sender];
        // ... slippage enforcement logic
    }
    ```
    ##########

    **1. Vault Architecture Understanding:**
    - Each vault in Aera v3 is an independent contract instance with its own state
    - SingleDepositorVault vs MultiDepositorVault are separate deployment types, not interconnected pools
    - File: `src/core/SingleDepositorVault.sol` lines 17-61, `src/core/MultiDepositorVault.sol` lines 18-109
    - No cross-vault token transfer mechanisms exist in the protocol design

    **2. BaseSlippageHooks State Tracking:**
    - State tracking is strictly per-vault using `_vaultStates[msg.sender]` mapping
    - File: `src/periphery/hooks/slippage/BaseSlippageHooks.sol` line 32, 178
    - `msg.sender` is always the vault address calling the hooks, ensuring isolation
    - Oracle registry and loss limits are vault-specific, not global

    **3. Hook Configuration and Authorization:**
    - Hook configurations require vault owner authorization via `requiresVaultAuth(vault)` modifier
    - File: `src/core/VaultAuth.sol` lines 21-28
    - Users cannot arbitrarily configure hooks for vaults they don't control
    - Each vault-hook relationship is established during deployment or explicit configuration

    **4. Token Movement Constraints:**
    - Tokens exist within specific vault contracts, not in shared pools
    - Transfer mechanisms: deposit/withdraw for SingleDepositorVault, enter/exit for MultiDepositorVault
    - File: `src/core/interfaces/ISingleDepositorVault.sol` lines 30-38, `src/core/interfaces/IMultiDepositorVault.sol` lines 50-63
    - No protocol-level cross-vault transfer functions exist

    **5. Daily Loss Reset Mechanism:**
    - Daily loss resets occur per vault based on UTC midnight timestamp
    - File: `src/periphery/hooks/slippage/BaseSlippageHooks.sol` lines 195-200
    - Reset is automatic and cannot be manipulated by users
    - Each vault maintains independent daily loss counters

    ##########

    ### Contract Architecture Context
    - **Single Vault System**: The Provisioner contract manages only one vault instance (`MULTI_DEPOSITOR_VAULT`), not multiple pools. This is an immutable address set during construction in `src/core/Provisioner.sol:84-99`.
    - **Token-specific Batching**: The `solveRequestsVault()` function at `src/core/Provisioner.sol:294` processes requests for a single token within the single vault, not across different pools.
    - **Unified Pricing**: All operations within a batch use the same price age from `PRICE_FEE_CALCULATOR.getVaultsPriceAge(MULTI_DEPOSITOR_VAULT)` at `src/core/Provisioner.sol:296`.

    ### Request Processing Context  
    - **Same Vault Operations**: Both deposits (`enter()`) and redemptions (`exit()`) operate on the same `MULTI_DEPOSITOR_VAULT` instance, as seen in lines like `src/core/Provisioner.sol:589` and `src/core/Provisioner.sol:708`.
    - **No Cross-Pool Arbitrage**: There is no mechanism to deposit in one pool and redeem in another, as only one vault exists in the system.
    - **Price Consistency**: Within a single batch, all requests use the same price data, eliminating intra-batch price arbitrage opportunities.

    ### False Positive Indicators
    - **Multi-pool assumptions**: Any vulnerability claiming arbitrage between different pools/vaults should be questioned, as this is a single-vault system.
    - **Cross-vault operations**: Claims about exploiting differences between multiple vaults are invalid for this architecture.
    - **Stale pricing differences**: Arguments about different pricing speeds across pools don't apply to a single-vault system with unified pricing.
    
    ##########
