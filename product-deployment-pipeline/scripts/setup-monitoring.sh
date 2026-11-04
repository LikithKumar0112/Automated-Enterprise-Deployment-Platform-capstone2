#!/bin/bash
set -euo pipefail

cd monitoring
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Alertmanager reads the Slack webhook from this secret
printf '%s' "$SLACK_WEBHOOK_URL" | kubectl create secret generic alertmanager-slack \
    -n monitoring --from-file=webhook=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap grafana-analytics-dashboard \
    --from-file=dashboards/grafana-analytics-dashboard.json \
    -n monitoring --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring -f dashboards/kube-prometheus-stack-values.yaml

kubectl apply -k efk/
kubectl apply -f dashboards/analytics-api-servicemonitor.yaml
