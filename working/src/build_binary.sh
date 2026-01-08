#!/bin/bash

set -eou pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
REPO="$(basename "$PROJECT_ROOT")"
BRANCH_RAW="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$BRANCH_RAW" ]]; then
    BRANCH_RAW="$(git rev-parse --abbrev-ref HEAD)"
fi
BRANCH_SAFE="$(printf '%s' "$BRANCH_RAW" | LC_ALL=C tr '/ ' '--')"
PROJECT="${REPO}-${BRANCH_SAFE}"

BIN_NAME="${BIN_NAME:-iterllm}"
BUILD_OUTPUT="${BUILD_OUTPUT:-${PROJECT_ROOT}/bin/${BIN_NAME}}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
if [[ -n "${INSTALL_PATH:-}" ]]; then
    INSTALL_DIR="$(dirname "$INSTALL_PATH")"
else
    INSTALL_PATH="${INSTALL_DIR}/${PROJECT}"
fi
BUILD_CMD="${BUILD_CMD:-}"

if [[ -n "$BUILD_CMD" ]]; then
    echo "Running build command: $BUILD_CMD"
    (cd "$PROJECT_ROOT" && eval "$BUILD_CMD")
fi

if [[ ! -x "$BUILD_OUTPUT" ]]; then
    cat <<EOF
Error: expected executable at ${BUILD_OUTPUT}

Set BUILD_CMD to produce it (example):
  BUILD_CMD='go build -o bin/iterllm ./cmd/iterllm' ./build_binary.sh
EOF
    exit 1
fi

install -d -m 0755 "$INSTALL_DIR"
install -m 0755 "$BUILD_OUTPUT" "$INSTALL_PATH"

echo "Installed binary to ${INSTALL_PATH}"
