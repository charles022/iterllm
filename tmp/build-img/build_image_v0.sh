#!/bin/bash

# 1. Generate a name based on the current directory (e.g., "my-project-env")
DIR_NAME=$(basename "$PWD")
IMAGE_NAME="${DIR_NAME}-image"
CONTAINER_NAME="${DIR_NAME}-container"

# echo "--- Building native environment for: $CONTAINER_NAME ---"

# 2. Clean up existing container/image to ensure "freshness"
# try...
buildah rm "$CONTAINER_NAME" 2>/dev/null
buildah rmi "$CONTAINER_NAME" 2>/dev/null

if podman container exists "$CONTAINER_NAME"; then
  podman rm -f "$CONTAINER_NAME"
fi

if podman image exists "$IMAGE_NAME"; then
  podman rmi -f "$IMAGE_NAME"
fi

# 3. Create the working container
cnt=$(buildah from --name "$IMAGE_NAME" fedora:latest)

# 4. Run your setup commands directly
# Buildah executes these against the container's filesystem
buildah run "$cnt" dnf update -y
buildah run "$cnt" dnf install -y git vim gcc python3-pip
buildah run "$cnt" dnf clean all

# 5. Configure the container metadata
buildah config --workingdir /src "$cnt"
buildah config --author "Gemini User" "$cnt"

# 6. "Commit" it to an image named after the directory
buildah commit "$cnt" "$CONTAINER_NAME"

# 7. Create the actual persistent container from that image
podman create -it --name "$CONTAINER_NAME" -v "$(pwd):/src:Z" "$CONTAINER_NAME" /bin/bash

echo "--- Setup Complete! Use 'enter-env.sh' to start working. ---"
