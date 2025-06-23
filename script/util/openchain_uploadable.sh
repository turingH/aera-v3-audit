#!/bin/bash
set -e

# Default UPLOADABLE to true if not provided
UPLOADABLE=${1:-true}

# Decide output filename based on UPLOADABLE
if [ "$UPLOADABLE" == "true" ]; then
  OUTPUT_FILE="openchain_uploadable.txt"
else
  OUTPUT_FILE="aera_v3_sighashes.txt"
fi

# Directory containing the 4byte files
FOURBYTE_DIR="4bytes"

# Temporary file to hold all unique signatures
tmp_file=$(mktemp)

# Find all .4bytes.txt files
find "$FOURBYTE_DIR" -name '*.4bytes.txt' | while read -r file; do
  while read -r line; do
    if [ "$UPLOADABLE" == "true" ]; then
      type=$(echo "$line" | cut -d':' -f1)
      rest=$(echo "$line" | cut -d':' -f2- | awk -F'=>' '{print $1}' | xargs)
      echo "$type $rest" >> "$tmp_file"
    else
      # Keep the line exactly as it appears
      echo "$line" >> "$tmp_file"
    fi
  done < "$file"
done

# Remove duplicates and empty lines
sort -u "$tmp_file" | grep -v '^$' > "$OUTPUT_FILE"

# Clean up
echo "Prepared signatures file: $OUTPUT_FILE"
rm "$tmp_file"