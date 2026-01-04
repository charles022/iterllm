#!/usr/bin/env bash

devctr=$(buildah from fedora:latest)
buildah run $devctr -- dnf -y install buildah
buildah commit $devctr dev:latest
buildah rm $devctr

devrun=$(buildah from dev:latest)
buildah run --volume "$WORKDIR:/work" $devrun -- buildah unshare /work/build-runtime.sh
buildah rm $devrun
