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
    