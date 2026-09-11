#!/bin/bash
# Builds all three targets with the same tag - used by
# product-deployment-pipeline/Jenkinsfile's "Build & Test" stage.
set -e
TAG="${1:-latest}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$DIR/build-api.sh" "$TAG"
"$DIR/build-webapp.sh" "$TAG"
"$DIR/build-data-processor.sh" "$TAG"

echo "✅ Built analytics-api:${TAG}, analytics-web:${TAG}, analytics-data-processor:${TAG}"
