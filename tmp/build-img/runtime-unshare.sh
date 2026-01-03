#!/bin/bash
set -euo pipefail

# Args from parent script
RUNTIME_CONTAINER="${1:?missing runtime container name}"
RUNTIME_IMAGE="${2:?missing runtime image name}"
RELEASEVER="${3:-41}"

echo "[unshare] Building Runtime Image..."
echo "[unshare]   container: $RUNTIME_CONTAINER"
echo "[unshare]   image:     $RUNTIME_IMAGE"
echo "[unshare]   releasever:$RELEASEVER"

# Create the working container
buildah from --name "$RUNTIME_CONTAINER" scratch > /dev/null

# Ensure we always unmount on failure
mnt=""
cleanup() {
  if [[ -n "${mnt:-}" ]]; then
    buildah unmount "$RUNTIME_CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Mount (this is the operation that needs unshare in rootless overlay mode)
mnt="$(buildah mount "$RUNTIME_CONTAINER")"

# Install minimal deps into the container rootfs via host dnf
dnf -y \
  --installroot "$mnt" \
  --releasever="$RELEASEVER" \
  --nodocs \
  --setopt=install_weak_deps=False \
  install bash coreutils glibc

dnf -y --installroot "$mnt" clean all

# Create working dir
mkdir -p "$mnt/src"

# Finalize
buildah unmount "$RUNTIME_CONTAINER" > /dev/null
mnt=""

buildah config --workingdir /src "$RUNTIME_CONTAINER"
buildah config --entrypoint '["/bin/bash"]' "$RUNTIME_CONTAINER"
buildah commit "$RUNTIME_CONTAINER" "$RUNTIME_IMAGE" > /dev/null

echo "[unshare] Runtime image built: $RUNTIME_IMAGE"

