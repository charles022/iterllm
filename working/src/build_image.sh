#!/bin/bash

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Runtime container builds are retired. Building a local binary instead."
exec "${SCRIPT_DIR}/build_binary.sh" "$@"
