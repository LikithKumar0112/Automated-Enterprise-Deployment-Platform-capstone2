#!/bin/bash
# Rolls back the API and web Deployments to their previous ReplicaSet, and
# prints the image before and after so the result can be verified.
# Usage: ./rollback.sh <environment> [namespace]
set -e
ENVIRONMENT="${1:?environment is required}"
NAMESPACE="${2:-analytics}"
DEPLOYMENTS=(analytics-api analytics-web)

show_images() {
    for d in "${DEPLOYMENTS[@]}"; do
        echo "  $d: $(kubectl get deployment "$d" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')"
    done
}

echo "⏪ Rolling back ${DEPLOYMENTS[*]} in ${ENVIRONMENT} (namespace: ${NAMESPACE})"
echo "Images before rollback:"
show_images
for d in "${DEPLOYMENTS[@]}"; do
    kubectl rollout undo "deployment/$d" -n "$NAMESPACE"
done
for d in "${DEPLOYMENTS[@]}"; do
    kubectl rollout status "deployment/$d" -n "$NAMESPACE" --timeout=180s
done
echo "Images after rollback:"
show_images
echo "✅ Rollback complete"
