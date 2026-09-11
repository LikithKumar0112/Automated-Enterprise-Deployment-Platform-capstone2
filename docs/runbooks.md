# Deployment Guide / Runbooks

## Prerequisites

`aws-cli` v2, `kubectl` >= 1.24, `terraform` >= 1.0, `docker`, `maven`, `jq`.
AWS credentials with access to the target environment (Vault-issued
short-lived credentials in CI, or `aws configure` locally).

## One-time bootstrap (per AWS account)

The S3 state bucket and DynamoDB lock table referenced by
`product-infrastructure/backend.tf` must exist before the first `terraform init`:

```bash
aws s3api create-bucket --bucket analytics-tf-state-<account-id> --region us-east-1
aws s3api put-bucket-versioning --bucket analytics-tf-state-<account-id> \
    --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name analytics-tf-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
```

## Manual deployment (local machine)

```bash
git clone https://github.com/SkillfymeLearning/Enterprise-Deployment-Platform.git
cd enterprise-product-deployment

./product-deployment-pipeline/scripts/deploy.sh dev apply
```

Or step by step, mirroring what `deploy.sh` does:

```bash
cd product-infrastructure
terraform init -backend-config="bucket=analytics-tf-state-<account-id>" -backend-config="region=us-east-1"

# Environments are Terraform workspaces, not separate directories:
terraform workspace new dev        # first time only
terraform workspace select dev
terraform plan  -var-file="environments/dev/dev.tfvars" -var="image_tag=<tag>"
terraform apply -var-file="environments/dev/dev.tfvars" -var="image_tag=<tag>"

aws eks update-kubeconfig --name analytics-dev --region us-east-1

cd ../product-kubernetes
kubectl create namespace analytics --dry-run=client -o yaml | kubectl apply -f -
# Substitute the placeholder image names before applying:
sed -i "s#analytics-api:latest#<ecr-registry>/analytics-api:<tag>#g" deployment.yaml
sed -i "s#analytics-web:latest#<ecr-registry>/analytics-web:<tag>#g" deployment.yaml
kubectl apply -f configmap.yaml -f secrets.yaml -f deployment.yaml -f service.yaml -f ingress.yaml
kubectl wait --for=condition=available --timeout=300s deployment/analytics-api -n analytics
kubectl wait --for=condition=available --timeout=300s deployment/analytics-web -n analytics
git checkout -- deployment.yaml   # restore the placeholder so the diff stays clean
```

`product-deployment-pipeline/scripts/deploy.sh <environment> <action> [image_tag] [run_tests] [security_scan]`
wraps all of the above — same entry point Jenkins uses for a manual/
break-glass deploy.

## CI deployment (Jenkins)

1. Trigger the pipeline with `ENVIRONMENT` = `dev` / `stage` / `prod`.
2. Stages run in order: `Initialize` → `Security Scan` → `Build & Test` →
   `Infrastructure Plan` → **Manual Approval (prod only)** →
   `Infrastructure Apply` → `Kubernetes Deploy` → `Smoke Tests` →
   `Monitoring Setup`.
3. Review the archived `tfplan.json` before approving a `prod` apply.
4. Success/failure post to `#deployments` / `#deployments-alerts` in Slack;
   `prod` failures auto-rollback (see `docs/incident-response.md`).

## Promoting a build between environments

The same image tag should move `dev → stage → prod` unchanged:

```bash
./product-deployment-pipeline/scripts/deploy.sh stage apply <tag-that-passed-dev> false false
./product-deployment-pipeline/scripts/deploy.sh prod  apply <tag-that-passed-stage> false false
```

`run_tests`/`security_scan` are `false` here because they already gated
the `dev` deploy of this exact artifact.

## Rolling back

```bash
./product-deployment-pipeline/scripts/rollback.sh <environment>
```

## Destroying an environment

```bash
./product-deployment-pipeline/scripts/deploy.sh dev destroy
```

There is no confirmation prompt beyond `terraform destroy -auto-approve` —
never run this against `prod` outside a planned decommission.

## Proof-of-execution checklist (what the capstone brief asks you to submit per task)

This repo gives you working code to run — the actual "expected outcomes"
listed in the capstone brief (pipeline logs, `terraform apply` output,
`kubectl get pods`, dashboard screenshots, etc.) only exist once you run
these commands against a real AWS account/Jenkins instance. Nothing here
fabricates those artifacts for you:

- [ ] Jenkins pipeline run, green, with webhook trigger screenshot
- [ ] `terraform plan` / `terraform apply` output for each workspace
- [ ] EKS cluster visible in the AWS console
- [ ] `kubectl get pods -n analytics` output showing all three workloads healthy
- [ ] Application reachable at the Ingress-assigned endpoint
- [ ] Trivy/Checkov/SonarQube scan reports attached
- [ ] Kibana log ingestion + Grafana dashboard screenshots
- [ ] Rollback demonstration log (`rollback.sh` output, before/after `kubectl get rs`)
