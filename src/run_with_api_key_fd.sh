#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./run_with_api_key_fd.sh <encrypted_cred_path> -- <command...>
#
# Contract:
# - The API key is provided to the child process on FD 3
# - Python reads from FD 3 once and caches it

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <encrypted_cred_path> -- <command...>" >&2
  exit 2
fi

CRED_PATH="$1"
shift

if [[ "$1" != "--" ]]; then
  echo "Usage: $0 <encrypted_cred_path> -- <command...>" >&2
  exit 2
fi
shift

echo "[wrapper] Requesting sudo access for credential decryption..."
# Ensure we have sudo permissions
sudo -v

# Open FD 3 as a pipe containing only the API key (no file on disk, no env var).
# The process substitution runs the decrypt and feeds it into FD 3.
exec 3< <(sudo systemd-creds decrypt "$CRED_PATH" | tr -d '\n')

echo "[wrapper] Decryption successful, launching command..."
# Launch python (or any command). It can read the key from FD 3.
exec "$@"
