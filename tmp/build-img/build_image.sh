#!/bin/bash
set -euo pipefail

PROJECT=$(basename "$PWD")

DEV_IMAGE="${PROJECT}-dev-image"
DEV_CONTAINER="${PROJECT}-dev-container"
RUNTIME_IMAGE="${PROJECT}-runtime-image"
RUNTIME_CONTAINER="${PROJECT}-runtime-container"

RUNTIME_RELEASEVER="41"

echo "Cleaning up old build artifacts..."
buildah rm "$DEV_CONTAINER" "$RUNTIME_CONTAINER" 2>/dev/null || true
buildah rmi -f "$DEV_IMAGE" "$RUNTIME_IMAGE" 2>/dev/null || true

if podman container exists "$DEV_CONTAINER"; then
  podman rm -f "$DEV_CONTAINER"
fi
if podman container exists "$RUNTIME_CONTAINER"; then
  podman rm -f "$RUNTIME_CONTAINER"
fi
if podman image exists "$DEV_IMAGE"; then
  podman rmi -f "$DEV_IMAGE"
fi
if podman image exists "$RUNTIME_IMAGE"; then
  podman rmi -f "$RUNTIME_IMAGE"
fi

# --- DEV BUILD ---
echo "Building Dev Image..."
buildah from --name "$DEV_CONTAINER" fedora:latest > /dev/null

buildah run "$DEV_CONTAINER" -- dnf -y install rust cargo bash coreutils git
buildah run "$DEV_CONTAINER" -- mkdir -p /src
buildah run "$DEV_CONTAINER" -- dnf clean all

buildah config --workingdir /src "$DEV_CONTAINER"
buildah commit "$DEV_CONTAINER" "$DEV_IMAGE" > /dev/null

# --- RUNTIME BUILD ---
# image built using dev container
echo "Building Runtime Image using Dev container tooling..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN_CONTAINER_SCRIPT="/tmp/runtime-rootfs-in-dev.sh"

# Copy the helper into the DEV build container
buildah copy "$DEV_CONTAINER" "$SCRIPT_DIR/runtime-rootfs-in-dev.sh" "$IN_CONTAINER_SCRIPT"

# Run it inside the DEV build container (no quoting gymnastics)
buildah run "$DEV_CONTAINER" -- chmod +x "$IN_CONTAINER_SCRIPT"

# Optional: control package list via env vars
buildah run "$DEV_CONTAINER" -- env \
  RUNTIME_PKGS="bash coreutils glibc" \
  OUT_DIR="/out" \
  /bin/bash -euo pipefail "$IN_CONTAINER_SCRIPT"

# Pull the resulting tarball out to the host
tmp_tar="$(mktemp --tmpdir "${PROJECT}.rootfs.XXXXXX.tar")"
buildah copy "$DEV_CONTAINER" /out/rootfs.tar "$tmp_tar"

# Create scratch runtime image from tarball
buildah from --name "$RUNTIME_CONTAINER" scratch > /dev/null
buildah add "$RUNTIME_CONTAINER" "$tmp_tar" /

buildah config --workingdir /src "$RUNTIME_CONTAINER"
buildah config --entrypoint '["/bin/bash"]' "$RUNTIME_CONTAINER"
buildah commit "$RUNTIME_CONTAINER" "$RUNTIME_IMAGE" > /dev/null

rm -f "$tmp_tar"

# Optional: remove helper + artifacts from dev container to keep it clean
buildah run "$DEV_CONTAINER" -- rm -f "$IN_CONTAINER_SCRIPT" /out/rootfs.tar
buildah run "$DEV_CONTAINER" -- rm -rf /out/rootfs


# Clean up existing container/image to ensure "freshness"
# try...
buildah rm "$CONTAINER_NAME" 2>/dev/null
buildah rmi "$CONTAINER_NAME" 2>/dev/null

if podman container exists "$CONTAINER_NAME"; then
  podman rm -f "$CONTAINER_NAME"
fi

if podman image exists "$IMAGE_NAME"; then
  podman rmi -f "$IMAGE_NAME"
fi




echo "Done."
echo "Images Ready:"
echo "  - $DEV_IMAGE"
echo "  - $RUNTIME_IMAGE"

