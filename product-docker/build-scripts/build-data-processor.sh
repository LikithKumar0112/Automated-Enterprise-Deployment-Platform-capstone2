#!/bin/bash
set -e
TAG="${1:-latest}"
docker build --target data-processor -t "analytics-data-processor:${TAG}" -f Dockerfile .
