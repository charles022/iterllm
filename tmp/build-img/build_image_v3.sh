#!/bin/bash
set -e

# Set name variable based on current directory
PROJECT=$(basename "$PWD")

# Naming conventions
DEV_IMAGE="${PROJECT}-dev-image"
DEV_CONTAINER="${PROJECT}-dev-container"
RUNTIME_IMAGE="${PROJECT}-runtime-image"
RUNTIME_CONTAINER="${PROJECT}-runtime-container"

# --- CLEANUP ---
# Combined cleanup logic. 'buildah rm' handles both storage views in most
# modern Fedora/RHEL setups. We use || true to suppress errors if they don't exist.
echo "Cleaning up..."
buildah rm -f "$DEV_CONTAINER" "$RUNTIME_CONTAINER" 2>/dev/null || true
buildah rmi -f "$DEV_IMAGE" "$RUNTIME_IMAGE" 2>/dev/null || true

# --- DEV BUILD ---
echo "Building Dev Container..."
# Explicitly name the container so the variable matches the actual container name
buildah from --name "$DEV_CONTAINER" fedora:latest > /dev/null

# Run setup
buildah run "$DEV_CONTAINER" -- dnf -y install rust cargo bash coreutils git
buildah run "$DEV_CONTAINER" -- dnf clean all
buildah commit "$DEV_CONTAINER" "$DEV_IMAGE"

# Configure image to default to this directory
# containers will be built/run with pwd mounted to src/
buildah config --workingdir /src "$DEV_CONTAINER"
buildah commit "$DEV_CONTAINER" "$DEV_IMAGE"

# --- RUNTIME BUILD ---
echo "Building Runtime Container..."
# FIX: Added --name. Now the container is actually named what the variable says.
buildah from --name "$RUNTIME_CONTAINER" scratch > /dev/null
mnt=$(buildah mount "$RUNTIME_CONTAINER")

# Install requirements via Host DNF
dnf -y \
    --installroot "$mnt" \
    --releasever=41 \
    --nodocs \
    --setopt=install_weak_deps=False \
    install bash coreutils glibc

# Cleanup metadata inside the mount
dnf -y --installroot "$mnt" clean all

# Finalize
buildah unmount "$RUNTIME_CONTAINER"
buildah config --entrypoint '["/bin/bash"]' "$RUNTIME_CONTAINER"
buildah commit "$RUNTIME_CONTAINER" "$RUNTIME_IMAGE"

echo "Done."
