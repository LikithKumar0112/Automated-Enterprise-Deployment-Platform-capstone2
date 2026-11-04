# Architecture Design

## Overview

The platform deploys an enterprise analytics product to AWS EKS across
three environments/Terraform workspaces (`dev`, `stage`, `prod`) from a
single Terraform root config (`product-infrastructure/main.tf`) with
per-environment `.tfvars` files. Kubernetes-side, three components run in
the `analytics` namespace: `analytics-api`, `analytics-web`, and the
hourly `analytics-data-processor` CronJob — matching the WebApp/API
layer/Data Processing Engine split in the diagram below.

```
                         ┌─────────────────────────────────────────┐
                         │              Route 53 / DNS               │
                         └───────────────────┬─────────────────────┘
                                              │
                         ┌───────────────────▼─────────────────────┐
                         │      Application Load Balancer (WAF)      │
                         │  product-infrastructure/modules/security-baseline│
                         │  product-kubernetes/ingress.yaml          │
                         └───────────┬───────────────┬──────────────┘
                                     │               │
                         ┌───────────▼──┐   ┌────────▼──────┐
                         │ analytics-web │   │ analytics-api │
                         │ (nginx, static)│   │ (Spring Boot) │
                         └───────────────┘   └───────┬────────┘
                                                      │
                                          ┌───────────▼───────────┐
                                          │ analytics-data-processor│
                                          │  (hourly CronJob)       │
                                          └─────────────────────────┘

         EKS cluster (private subnets)                 Observability
   ┌────────────────────────────────┐        ┌──────────────────────────┐
   │ node group: general (on-demand) │        │ Prometheus/Grafana        │
   │ node group: spot (batch/tolerant)│       │ (monitoring/dashboards/)  │
   └────────────────────────────────┘        │ EFK (monitoring/efk/)     │
                                              │ CloudWatch + SNS          │
                                              └──────────────────────────┘
```

## Components

### Compute — `product-infrastructure/modules/eks-cluster`
- One EKS cluster per Terraform workspace, private API endpoint by default
  (opened only for `dev`, see `environments/dev/dev.tfvars`).
- Two managed node groups: `general` (on-demand, serves `analytics-api` /
  `analytics-web`) and `spot` (tainted, absorbs `analytics-data-processor`).
- Secrets envelope-encrypted with a dedicated KMS key; control-plane logs
  shipped to CloudWatch.
- OIDC provider for IRSA (so add-ons like the AWS Load Balancer Controller
  don't need node-wide IAM permissions).

### Networking — `product-infrastructure/modules/vpc-networking`
- One VPC per workspace, public + private subnets across 2–3 AZs.
- `dev`/`stage` share a single NAT gateway; `prod` runs one per AZ.
- VPC Flow Logs to CloudWatch.

### Application layer — `product-kubernetes/`
Flat manifest set (no Helm/Kustomize at this layer, by design):
- `deployment.yaml` — three `---`-separated documents: the
  `analytics-api` and `analytics-web` Deployments, plus the
  `analytics-data-processor` CronJob.
- `service.yaml` — ClusterIP Services for API and web.
- `ingress.yaml` — ALB Ingress resources for API and web.
- `configmap.yaml` / `secrets.yaml` — app config and the secrets
  *template* (see `docs/security.md` — never filled with real values here).

Because there's no Kustomize overlay layer, image tags are rendered into a
git-ignored `deployment.rendered.yaml` before `kubectl apply` (`sed` in
`product-deployment-pipeline/scripts/deploy.sh` and the Jenkinsfile's
`Kubernetes Deploy` stage), so the checked-in files always show the `analytics-api:latest` /
`analytics-web:latest` / `analytics-data-processor:latest` placeholders.

### CI/CD — `product-deployment-pipeline/`
`Jenkinsfile` is the pipeline entry point; `scripts/` holds `deploy.sh` (the
manual/local equivalent) and helpers both of them call (`health-check.sh`,
`rollback.sh`, `sync-secrets.sh`, `scan-image.sh`, `notify-slack.sh`) and one
script for each larger pipeline step (`build-images.sh`, `k8s-deploy.sh`, and so on).
`shared-library/vars/*.groovy` exists but isn't called by the Jenkinsfile yet. See
`docs/runbooks.md` for the full stage-by-stage walkthrough.

### Observability — `monitoring/`
- `monitoring/dashboards/` — Prometheus/Alertmanager/Grafana via the
  `kube-prometheus-stack` Helm chart, plus an importable Grafana dashboard
  JSON for `analytics-api` metrics.
- `monitoring/efk/` — Elasticsearch + Fluentd + Kibana for centralized log
  aggregation, applied with `kubectl apply -k efk/`.
- `product-infrastructure/modules/monitoring-stack` — CloudWatch alarms +
  SNS, for infrastructure-level alerting that survives even if the
  in-cluster stack itself is degraded.

### Security — `product-infrastructure/modules/security-baseline`, `product-docker/Dockerfile`
- All three container targets (`api`, `webapp`, `data-processor`) in the
  single multi-stage `Dockerfile` run as a non-root user.
- Application secrets live in AWS Secrets Manager, encrypted with a
  dedicated KMS key, never committed to Git.
- `scripts/sync-secrets.sh` copies them into the `api-secrets` Kubernetes
  Secret at deploy time.
- A per-workspace `ci_deploy` IAM role and a WAFv2 web ACL are provisioned but
  not in use yet (see `docs/security.md`).

## Data flow (a single deployment)

1. A Jenkins pipeline run is started with `ENVIRONMENT` and `ACTION`.
2. Checkov scans the Terraform and Snyk scans the Maven dependencies.
3. Maven tests run, then `product-docker/Dockerfile` builds all three targets
   (`--target api`, `--target webapp`, `--target data-processor`). Trivy scans
   them, and they're pushed to ECR on `ACTION=apply`.
4. `terraform workspace select <env>` (or `new` on first run) →
   `terraform plan`/`apply -var-file=environments/<env>/<env>.tfvars`
   against the single `product-infrastructure/main.tf` root — manual
   approval gate for `prod`.
5. `sync-secrets.sh` builds `api-secrets`, then `kubectl apply` the rendered
   `product-kubernetes/` manifests, wait for rollout, and run smoke tests
   against the Ingress health endpoints.
6. If the deploy or smoke tests fail, the pipeline runs `rollback.sh` (see
   `docs/incident-response.md`, `product-deployment-pipeline/scripts/rollback.sh`).

## Why this shape

- **Workspaces, not directories, for environments** (per the capstone's
  Task 4): one root Terraform config avoids three near-duplicate copies of
  `main.tf` drifting apart; `.tfvars` per environment is the only thing
  that differs, and workspace-scoped state (`workspace_key_prefix`) keeps
  state files isolated per environment inside one backend config.
- **Flat `product-kubernetes/` manifests over Kustomize**: matches the
  capstone's specified structure directly — five files, one per resource
  type, each a multi-document YAML where more than one workload of that
  type exists.
- **Single multi-target Dockerfile over per-service Dockerfiles**: matches
  `product-docker/`'s single-`Dockerfile` layout while still producing
  three independently buildable images via `--target`.
