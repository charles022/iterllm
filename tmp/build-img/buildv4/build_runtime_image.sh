#!/bin/bash

set -eou pipefail

echo "building runtime-container from scratch image..."
newcontainer=$(buildah from scratch)

echo "mounting scratch/runtime-container, requires privleges..."
mnt=$(buildah mount "$newcontainer")

echo "using dnf to install to mounted runtime/scratch-container from inside the dev-container..."
dnf install -y \
    --installroot "$mnt" \
    --use-host-config \
    --nodocs \
    bash
dnf clean all --installroot "$mnt"

echo "committing runtime-container to runtime-image..."
buildah commit "$newcontainer" runtime-image

echo "pushing runtime-image.tar to shared dev-container:/hostmount/ and localhost:./ "
buildah push runtime-image oci-archive:/hostmount/runtime-image.tar

