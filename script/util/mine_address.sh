#!/bin/bash

# Default values
DEPLOYER=""
CONTRACT=""
STARTS_WITH=""
ENDS_WITH=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --deployer)
            DEPLOYER="$2"
            shift 2
            ;;
        --contract)
            CONTRACT="$2"
            shift 2
            ;;
        --starts-with)
            STARTS_WITH="$2"
            shift 2
            ;;
        --ends-with)
            ENDS_WITH="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$DEPLOYER" ]; then
    echo "Error: DEPLOYER address is required"
    exit 1
fi

if [ -z "$CONTRACT" ]; then
    echo "Error: CONTRACT name is required"
    exit 1
fi

# Get init code hash
INIT_CODE_HASH=$(cast keccak "$(forge inspect $CONTRACT bytecode)")

echo -e "\n>>> Running CREATE2 Address Finder..."
echo "Deployer:       $DEPLOYER"
echo "Contract:       $CONTRACT"
echo "Starts with:    ${STARTS_WITH:-<0>} (default=0)"
echo "Ends with:      ${ENDS_WITH:-<any>}"
echo "Init code hash: $INIT_CODE_HASH"
echo ""

# Build cast create2 command based on provided options
CMD="cast create2"
if [ ! -z "$STARTS_WITH" ]; then
    CMD="$CMD --starts-with $STARTS_WITH"
else
    CMD="$CMD --starts-with 0"
fi
if [ ! -z "$ENDS_WITH" ]; then
    CMD="$CMD --ends-with $ENDS_WITH"
fi

CMD="$CMD --deployer $DEPLOYER --init-code-hash $INIT_CODE_HASH"

# Use cast create2 to find the address and capture its output
RESULT=$(eval $CMD | awk '/Successfully found contract address/,0')
echo "$RESULT"

