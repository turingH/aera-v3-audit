#!/bin/bash
set -e

# NOTE: you'll need to generate the ABI via abi_gen.sh first

mkdir -p 4bytes

echo "Starting 4bytes generation process..."
# echo "Processing these ABI files:"
# ls -la abi/*.abi.json

# Process a single ABI file
process_abi_file() {
  local abi_file="$1"
  local base_name=$(basename "$abi_file" .abi.json)
  local fourbyte_file="4bytes/${base_name}.4bytes.txt"
  
  echo "Processing file: $abi_file -> $fourbyte_file"
  
  # Check if file exists and is not empty
  if [ ! -s "$abi_file" ]; then
    echo "  Empty or non-existent file: $abi_file" >&2
    return
  fi
  
  # First check if the file is valid JSON and not just "null"
  if [[ "$(cat "$abi_file")" == "null" ]]; then
    echo "  Skipping empty ABI file: $abi_file" >&2
    return
  fi
  
  # Check if file is a valid JSON
  if ! jq empty "$abi_file" 2>/dev/null; then
    echo "  Skipping invalid JSON file: $abi_file" >&2
    return
  fi
  
  # Create a temporary file for processing
  temp_file=$(mktemp)
  
  # Extract each function/event/error to process individually
  jq -c '.[] | select(.type=="function" or .type=="event" or .type=="error")' "$abi_file" > "$temp_file"
  
  # If nothing was extracted, skip this file
  if [ ! -s "$temp_file" ]; then
    echo "  No functions, events, or errors found. Skipping."
    rm "$temp_file"
    return
  fi
  
  # Function to process a tuple type recursively
  process_tuple() {
    local tuple_json="$1"
    
    # Start with opening parenthesis
    echo -n "("
    
    # Process each component
    local components=$(echo "$tuple_json" | jq -c '.components[]')
    local first=true
    local IFS=$'\n'
    for component in $components; do
      # Add comma if not the first component
      if [ "$first" = true ]; then
        first=false
      else
        echo -n ","
      fi
      
      local comp_type=$(echo "$component" | jq -r '.type')
      
      # Handle nested tuples
      if [[ "$comp_type" == "tuple" ]]; then
        process_tuple "$component"
      elif [[ "$comp_type" == "tuple[]" ]]; then
        process_tuple "$component"
        echo -n "[]"
      else
        # Regular type
        echo -n "$comp_type"
      fi
    done
    
    # Close parenthesis
    echo -n ")"
  }
  
  # Process each entry
  while read -r entry; do
    local entry_type=$(echo "$entry" | jq -r '.type')
    local name=$(echo "$entry" | jq -r '.name')
    
    # Build the parameter list
    local params=""
    local first=true
    
    # Extract all inputs
    local inputs=$(echo "$entry" | jq -c '.inputs[]' 2>/dev/null || echo "")
    
    # If we have inputs, process them
    if [ -n "$inputs" ]; then
      local IFS=$'\n'
      for input in $inputs; do
        # Add comma if not the first parameter
        if [ "$first" = true ]; then
          first=false
        else
          params="${params},"
        fi
        
        local input_type=$(echo "$input" | jq -r '.type')
        
        # Handle different types of inputs
        if [[ "$input_type" == "tuple" ]]; then
          params="${params}$(process_tuple "$input")"
        elif [[ "$input_type" == "tuple[]" ]]; then
          params="${params}$(process_tuple "$input")[]"
        else
          # Regular type
          params="${params}${input_type}"
        fi
      done
    fi
    
    # Build the full signature
    local signature="${name}(${params})"
    
    # Generate the selector
    local selector=$(cast sig "$signature" 2>/dev/null || echo "ERROR")
    
    if [[ "$selector" != "ERROR" ]]; then
      echo "${entry_type}: ${signature} => ${selector}" >> "$fourbyte_file"
    #   echo "  Processed ${entry_type}: ${signature} => ${selector}"
    else
      echo "  Failed to process ${entry_type}: ${signature}" >&2
    fi
  done < "$temp_file"
  
  # Cleanup
  rm "$temp_file"
  
  # Count successful extractions
  total_processed=$(wc -l < "$fourbyte_file" 2>/dev/null || echo "0")
  echo "  Successfully processed $total_processed signatures"
}

# Process each ABI file
for abi_file in abi/*.abi.json; do
  process_abi_file "$abi_file"
done

echo "Processing complete. Checking results..."
total_files=$(find 4bytes -type f | wc -l)
total_signatures=$(find 4bytes -type f -exec cat {} \; | wc -l)
echo "Generated $total_signatures signatures across $total_files files."
