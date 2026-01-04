#!/bin/bash

set -eou pipefail

ARCHIVE_PATH="$1"

newcontainer=$(buildah from scratch)
mnt=$(buildah mount "$newcontainer")
dnf install -y \
    --installroot "$mnt" \
    --use-host-config \
    --nodocs \
    bash
dnf clean all --installroot "$mnt"
buildah config --cmd /bin/bash "$newcontainer"
buildah commit "$newcontainer" "oci-archive:${ARCHIVE_PATH}"
