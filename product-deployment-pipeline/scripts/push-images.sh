#!/bin/bash
set -euo pipefail

aws ecr get-login-password --region "$AWS_REGION" |
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

for image in analytics-api analytics-web analytics-data-processor; do
    docker push "$ECR_REGISTRY/$image:$IMAGE_TAG"
done
