#!/bin/bash
set -e
TAG="${1:-latest}"
docker build --target api -t "analytics-api:${TAG}" -f Dockerfile .
