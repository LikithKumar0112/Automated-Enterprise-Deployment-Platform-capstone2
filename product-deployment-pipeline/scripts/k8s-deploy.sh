#!/bin/bash
set -euo pipefail

cd product-kubernetes
sed -e "s#analytics-api:latest#$ECR_REGISTRY/analytics-api:$IMAGE_TAG#g" \
    -e "s#analytics-web:latest#$ECR_REGISTRY/analytics-web:$IMAGE_TAG#g" \
    -e "s#analytics-data-processor:latest#$ECR_REGISTRY/analytics-data-processor:$IMAGE_TAG#g" \
    deployment.yaml > deployment.rendered.yaml

kubectl apply -f configmap.yaml
kubectl apply -f deployment.rendered.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml

# rollout status waits for the new pods, not just any available pods
kubectl rollout status deployment/analytics-api -n analytics --timeout=300s
kubectl rollout status deployment/analytics-web -n analytics --timeout=300s
