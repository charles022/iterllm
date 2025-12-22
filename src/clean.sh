#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

OUTPUT_DIR="$PROJECT_ROOT/outputs"

if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning artifacts in $OUTPUT_DIR..."
    # Remove contents but keep the directory
    rm -rf "$OUTPUT_DIR"/*
    echo "Done."
else
    echo "Output directory $OUTPUT_DIR does not exist."
fi
