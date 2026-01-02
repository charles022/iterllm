#!/bin/bash
set -euo pipefail

DIR_NAME=$(basename "$PWD")
IMAGE_NAME="${DIR_NAME}-env"
CTR_NAME="${DIR_NAME}-env"

echo "--- Building native environment for: $IMAGE_NAME ---"

# Remove existing podman container (freshness)
if podman container exists "$CTR_NAME"; then
  echo "Removing existing container: $CTR_NAME"
  podman rm -f "$CTR_NAME"
fi

# Remove existing image (freshness)
if podman image exists "$IMAGE_NAME"; then
  echo "Removing existing image: $IMAGE_NAME"
  podman rmi -f "$IMAGE_NAME"
fi

# Create a named buildah working container so we can remove it deterministically
BUILD_CNT="${IMAGE_NAME}-build"

# If a previous buildah working container exists, remove it
buildah rm "$BUILD_CNT" 2>/dev/null || true

# Pin Fedora major for reproducibility (change to fedora:latest if you truly want latest)
BASE_IMAGE="fedora:41"

cnt=$(buildah from --name "$BUILD_CNT" "$BASE_IMAGE")

cleanup() {
  buildah rm "$cnt" 2>/dev/null || true
}
trap cleanup EXIT

# Install tools
buildah run "$cnt" -- dnf -y upgrade --refresh
buildah run "$cnt" -- dnf -y install --setopt=install_weak_deps=False \
  git vim gcc python3-pip
buildah run "$cnt" -- dnf -y clean all

# Configure metadata
buildah config --workingdir /src "$cnt"
buildah config --author "local-dev" "$cnt"

# Commit to image
buildah commit "$cnt" "$IMAGE_NAME"

# Create a persistent container that stays alive
podman create \
  --name "$CTR_NAME" \
  --workdir /src \
  --userns=keep-id \
  -v "$PWD:/src:Z" \
  "$IMAGE_NAME" \
  sleep infinity

echo "--- Setup complete. Run './enter-env.sh' to enter. ---"

