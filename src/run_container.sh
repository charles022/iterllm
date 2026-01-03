#!/bin/bash
set -e

# build and run container from image
# use: ./run_container.sh --runtime to build/run the runtime container


PROJECT=$(basename "$PWD")

# Default to Dev settings
IMAGE_NAME="${PROJECT}-dev-image"
MODE="Development"

# Check for optional argument
if [[ "$1" == "--runtime" ]]; then
    IMAGE_NAME="${PROJECT}-runtime-image"
    MODE="Runtime"
fi

echo "Starting $MODE Environment for: $PROJECT"
echo "Mounting $PWD -> /src"

# Run container
# -it: Interactive terminal
# --rm: Delete container on exit
# -v:  Bind mount current dir to /src (with SELinux :Z)
podman run -it --rm \
    -v "$PWD":/src:Z \
    "localhost/$IMAGE_NAME"
