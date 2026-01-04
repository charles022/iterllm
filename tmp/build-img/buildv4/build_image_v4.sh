#!/bin/bash

set -eou pipefail

# use 'ssh style' notation... <machine>:<path on machine>
#
# note: buildah & podman store images in
#   ~/.local/share/containers/storage (when run as rootless)
#   or
#   /var/lib/containers/storage (when run as root)


# Set name variable based on current directory
PROJECT=$(basename "$PWD")

# Naming conventions
# use standard naming even for temp objects so that artifcats can be found and removed
DEV_IMAGE="${PROJECT}-dev-image"
DEV_CONTAINER="${PROJECT}-dev-container"
RUNTIME_IMAGE="${PROJECT}-runtime-image"
RUNTIME_CONTAINER="${PROJECT}-runtime-container"

# cleanup
# there is no -f flag with buildah rm
# ... || true is needed so a script doesnt exit on error
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




# --- build dev image ---
# pull/run fedora:latest container, base of dev image
# name it this way with "$DEV_CONTAINER" so that we can access it
buildah from --name "$DEV_CONTAINER" fedora:latest
# build dev image by modifying base container directly
buildah run "$DEV_CONTAINER" dnf update -y
buildah run "$DEV_CONTAINER" dnf install -y buildah # git vim gcc python3-pip
buildah run "$DEV_CONTAINER" dnf clean all
# commit container to dev-image
buildah commit "$DEV_CONTAINER" "$DEV_IMAGE"
# how to create persistent container from that image
# podman create -it --name "$CONTAINER_NAME" -v "$(pwd):/src:Z" "$CONTAINER_NAME" /bin/bash


# --- build runtime image ---
#
# following line does 3 things...
# 1) run container
# 2) mount local directory to container:/hostmount/
# 3) execute the runtime-image build script from inside the container, which...
#   places runtime-image at
#   localhost:./newimage
#   and
#   container:/hostmount/newimage
# notes:
#   to do 'buildah mount "$newcontainer"'
#   ... set '--device /dev/fuse --cap-add=CAP_SYS_ADMIN'
#   use -t for interactive
# ... possibly add to build_runtime_image.sh: 
# --setopt=install_weak_deps=False \
# coreutils glibc
buildah run \
    --device /dev/fuse \
    --cap-add=CAP_SYS_ADMIN \
    -v "$(pwd)":/hostmount:Z \
    "$DEV_CONTAINER" -- /bin/bash /hostmount/build_runtime_image.sh









# PROJECT=$(basename "$PWD")
# DEV_IMAGE="${PROJECT}-dev-image"
# DEV_CONTAINER="${PROJECT}-dev-container"
# RUNTIME_IMAGE="${PROJECT}-runtime-image"
# RUNTIME_CONTAINER="${PROJECT}-runtime-container"
# 
# # clean slate
# buildah rm "$DEV_CONTAINER" "$RUNTIME_CONTAINER" 2>/dev/null || true
# buildah from --name "$DEV_CONTAINER" fedora:latest
# buildah run "$DEV_CONTAINER" dnf update -y
# buildah run "$DEV_CONTAINER" dnf install -y buildah # git vim gcc python3-pip
# buildah run "$DEV_CONTAINER" dnf clean all
# buildah commit "$DEV_CONTAINER" "$DEV_IMAGE"
#
# from within the container...
# newcontainer=$(buildah from scratch)
# mnt=$(buildah mount "$newcontainer")


# # Install requirements via Host DNF
# dnf -y \
#     --installroot "$mnt" \
#     --releasever=41 \
#     --nodocs \
#     --setopt=install_weak_deps=False \
#     install bash coreutils glibc
# 
# # Cleanup metadata inside the mount
# dnf -y --installroot "$mnt" clean all
# 
# # Finalize
# buildah unmount "$RUNTIME_CONTAINER"
# buildah config --entrypoint '["/bin/bash"]' "$RUNTIME_CONTAINER"
# buildah commit "$RUNTIME_CONTAINER" "$RUNTIME_IMAGE"







# other...

# devctr=$(buildah from fedora:latest)
# buildah commit $devctr dev:latest
# devrun=$(buildah from dev:latest)
# buildah run --volume "$WORKDIR:/work" $devrun -- buildah unshare /work/build-runtime.sh
# 
# devctr=$(buildah from fedora:latest)
# buildah run $devctr -- dnf -y install buildah
# buildah commit $devctr dev:latest
# buildah rm $devctr
# 
# devrun=$(buildah from dev:latest)
# buildah run --volume "$WORKDIR:/work" $devrun -- buildah unshare /work/build-runtime.sh
# buildah rm $devrun


#
# notes:
#   buildah mount
#       mounts the containers filesystem to the host
#   buildah run -v
#       mounts host directories into the container
#   :Z
#        Fedora/SELinux systems - relabels the content for container access
#   no additional flags needed for read/write access, default
#   :ro
#       read-only access
#       -v "$(pwd)":/workspace:ro,Z
#   choosing to NOT use ...
#       [buildah run ...] --workingdir /hostmount
#       or
#       [buildah config ...] --workingdir /hostmount
#       ... and to instead use absolute path to access container:/hostmount/hello_world.sh
#       ... and absolute path inside hello_world.sh to write the new file to container:/hostmount/
