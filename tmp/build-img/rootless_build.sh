#!/bin/bash





# pull/run fedora:latest container, base of dev image
"$DEV_CONTAINER"=$(buildah from --name "$DEV_CONTAINER" fedora:latest)
# build dev image by modifying base container directly
buildah run "$DEV_CONTAINER" dnf update -y
buildah run "$DEV_CONTAINER" dnf install -y buildah # git vim gcc python3-pip
buildah run "$DEV_CONTAINER" dnf clean all
# optional, currently unused
# set default directory in container to /src
# not related to mounting filesystem (unless we want it to be)
#   buildah config --workingdir /src "$DEV_CONTAINER"
# commit container to dev-image
buildah commit "$DEV_CONTAINER" "$DEV_IMAGE"
# how to create persistent container from that image
# podman create -it --name "$CONTAINER_NAME" -v "$(pwd):/src:Z" "$CONTAINER_NAME" /bin/bash

# --- build runtime image ---

buildah run "$DEV_CONTAINER" bash ./




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
