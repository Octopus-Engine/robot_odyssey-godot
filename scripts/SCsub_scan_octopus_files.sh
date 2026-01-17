#!/bin/bash

# Directory to scan
search_dir="modules/godoctopus2/src/octopus2/"

echo "    \"./src/octopus2/src/octopus/src/cdt/src/CDT.cpp\","
# Find all .cc files in the directory, excluding paths with "test" or "exe"
find "$search_dir" -type f -name "*.cc" ! -path "*test*" ! -path "*exe*" | while read -r file; do
	# Replace the first two directories with "."
	truncated_path=$(echo "$file" | sed 's|^[^/]*/[^/]*/|./|')
	echo "    \"$truncated_path\","
done