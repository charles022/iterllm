#!/bin/bash

# note: buildah & podman store images in
#   ~/.local/share/containers/storage (when run as rootless)
#   or
#   /var/lib/containers/storage (when run as root)


# Set name variable based on current directory
PROJECT=$(basename "$PWD")

# Naming conventions
DEV_IMAGE="${PROJECT}-dev-image"
DEV_CONTAINER="${PROJECT}-dev-container"
RUNTIME_IMAGE="${PROJECT}-runtime-image"
RUNTIME_CONTAINER="${PROJECT}-runtime-container"

# cleanup
buildah rm -f "$DEV_CONTAINER" "$RUNTIME_CONTAINER" 2>/dev/null || true
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



# pull/run fedora:latest container, base of dev image
cnt=$(buildah from --name "$IMAGE_NAME" fedora:latest)
# build dev image by modifying base container directly
buildah run "$cnt" dnf update -y
buildah run "$cnt" dnf install -y git vim gcc python3-pip
buildah run "$cnt" dnf clean all
# optional, metadata, set workigndir as container-root/src
buildah config --workingdir /src "$cnt"
# commit container to dev-image
buildah commit "$cnt" "$DEV_IMAGE"
# how to create persistent container from that image
# podman create -it --name "$CONTAINER_NAME" -v "$(pwd):/src:Z" "$CONTAINER_NAME" /bin/bash







devctr=$(buildah from fedora:latest)
buildah commit $devctr dev:latest
devrun=$(buildah from dev:latest)
buildah run --volume "$WORKDIR:/work" $devrun -- buildah unshare /work/build-runtime.sh

devctr=$(buildah from fedora:latest)
buildah run $devctr -- dnf -y install buildah
buildah commit $devctr dev:latest
buildah rm $devctr

devrun=$(buildah from dev:latest)
buildah run --volume "$WORKDIR:/work" $devrun -- buildah unshare /work/build-runtime.sh
buildah rm $devrun
