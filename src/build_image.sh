#!/bin/bash

set -eou pipefail

PROJECT=$(basename "$PWD")
DEV_IMAGE="${PROJECT}-dev-image"
DEV_CONTAINER="${PROJECT}-dev-container"
RUNTIME_IMAGE="${PROJECT}-runtime-image"
RUNTIME_CONTAINER="${PROJECT}-runtime-container"
HOSTMOUNT="/hostmount"

# cleanup
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

# build dev container
buildah from --name "$DEV_CONTAINER" fedora:latest
buildah run "$DEV_CONTAINER" dnf update -y
buildah run "$DEV_CONTAINER" dnf install -y buildah
buildah run "$DEV_CONTAINER" dnf clean all
buildah commit "$DEV_CONTAINER" "$DEV_IMAGE:latest"

# --- build runtime image ---
RUNTIME_ARCHIVE="${RUNTIME_IMAGE}.oci-archive"
ARCHIVE_PATH="$(pwd)/${RUNTIME_ARCHIVE}"
rm -f "$ARCHIVE_PATH"
trap 'rm -f "$ARCHIVE_PATH"' EXIT

# run dev container to build runtime-container
buildah run \
    --device /dev/fuse \
    --cap-add=CAP_SYS_ADMIN \
    -v "$(pwd)":"$HOSTMOUNT":Z \
    "$DEV_CONTAINER" -- /bin/bash "${HOSTMOUNT}/build_runtime_image.sh" "${HOSTMOUNT}/${RUNTIME_ARCHIVE}"

image_id=$(buildah pull "oci-archive:$ARCHIVE_PATH")
buildah tag "$image_id" "$RUNTIME_IMAGE:latest"

# test
podman run --rm "$RUNTIME_IMAGE:latest" /bin/bash -c 'echo "runtime container works"'
