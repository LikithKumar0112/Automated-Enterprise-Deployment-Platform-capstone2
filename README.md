# Automated Enterprise Product Deployment Platform

**Project Domain:** Product-Based Technology (Enterprise Analytics)

A standardized, automated deployment system for an enterprise analytics
product that works consistently across diverse customer environments
while maintaining enterprise-grade security and compliance. This project
simulates how DevOps is practiced inside a real product-based enterprise
company serving 100+ customers with self-hosted deployments.

By completing this project you will be able to:
- Design and operate production-grade CI/CD pipelines
- Provision infrastructure using Terraform
- Deploy and manage applications on Kubernetes (EKS)
- Implement DevSecOps, monitoring, logging, and compliance controls
- Handle enterprise failure scenarios and disaster recovery

**Project Repository:** https://github.com/SkillfymeLearning/Enterprise-Deployment-Platform.git

## Business Context & Industry Problem

The company develops and sells a data-intensive enterprise analytics
platform (on-premise/self-hosted). Customers deploy this product in their
own environments, which leads to inconsistent deployments, high support
costs from environment-specific issues, slow time-to-value, difficulty
scaling to new customer environments, and compliance requirements needing
audit trails and security controls.

**Real stakeholders:** Customer Success Teams, Support Engineers, Product
Teams, Security & Compliance, Sales Engineering.

## Quick Start

### Prerequisites
- AWS Account with appropriate permissions
- GitHub Account
- Tools: `aws-cli`, `kubectl`, `terraform`, `docker`, `maven`, `jq`

### Initial setup

```bash
git clone https://github.com/SkillfymeLearning/Enterprise-Deployment-Platform.git
cd enterprise-product-deployment
aws configure

# Bootstrap the remote state bucket/lock table once (see docs/runbooks.md), then:
cd product-infrastructure
terraform init -backend-config="bucket=<your-state-bucket>" -backend-config="region=<region>"
terraform workspace new dev && terraform workspace select dev
terraform apply -var-file="environments/dev/dev.tfvars"

aws eks update-kubeconfig --name analytics-dev --region <region>
cd ../product-kubernetes
kubectl apply -f configmap.yaml -f secrets.yaml -f deployment.yaml -f service.yaml -f ingress.yaml
```

Or simply: `./product-deployment-pipeline/scripts/deploy.sh dev apply`.
Full walkthrough in `docs/runbooks.md`.

## Repository Structure

```
enterprise-product-deployment/
├── product-deployment-pipeline/
│   ├── Jenkinsfile
│   ├── scripts/               deploy.sh, health-check.sh, rollback.sh, notify-slack.sh
│   └── shared-library/        vars/*.groovy - reusable pipeline steps
├── product-infrastructure/
│   ├── modules/
│   │   ├── eks-cluster/
│   │   ├── vpc-networking/
│   │   ├── monitoring-stack/
│   │   └── security-baseline/
│   ├── environments/
│   │   ├── dev/dev.tfvars
│   │   ├── stage/stage.tfvars
│   │   └── prod/prod.tfvars
│   ├── main.tf                 single root config, driven by terraform.workspace
│   ├── variables.tf
│   ├── outputs.tf
│   └── backend.tf
├── product-kubernetes/
│   ├── deployment.yaml          analytics-api + analytics-web + analytics-data-processor
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml             structural template only - see docs/security.md
│   └── ingress.yaml
├── product-docker/
│   ├── Dockerfile                single multi-stage, multi-target file (api/webapp/data-processor)
│   └── build-scripts/
├── monitoring/
│   ├── efk/                      Elasticsearch, Fluentd, Kibana
│   └── dashboards/                Prometheus/Grafana Helm values + dashboard JSON
├── docs/
│   ├── architecture.md
│   ├── runbooks.md
│   ├── incident-response.md
│   ├── security.md
│   └── cost-optimization.md
└── README.md
```

## Deployment Environments

- `dev` — Development environment
- `stage` — Staging/UAT environment
- `prod` — Production environment

These are **Terraform workspaces**, not separate directories — one root
config in `product-infrastructure/`, differentiated by
`environments/<env>/<env>.tfvars`. Zero manual configuration drift between
environments is the point.

## CI/CD Pipeline

```bash
git push origin main
# Jenkins: http://<jenkins-url>/job/enterprise-product-deployment

# Manual deployment (from repo root)
./product-deployment-pipeline/scripts/deploy.sh <environment>
```

