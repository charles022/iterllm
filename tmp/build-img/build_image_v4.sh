#!/bin/bash


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

podman create -it --name "$CONTAINER_NAME" -v "$(pwd):/src:Z" "$CONTAINER_NAME" /bin/bash



# --- build runtime image ---
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
# following line does 3 things...
# 1) run container
# 2) mount local directory to container:/hostmount/
# 3) execute the runtime-image build script from inside the container, which...
#   ... places runtime-image at
#   ... localhost:./newimage
#       and
#   ... container:/hostmount/newimage
buildah run \
    -v "$(pwd)":/hostmount:Z \
    "$DEV_CONTAINER" -- /bin/bash /hostmount/build_runtime_image.sh


# interactively
buildah run -t \
    -v "$(pwd)":/hostmount:Z \
    --privledged \
    "$DEV_CONTAINER" -- /bin/bash






PROJECT=$(basename "$PWD")
DEV_IMAGE="${PROJECT}-dev-image"
DEV_CONTAINER="${PROJECT}-dev-container"
RUNTIME_IMAGE="${PROJECT}-runtime-image"
RUNTIME_CONTAINER="${PROJECT}-runtime-container"

# clean slate
buildah rm "$DEV_CONTAINER" "$RUNTIME_CONTAINER" 2>/dev/null || true
buildah from --name "$DEV_CONTAINER" fedora:latest
buildah run "$DEV_CONTAINER" dnf update -y
buildah run "$DEV_CONTAINER" dnf install -y buildah # git vim gcc python3-pip
buildah run "$DEV_CONTAINER" dnf clean all
buildah commit "$DEV_CONTAINER" "$DEV_IMAGE"

# interactively
# possibly run with...
# --cap-add=CAP_SYS_ADMIN  or =all
buildah run -t \
    -v "$(pwd)":/hostmount:Z \
    "$DEV_CONTAINER" -- /bin/bash


# from within the container...
newcontainer=$(buildah from scratch)
mnt=$(buildah mount "$newcontainer")


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






# [chuck@7510 tdir | 1767476676 | 7342.43]$ PROJECT=$(basename "$PWD")
# DEV_IMAGE="${PROJECT}-dev-image"
# DEV_CONTAINER="${PROJECT}-dev-container"
# RUNTIME_IMAGE="${PROJECT}-runtime-image"
# RUNTIME_CONTAINER="${PROJECT}-runtime-container"
# [chuck@7510 tdir | 1767476676 | 7349.25]$ buildah rm "$DEV_CONTAINER" "$RUNTIME_CONTAINER" 2>/dev/null || true
# bd51f03a516780697e94bac446b2003c9a7436275e05b255139fd2691caa946b
# [chuck@7510 tdir | 1767476676 | 7355.53]$ buildah from --name "$DEV_CONTAINER" fedora:latest
# tdir-dev-container
# [chuck@7510 tdir | 1767476676 | 7467.83]$ buildah commit "$DEV_CONTAINER" "$DEV_IMAGE"
# Getting image source signatures
# Copying blob 516b47e1f451 skipped: already exists
# Copying blob 8ddf437fb54b done   |
# Copying config c9220fbb51 done   |
# Writing manifest to image destination
# c9220fbb51c244cf1aeaecd8d498ade138f7b907229c623bfa35d22ee8131daf
# [chuck@7510 tdir | 1767476676 | 7475.77]$ buildah run -t \
#     -v "$(pwd)":/hostmount:Z \
#     "$DEV_CONTAINER" -- /bin/bash
# [root@f60c3007d4da /]# newcontainer=$(buildah from scratch)
# [root@f60c3007d4da /]# mnt=$(buildah mount "$newcontainer")
# Error: overlay: failed to make mount private: mount /var/lib/containers/storage/overlay:/var/lib/containers/storage/overlay, flags: 0x1000: operation not permitted
# WARN[0000] failed to shutdown storage: "overlay: failed to make mount private: mount /var/lib/containers/storage/overlay:/var/lib/containers/storage/overlay, flags: 0x1000: operation not permitted"
# [root@f60c3007d4da /]# exit
# exit
# Error: while running runtime: exit status 125
# [chuck@7510 tdir | 1767476676 | 7677.90]$ buildah run -t \
#     -v "$(pwd)":/hostmount:Z \
#     --privileged \
#     "$DEV_CONTAINER" -- /bin/bash
# Error: unknown flag: --privileged
# [chuck@7510 tdir | 1767476676 | 7719.01]$
