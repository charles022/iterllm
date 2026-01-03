#!/bin/bash
set -euo pipefail

# This script runs *inside* the DEV build container.
# It assembles a minimal runtime rootfs under /out/rootfs
# and produces /out/rootfs.tar as the export artifact.

OUT_DIR="${OUT_DIR:-/out}"
ROOTFS_DIR="${ROOTFS_DIR:-$OUT_DIR/rootfs}"
TAR_PATH="${TAR_PATH:-$OUT_DIR/rootfs.tar}"

# Space-separated package list is easiest to pass/override
RUNTIME_PKGS="${RUNTIME_PKGS:-bash coreutils glibc}"

mkdir -p "$ROOTFS_DIR"

# Install runtime packages into the rootfs using the dev container's dnf/tooling
dnf -y \
  --installroot="$ROOTFS_DIR" \
  --nodocs \
  --setopt=install_weak_deps=False \
  install $RUNTIME_PKGS

dnf -y --installroot="$ROOTFS_DIR" clean all

# Optional hygiene: reduce size/noise
rm -rf "$ROOTFS_DIR/var/cache/dnf" || true
rm -rf "$ROOTFS_DIR/var/log/"* || true

# Ensure working dir exists in runtime
mkdir -p "$ROOTFS_DIR/src"

# Create tarball of the runtime filesystem
rm -f "$TAR_PATH"
tar --numeric-owner -C "$ROOTFS_DIR" -cf "$TAR_PATH" .

