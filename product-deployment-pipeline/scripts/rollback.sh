#!/bin/bash
# Rolls back the API and web Deployments to their previous ReplicaSet.
# Usage: ./rollback.sh <environment> [namespace]
set -e
ENVIRONMENT="${1:?environment is required}"
NAMESPACE="${2:-analytics}"

echo "⏪ Rolling back analytics-api and analytics-web in ${ENVIRONMENT} (namespace: ${NAMESPACE})"
kubectl rollout undo deployment/analytics-api -n "$NAMESPACE"
kubectl rollout undo deployment/analytics-web -n "$NAMESPACE"
kubectl rollout status deployment/analytics-api -n "$NAMESPACE" --timeout=180s
kubectl rollout status deployment/analytics-web -n "$NAMESPACE" --timeout=180s
echo "✅ Rollback complete"
