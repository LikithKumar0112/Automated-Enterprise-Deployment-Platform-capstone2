#!/bin/bash
# Fails if a local image has a fixable HIGH/CRITICAL vulnerability. Scans the
# exported filesystem because Trivy couldn't read the nginx image through the
# Docker socket or `docker save` on the containerd image store. A Trivy error
# also fails the scan, so an unscanned image can't pass.
# Usage: ./scan-image.sh <image>
set -euo pipefail
IMAGE="${1:?image is required}"
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.69.3}"

WORK_DIR="$(mktemp -d)"
CONTAINER="$(docker create "$IMAGE")"
cleanup() {
    docker rm "$CONTAINER" > /dev/null 2>&1 || true
    chmod -R u+rwX "$WORK_DIR" 2> /dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

docker export "$CONTAINER" | tar -x -C "$WORK_DIR" --no-same-owner --exclude='dev/*' --exclude='proc/*' --exclude='sys/*'
chmod -R u+rX,go+rX "$WORK_DIR"

echo "Scanning $IMAGE ..."
docker run --rm -v "$WORK_DIR:/scan:ro" -v trivy-cache:/root/.cache "$TRIVY_IMAGE" \
    rootfs --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed /scan
