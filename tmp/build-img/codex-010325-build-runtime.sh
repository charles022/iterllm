#!/usr/bin/env bash

rtctr=$(buildah from scratch)
rtmnt=$(buildah mount $rtctr)
dnf -y --installroot "$rtmnt" --releasever=latest install bash python rustup
buildah umount $rtctr
buildah commit $rtctr runtime:latest
buildah rm $rtctr
