#!/bin/bash

set -eou pipefail

# --- Configuration ---
# Match naming logic from build_image.sh
REPO=$(basename "$(git rev-parse --show-toplevel)")
BRANCH_RAW="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$BRANCH_RAW" ]]; then
    BRANCH_RAW="$(git rev-parse --abbrev-ref HEAD)"
fi
BRANCH_SAFE="$(printf '%s' "$BRANCH_RAW" | LC_ALL=C tr '/ ' '--')"
PROJECT="$REPO-$BRANCH_SAFE"

SERVICE_NAME="${PROJECT}-service"
BINARY_PATH_DEFAULT="${HOME}/.local/bin/${PROJECT}"
BINARY_PATH="${BINARY_PATH:-$BINARY_PATH_DEFAULT}"
CONFIG_HOME="$HOME/.config"
CRED_SOURCE="${CONFIG_HOME}/credstore.encrypted/my_api_key"
UNIT_DIR="${CONFIG_HOME}/systemd/user"
UNIT_FILE="${UNIT_DIR}/${SERVICE_NAME}.service"

# --- Checks ---
echo "Checking for binary: ${BINARY_PATH}..."
if [[ ! -x "$BINARY_PATH" ]]; then
    echo "Error: Binary ${BINARY_PATH} not found or not executable."
    echo "Build and install it with src/build_binary.sh or set BINARY_PATH."
    exit 1
fi

echo "Checking for encrypted credential: ${CRED_SOURCE}..."
if ! test -f "$CRED_SOURCE"; then
    echo "Warning: Credential file $CRED_SOURCE does not exist or is not readable."
    echo "Please create it using 'systemd-creds encrypt' as per docs/secure_key_sop.md"
    echo "The service will likely fail to start without it."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- Generate Systemd Unit ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing systemd unit at ${UNIT_FILE}..."
install -d -m 0755 "$UNIT_DIR"

# Read template, substitute variables, and write to unit file
sed -e "s|{{SERVICE_NAME}}|${SERVICE_NAME}|g" \
    -e "s|{{BINARY_PATH}}|${BINARY_PATH}|g" \
    "${SCRIPT_DIR}/iterllm.service.template" > "${UNIT_FILE}"
chmod 644 "${UNIT_FILE}"

# --- Enable & Start ---
echo "Reloading user systemd..."
systemctl --user daemon-reload

echo "Enabling and starting service ${SERVICE_NAME}..."
systemctl --user enable "${SERVICE_NAME}"
systemctl --user restart "${SERVICE_NAME}"
