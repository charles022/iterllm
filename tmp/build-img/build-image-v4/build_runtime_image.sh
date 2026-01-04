#!/bin/bash

set -eou pipefail


ARCHIVE_PATH="${1-}"


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


echo "committing runtime-container to image tarball at shared location>/$ARCHIVE_PATH"
buildah commit "$newcontainer" "oci-archive:${ARCHIVE_PATH}"
echo "successfully committed runtime container from inside dev container. exiting the build_runtime_image.sh script now"

# oci-archive is used to save it as a shareable tarball at set location rather than standard image storage methods inside this environment

# buildah commit "$newcontainer" "oci-archive:/hostmount/${FIFO_PATH}"
# buildah commit "$newcontainer" "$RUNTIME_IMAGE"
# buildah push "$RUNTIME_IMAGE" "oci-archive:/hostmount/${FIFO_PATH}"
# #echo "pushing $RUNTIME_IMAGE.tar to shared dev-container:/hostmount/ and localhost:./ "
# echo "pushing image to the FIFO (host is waiting to read)"

# 
# # suggested:
# # ./build_runtime_image.sh
# RUNTIME_IMAGE="..."
# buildah commit "$newcontainer" "$RUNTIME_IMAGE" # runtime-image
# # buildah push runtime-image oci-archive:/hostmount/${PROJECT:-runtime}-image.tar
# buildah push $"RUNTIME_IMAGE" oci-archive:/hostmount/${PROJECT:-runtime}-image.tar
# # And add a final step to build_image_v4.sh to auto-import:
# # After the buildah run command completes:
# # buildah pull oci-archive:./runtime-image.tar "$RUNTIME_IMAGE"
# buildah pull oci-archive:./"$RUNTIME_IMAGE".tar "$RUNTIME_IMAGE"
# echo "Runtime image available as: $RUNTIME_IMAGE"
# 
