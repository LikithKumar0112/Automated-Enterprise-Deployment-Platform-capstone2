#!/bin/bash
# Local-dev-only helper: builds the app/ stubs with Maven and copies their
# output into product-docker/, mirroring what the real Jenkinsfile does for
# a real analytics-app checkout (`cp -r app/target infra/product-docker/target`).
# Not part of the CI path - Jenkins never runs this script, it does the
# equivalent inline against a real app repo. Run this once (or whenever
# app/ changes) before ./build-scripts/build-all.sh.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"          # product-docker/build-scripts
DOCKER_DIR="$(dirname "$DIR")"                                # product-docker
APP_DIR="$(cd "$DOCKER_DIR/../app" && pwd)"                    # app/

echo "📦 Building app/api ..."
(cd "$APP_DIR/api" && mvn -q clean package -DskipTests)

echo "📦 Building app/data-processor ..."
(cd "$APP_DIR/data-processor" && mvn -q clean package)

echo "📦 Staging build output into product-docker/ ..."
rm -rf "$DOCKER_DIR/target"
mkdir -p "$DOCKER_DIR/target"
cp "$APP_DIR/api/target/analytics-api-"*.jar "$DOCKER_DIR/target/"
cp "$APP_DIR/data-processor/target/analytics-data-processor-"*.jar "$DOCKER_DIR/target/"
cp "$APP_DIR/api/src/main/resources/application-prod.yml" "$DOCKER_DIR/application-prod.yml"

rm -rf "$DOCKER_DIR/dist"
cp -r "$APP_DIR/webapp/dist" "$DOCKER_DIR/dist"
cp "$APP_DIR/webapp/nginx.conf" "$DOCKER_DIR/nginx.conf"
cp "$APP_DIR/webapp/mime.types" "$DOCKER_DIR/mime.types"

echo "✅ Staged. product-docker/ now has target/, dist/, application-prod.yml, nginx.conf, mime.types"
echo "   Run ./build-scripts/build-all.sh <tag> next."
