#!/bin/bash

PROJECT=$(basename "$PWD")
DEV_IMAGE="${PROJECT}-dev-image"
DEV_CONTAINER="${PROJECT}-dev-container"
RUNTIME_IMAGE="${PROJECT}-runtime-image"
RUNTIME_CONTAINER="${PROJECT}-runtime-container"
buildah run \
    --device /dev/fuse \
    --cap-add=CAP_SYS_ADMIN \
    -v "$(pwd)":/hostmount:Z \
    "$DEV_CONTAINER" -- /bin/bash /hostmount/build_runtime_image.sh
