#!/bin/bash

# Usage: ./scripts/new_day.sh <year> <day>
# Example: ./scripts/new_day.sh 2019 3

if [ $# -ne 2 ]; then
    echo "Usage: $0 <year> <day>"
    echo "Example: $0 2019 3"
    exit 1
fi

YEAR=$1
DAY=$2

TARGET_FILE="src/$YEAR/day$DAY.zig"

# Check if the file already exists
if [ -f "$TARGET_FILE" ]; then
    echo "Error: $TARGET_FILE already exists. Not overwriting."
    exit 1
fi

# Copy the template to the destination
cp "scripts/template.zig" "$TARGET_FILE"

echo "Created $TARGET_FILE"

# Add to year.zig if it doesn't already exist
YEAR_FILE="src/$YEAR/year.zig"
LINE="pub const day$DAY = @import(\"day$DAY.zig\");"

if [ -f "$YEAR_FILE" ]; then
    # Check if the line already exists
    if ! grep -Fq "$LINE" "$YEAR_FILE"; then
        echo "$LINE" >> "$YEAR_FILE"
        echo "Added day$DAY to $YEAR_FILE"
    else
        echo "day$DAY already exists in $YEAR_FILE"
    fi
else
    # Create year.zig if it doesn't exist
    echo "$LINE" > "$YEAR_FILE"
    echo "Created $YEAR_FILE with day$DAY"
fi
