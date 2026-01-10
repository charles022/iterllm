#!/bin/bash

set -eou pipefail

REPO=$(basename "$(git rev-parse --show-toplevel)")
BRANCH=$(git branch --show-current) # alternate: BRANCH=$(git rev-parse --abbrev-ref HEAD)
PROJECT="$REPO-$BRANCH" # old: PROJECT=$(basename "$PWD")
IMAGE="${PROJECT}-image"
CONTAINER="${PROJECT}-container"
# DEV_IMAGE="${PROJECT}-dev-image"
# DEV_CONTAINER="${PROJECT}-dev-container"
# RUNTIME_IMAGE="${PROJECT}-runtime-image"
# RUNTIME_CONTAINER="${PROJECT}-runtime-container"
HOSTMOUNT="/hostmount"

skip_rebuild=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip_rebuild)      skip_rebuild=true ;;
        *)                   echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

if ! $skip_rebuild; then
    # ...
    # cleanup
    buildah rm "$CONTAINER" 2>/dev/null || true
    buildah rmi -f "$IMAGE" 2>/dev/null || true
    if podman container exists "$CONTAINER"; then
      podman rm -f "$CONTAINER"
    fi
    if podman image exists "$IMAGE"; then
      podman rmi -f "$IMAGE"
    fi
    
    # build dev container
    buildah from --name "$CONTAINER" --pull=newer fedora:latest
    buildah run "$CONTAINER" dnf update -y
    buildah run "$CONTAINER" dnf install -y buildah
    buildah run "$CONTAINER" dnf clean all
    buildah commit "$CONTAINER" "$IMAGE:latest"
fi



# test
podman run --rm "$IMAGE:latest" /bin/bash -c 'echo "container works"'
