#!/bin/bash
# 
# Usage: ./src/run.sh [OPTIONS]
# 
# This script can be run from any directory; it automatically resolves the project root.
# 
# Options:
#   --input <path>            Path to scenario list file (default: input/DataTransferScenarioList.md)
#   --input-template <path>   Path to alternate editable prompt template
#   --base-template <path>    Path to baseline prompt template
#   --output-dir <path>       Directory for scenario outputs (default: outputs/)
#   --max-scenarios <n>       Limit run to first N scenarios
#   --overwrite               Regenerate existing outputs
#   --reasoning-effort <lvl>  Reasoning level: minimal|low|medium|high (for GPT-5/o-series)
#   --help                    Show full help message
# 
# Example: ./src/run.sh --max-scenarios 2

set -e

echo "[run.sh] Starting run script..."

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Navigate to project root
cd "$PROJECT_ROOT"

# Activate virtual environment if it exists
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
else
    echo "Warning: .venv not found at $PROJECT_ROOT/.venv"
fi

# Run the orchestrator with any passed arguments
echo "Running src/orchestrator.py from $PROJECT_ROOT..."

# Extract CREDENTIAL_PATH from src/.env (if it exists)
CRED_PATH=""
if [ -f "src/.env" ]; then
    CRED_PATH=$(python3 -c "import json, sys; print(json.load(open('src/.env')).get('CREDENTIAL_PATH', ''))" 2>/dev/null || true)
fi

if [ -n "$CRED_PATH" ]; then
    echo "Using secure credential wrapper with $CRED_PATH"
    # Execute via the wrapper script which handles sudo decryption
    exec "$PROJECT_ROOT/src/run_with_api_key_fd.sh" "$CRED_PATH" -- python src/orchestrator.py "$@"
else
    echo "Error: CREDENTIAL_PATH must be set in src/.env to use the secure wrapper." >&2
    exit 1
fi
