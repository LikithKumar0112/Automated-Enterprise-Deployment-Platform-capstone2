#!/bin/bash
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
