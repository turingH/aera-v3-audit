#!/bin/bash

set -e

# Default values
INPUT_TOKEN="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"  # WETH
OUTPUT_TOKEN="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"  # USDC
INPUT_AMOUNT="1000000000000000000"  # 1 ETH
SLIPPAGE="1"  # 1%
VAULT_ADDRESS="0x658a74FA3f3B450E3B2D5f3FecE282f8cc26DAD6"
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
echo -e "\n>>> Generating Odos Swap Data @ Block $BLOCK_NUMBER"
echo "Input Token:    $INPUT_TOKEN"
echo "Output Token:   $OUTPUT_TOKEN"
echo "Input Amount:   $INPUT_AMOUNT"
echo "Slippage:       $SLIPPAGE%"
echo "Vault Address:  $VAULT_ADDRESS"
echo "RPC URL:        $RPC_URL"
echo ""

# 1. Get quote
QUOTE_PAYLOAD='{"chainId":1,"inputTokens":[{"tokenAddress":"'$INPUT_TOKEN'","amount":"'$INPUT_AMOUNT'"}],"outputTokens":[{"tokenAddress":"'$OUTPUT_TOKEN'"}],"userAddr":"'$VAULT_ADDRESS'","slippageLimitPercent":'$SLIPPAGE',"disableRFQs":true,"compact":false}'

echo "Fetching quote from Odos API..."
QUOTE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "accept: application/json" \
  -d "$QUOTE_PAYLOAD" \
  https://api.odos.xyz/sor/quote/v2)

ERROR_CODE=$(echo "$QUOTE_RESPONSE" | jq -r '.errorCode')
if [ "$ERROR_CODE" != "null" ]; then
    ERROR_DETAIL=$(echo "$QUOTE_RESPONSE" | jq -r '.detail')
    echo "Error $ERROR_CODE: $ERROR_DETAIL"
    exit 1
fi

PATH_ID=$(echo "$QUOTE_RESPONSE" | jq -r '.pathId')
[ -n "$PATH_ID" ] || { echo "Failed to get pathId"; exit 1; }
echo -e "\n~~~~~~~~\nPath ID: $PATH_ID\n~~~~~~~~\n"

# 2. Assemble path
ASSEMBLE_PAYLOAD='{"userAddr":"'$VAULT_ADDRESS'","pathId":"'$PATH_ID'","simulate":false}'

echo "Assembling transaction path..."
ASSEMBLE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "accept: application/json" \
  -d "$ASSEMBLE_PAYLOAD" \
  https://api.odos.xyz/sor/assemble)

SWAP_DATA=$(echo "$ASSEMBLE_RESPONSE" | jq -r '.transaction.data')
[ -n "$SWAP_DATA" ] || { echo "Failed to get swap data"; exit 1; }

echo -e "\n✅ Successfully generated Odos swap data @ block $BLOCK_NUMBER:"
echo "$SWAP_DATA" 