Pipeline stages: code checkout → Maven build → security scanning
(SonarQube/Snyk/Trivy/Checkov) → Docker image build (three targets from
one Dockerfile) → push to registry → Terraform plan/apply → deploy to
Kubernetes → smoke tests → monitoring setup.

## Monitoring

- **EFK Stack** (`monitoring/efk/`) — centralized logging and visualization
- **Prometheus/Grafana** (`monitoring/dashboards/`) — metrics and dashboards
- **CloudWatch** — AWS-native infrastructure monitoring

Access Kibana: `kubectl port-forward svc/kibana 5601:5601 -n logging`

## Security

All security scans must pass before deployment: SonarQube (code quality),
Trivy (container images), Checkov (Terraform). Secrets management via
HashiCorp Vault / AWS Secrets Manager — no secrets in Git, dynamic
injection at deploy time. See `docs/security.md`.

## Disaster Recovery

- **RTO:** 4 hours | **RPO:** 24 hours | **Rollback time:** < 15 minutes
- Blue/Green-style rolling deploys for zero-downtime, Terraform state
  versioning (S3 + DynamoDB), database backup/restore procedures,
  full incident response runbooks in `docs/incident-response.md`.

## Cost Optimization

Spot instances for interruption-tolerant workloads, autoscaling policies,
resource rightsizing, cost anomaly detection. See `docs/cost-optimization.md`.

## Failure Scenarios

Ten scenarios are simulated and documented per `docs/incident-response.md`:
Terraform state corruption, Docker registry outage, EKS control plane
outage, Jenkins pipeline failure, Maven dependency failure, Kubernetes
node failure, AWS region outage, Git repository corruption, certificate
expiration, configuration drift.

## Phase-wise Execution Checklist

Each task below needs both **execution** and a submittable **expected
outcome** — see `docs/runbooks.md` for the full proof-of-execution list.

**Phase 1 — Foundation**
- [ ] Task 1: CI/CD Pipeline Setup (Jenkinsfile, pipeline logs, image push logs, webhook screenshot)
- [ ] Task 2: Infrastructure Provisioning (Terraform code, plan/apply output, EKS visible in console)
- [ ] Task 3: Kubernetes Deployment (K8s YAMLs, `kubectl get pods`, accessible endpoint)

**Phase 2 — Enterprise Readiness**
- [ ] Task 4: Multi-Environment Deployment (workspace config, 3 environments deployed, zero drift)
- [ ] Task 5: Security & Secrets (scan reports, pipeline fails on critical vulns, dynamic secret injection proof)
- [ ] Task 6: Monitoring Implementation (log ingestion proof, dashboard screenshots, alert config)

**Phase 3 — Scale & Optimization**
- [ ] Task 7: Deployment Templating (parameterized builds, 10+ environment deploys)
- [ ] Task 8: Rollback & DR (rollback logs, backup verification, RTO/RPO documentation)
- [ ] Task 9: Cost Optimization (cost report, before/after comparison, Trusted Advisor findings)

**Phase 4 — Failure & Incident Simulation** (see `docs/incident-response.md`)

## Final Deliverables

All repositories · Terraform modules · Jenkins configuration ·
Kubernetes manifests · Monitoring dashboards · Security scan reports ·
Incident response documentation · Cost optimization report ·
Architecture diagrams · Runbooks.

## Evaluation Criteria

Correctness · Security depth · Troubleshooting maturity ·
Documentation clarity · Ability to explain architectural decisions.

## Non-Goals & Out-of-Scope

Intentionally **not** built here (owned by other teams): customer-facing
deployment UI (Product), billing/invoicing (Finance), product licensing
enforcement (Product/Legal), customer support ticketing (Customer
Success), product feature development (Product Engineering), sales demo
environments (Sales Engineering), customer data migration tools
(Professional Services). Also explicitly out of scope: managing customer
AWS accounts, product application code development, end-user training,
sales/marketing collateral, legal/compliance certification, product
pricing, and customer contract negotiations.

This scoping exists for role clarity (DevOps Engineer owns deployment
automation, not product development or customer-facing functions), clean
team boundaries, and single-threaded ownership of deployment reliability.

## Support

GitHub Issues for technical problems and bug reports · `/docs` for
comprehensive guides · runbooks for operational procedures.
