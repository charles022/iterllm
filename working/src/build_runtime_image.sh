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
buildah config --cmd '["/bin/bash","-c","echo Service Started; if [ -f /run/secrets/my_api_key ]; then echo Key available at /run/secrets/my_api_key; else echo Key missing; fi; sleep infinity"]' "$newcontainer"
buildah commit "$newcontainer" "oci-archive:${ARCHIVE_PATH}"
