#!/bin/bash
set -e
TAG="${1:-latest}"
docker build --target webapp -t "analytics-web:${TAG}" -f Dockerfile .
