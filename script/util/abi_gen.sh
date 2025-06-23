#!/bin/bash
set -e
export FOUNDRY_PROFILE=periphery

# NOTE: you'll need to compile first via `forge build`

mkdir -p abi
find out -name '*.json' | while read -r file; do
  abi_file="abi/$(basename "$file" .json).abi.json"
  jq '.abi' "$file" > "$abi_file"
done