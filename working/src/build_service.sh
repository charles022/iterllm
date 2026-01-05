#!/bin/bash

set -eou pipefail

# --- Configuration ---
# Match naming logic from build_image.sh
REPO=$(basename "$(git rev-parse --show-toplevel)")
BRANCH=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD)
PROJECT="$REPO-$BRANCH"
RUNTIME_IMAGE="${PROJECT}-runtime-image"

SERVICE_NAME="${PROJECT}-service"
CRED_NAME="my_api_key"
CRED_SOURCE="/etc/credstore.encrypted/${CRED_NAME}"
UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_DIR="/etc/iterllm"
ENV_FILE="${ENV_DIR}/${SERVICE_NAME}.env"

# --- Checks ---
if ! command -v podman &> /dev/null; then
    echo "Error: podman is not installed."
    exit 1
fi

echo "Checking for runtime image: ${RUNTIME_IMAGE}..."
if ! sudo podman image exists "${RUNTIME_IMAGE}:latest"; then
    echo "Error: Image ${RUNTIME_IMAGE}:latest not found in root store. Please run src/build_image.sh with sudo or push to a shared registry."
    exit 1
fi

echo "Checking for encrypted credential: ${CRED_SOURCE}..."
if ! sudo test -f "$CRED_SOURCE"; then
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

sudo install -d -m 0755 "$ENV_DIR"
tmp_env="$(mktemp)"
cat > "$tmp_env" <<EOF
PROJECT=${PROJECT}
SERVICE_NAME=${SERVICE_NAME}
CRED_NAME=${CRED_NAME}
CRED_SOURCE=${CRED_SOURCE}
RUNTIME_IMAGE=${RUNTIME_IMAGE}
EOF
sudo install -m 0640 "$tmp_env" "$ENV_FILE"
rm -f "$tmp_env"

echo "Installing systemd unit at ${UNIT_FILE}..."
sudo install -m 0644 "${SCRIPT_DIR}/iterllm.service.template" "$UNIT_FILE"

# --- Enable & Start ---
echo "Reloading systemd..."
sudo systemctl daemon-reload

echo "Enabling and starting service ${SERVICE_NAME}..."
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"
