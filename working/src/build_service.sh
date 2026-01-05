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
echo "Generating systemd unit at ${UNIT_FILE}..."

cat <<EOF | sudo tee "$UNIT_FILE" > /dev/null
[Unit]
Description=IterLLM Runtime Service (${PROJECT})
After=network-online.target
Documentation=https://github.com/iterllm/iterllm-v3

[Service]
# --- Security & Isolation ---
Type=exec
DynamicUser=yes
PrivateMounts=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes

# --- Credentials ---
# Decrypts $CRED_SOURCE -> \$CREDENTIALS_DIRECTORY/$CRED_NAME
LoadCredentialEncrypted=${CRED_NAME}:${CRED_SOURCE}

# --- Container Execution ---
# We run bash via /bin/sh to expand \$CREDENTIALS_DIRECTORY before calling podman
ExecStart=/bin/sh -c '/usr/bin/podman run \
    --name ${SERVICE_NAME} \
    --replace \
    --rm \
    --cgroup-manager=systemd \
    --sdnotify=conmon \
    --network=slirp4netns \
    -v "\${CREDENTIALS_DIRECTORY}/${CRED_NAME}:/run/secrets/${CRED_NAME}:ro" \
    ${RUNTIME_IMAGE}:latest \
    /bin/bash -c "echo Service Started; if [ -f /run/secrets/${CRED_NAME} ]; then echo Key available at /run/secrets/${CRED_NAME}; else echo Key missing; fi; sleep infinity"'

# Cleanup
ExecStop=/usr/bin/podman stop --ignore --time 10 ${SERVICE_NAME}
ExecStopPost=/usr/bin/podman rm --force --ignore ${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

# --- Enable & Start ---
echo "Reloading systemd..."
sudo systemctl daemon-reload

echo "Enabling and starting service ${SERVICE_NAME}..."
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"
