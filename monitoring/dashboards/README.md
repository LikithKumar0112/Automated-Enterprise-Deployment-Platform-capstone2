# Dashboards

- `kube-prometheus-stack-values.yaml` - Helm values for Prometheus,
  Alertmanager, and Grafana (metrics side of monitoring).
- `grafana-analytics-dashboard.json` - importable Grafana dashboard for
  `analytics-api` request rate, error rate, pod restarts, and node CPU.
  Import via Grafana UI ("+" > Import > paste JSON) or reference it from
  `dashboardsConfigMaps` in the values file above for GitOps-style
  provisioning.

Log visualization (Kibana) lives with the rest of the EFK stack in
`monitoring/efk/`, not here - this folder is metrics/dashboards only.
