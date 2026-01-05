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
RUNTIME_IMAGE="${PROJECT}-runtime-image"

SERVICE_NAME="${PROJECT}-service"
CONFIG_HOME="$HOME/.config"
CRED_SOURCE="${CONFIG_HOME}/credstore.encrypted/my_api_key"
UNIT_DIR="${CONFIG_HOME}/systemd/user"
UNIT_FILE="${UNIT_DIR}/${SERVICE_NAME}.service"
ENV_DIR="${CONFIG_HOME}/iterllm"
ENV_FILE="${ENV_DIR}/${SERVICE_NAME}.env"

# --- Checks ---
if ! command -v podman &> /dev/null; then
    echo "Error: podman is not installed."
    exit 1
fi

echo "Checking for runtime image: ${RUNTIME_IMAGE}..."
if ! podman image exists "${RUNTIME_IMAGE}:latest"; then
    echo "Error: Image ${RUNTIME_IMAGE}:latest not found in user store. Please run src/build_image.sh."
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
echo "Writing environment file at ${ENV_FILE}..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d -m 0755 "$ENV_DIR"
tmp_env="$(mktemp)"
cat > "$tmp_env" <<EOF
PROJECT=${PROJECT}
SERVICE_NAME=${SERVICE_NAME}
RUNTIME_IMAGE=${RUNTIME_IMAGE}
EOF
install -m 0640 "$tmp_env" "$ENV_FILE"
rm -f "$tmp_env"

echo "Installing systemd unit at ${UNIT_FILE}..."
install -d -m 0755 "$UNIT_DIR"
install -m 0644 "${SCRIPT_DIR}/iterllm.service.template" "$UNIT_FILE"

# --- Enable & Start ---
echo "Reloading user systemd..."
systemctl --user daemon-reload

echo "Enabling and starting service ${SERVICE_NAME}..."
systemctl --user enable "${SERVICE_NAME}"
systemctl --user restart "${SERVICE_NAME}"
