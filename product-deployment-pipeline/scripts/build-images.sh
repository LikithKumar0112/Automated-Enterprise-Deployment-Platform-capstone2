#!/bin/bash
set -euo pipefail

cd product-docker
./build-scripts/stage-local-app.sh
docker build --target api            -t "$ECR_REGISTRY/analytics-api:$IMAGE_TAG" .
docker build --target webapp         -t "$ECR_REGISTRY/analytics-web:$IMAGE_TAG" .
docker build --target data-processor -t "$ECR_REGISTRY/analytics-data-processor:$IMAGE_TAG" .
