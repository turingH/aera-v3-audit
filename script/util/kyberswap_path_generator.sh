#!/bin/bash

set -e

# Default values
INPUT_TOKEN="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"  # WETH
OUTPUT_TOKEN="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"  # USDC
INPUT_AMOUNT="100000000000000000000"  # 100 ETH
SLIPPAGE="100"  # 1%
VAULT_ADDRESS="0xE8496bB953d4a9866e5890bb9eCE401e4C07d633"
RPC_URL="${ETH_RPC_URL:-https://mainnet.infura.io/v3/}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --input-token)
            INPUT_TOKEN="$2"
            shift 2
            ;;
        --output-token)
            OUTPUT_TOKEN="$2"
            shift 2
            ;;
        --input-amount)
            INPUT_AMOUNT="$2"
            shift 2
            ;;
        --slippage)
            SLIPPAGE="$2"
            shift 2
            ;;
        --vault)
            VAULT_ADDRESS="$2"
            shift 2
            ;;
        --rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Get current block number
BLOCK_NUMBER=$(cast block-number --rpc-url "$RPC_URL")
echo -e "\n>>> Generating KyberSwap Swap Data @ Block $BLOCK_NUMBER"
echo "Input Token:    $INPUT_TOKEN"
echo "Output Token:   $OUTPUT_TOKEN"
echo "Input Amount:   $INPUT_AMOUNT"
echo "Slippage:       $(($SLIPPAGE / 100))%"
echo "Vault Address:  $VAULT_ADDRESS"
echo "RPC URL:        $RPC_URL"
echo ""

# Get the route summary
ROUTE_SUMMARY_RESPONSE=$(curl -sL \
  --url "https://aggregator-api.kyberswap.com/ethereum/api/v1/routes?tokenIn=$INPUT_TOKEN&tokenOut=$OUTPUT_TOKEN&amountIn=$INPUT_AMOUNT")

# Extract routeSummary
ROUTE_SUMMARY=$(echo "$ROUTE_SUMMARY_RESPONSE" | jq '.data.routeSummary')

if [[ "$ROUTE_SUMMARY" == "null" || -z "$ROUTE_SUMMARY" ]]; then
  echo "Failed to retrieve route summary"
  exit 1
fi

echo "Route summary retrieved"

# Build the route
echo ">>> Building transaction path"

BUILD_PAYLOAD=$(jq -n \
  --argjson routeSummary "$ROUTE_SUMMARY" \
  --arg sender "$VAULT_ADDRESS" \
  --arg recipient "$VAULT_ADDRESS" \
  --argjson slippageTolerance "$SLIPPAGE" \
  '{
    routeSummary: $routeSummary,
    sender: $sender,
    recipient: $recipient,
    slippageTolerance: $slippageTolerance
  }')

BUILD_RESPONSE=$(curl -sL \
  --request POST \
  --url "https://aggregator-api.kyberswap.com/ethereum/api/v1/route/build" \
  --header 'Content-Type: application/json' \
  --data "$BUILD_PAYLOAD")

# Extract swap data
SWAP_DATA=$(echo "$BUILD_RESPONSE" | jq -r '.data.data')

if [[ "$SWAP_DATA" == "null" || -z "$SWAP_DATA" ]]; then
  echo "Failed to retrieve swap data"
  exit 1
fi

echo -e "\n✅ Successfully generated KyberSwap swap data @ block $BLOCK_NUMBER:"
echo "$SWAP_DATA" 