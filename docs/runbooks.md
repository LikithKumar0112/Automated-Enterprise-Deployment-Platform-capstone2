# Deployment Guide / Runbooks

## Prerequisites

`aws-cli` v2, `kubectl` >= 1.24, `helm`, `terraform` >= 1.0, `docker`, `maven`, `jq`,
and `snyk` on the Jenkins host. AWS credentials with access to the target
environment (the `jenkins` system user's in CI, or `aws configure` locally).

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

## One-time setup (ECR)

Terraform doesn't create the image repositories, and images are pushed before
`terraform apply`. Create them once per account:

```bash
for repo in analytics-api analytics-web analytics-data-processor; do
    aws ecr create-repository --repository-name "$repo" --image-scanning-configuration scanOnPush=true
done
```

## One-time setup (per environment)

Run after the first `terraform apply` creates the secret containers. Deploys
fail until these values exist:

```bash
aws secretsmanager put-secret-value --secret-id analytics-dev/db-credentials \
    --secret-string '{"DB_USERNAME":"<user>","DB_PASSWORD":"<password>","DB_URL":"<jdbc-url>"}'
aws secretsmanager put-secret-value --secret-id analytics-dev/api-keys \
    --secret-string '{"JWT_SIGNING_KEY":"<key>"}'
```

## One-time setup (Jenkins)

Add two **Secret text** credentials: `snyk-api-token` and `slack-webhook-url`.
Point the job's Script Path at `product-deployment-pipeline/Jenkinsfile`.

## Manual deployment (local machine)

```bash
git clone https://github.com/LikithKumar0112/Automated-Enterprise-Deployment-Platform-capstone2.git
cd Automated-Enterprise-Deployment-Platform-capstone2

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

cd ..
kubectl create namespace analytics --dry-run=client -o yaml | kubectl apply -f -
./product-deployment-pipeline/scripts/sync-secrets.sh dev

cd product-kubernetes
# Render the real image names into a git-ignored copy:
sed -e "s#analytics-api:latest#<ecr-registry>/analytics-api:<tag>#g" \
    -e "s#analytics-web:latest#<ecr-registry>/analytics-web:<tag>#g" \
    -e "s#analytics-data-processor:latest#<ecr-registry>/analytics-data-processor:<tag>#g" \
    deployment.yaml > deployment.rendered.yaml
kubectl apply -f configmap.yaml -f deployment.rendered.yaml -f service.yaml -f ingress.yaml
kubectl rollout status deployment/analytics-api -n analytics --timeout=300s
kubectl rollout status deployment/analytics-web -n analytics --timeout=300s
```

`product-deployment-pipeline/scripts/deploy.sh <environment> <action> [image_tag] [run_tests] [security_scan]`
wraps all of the above for a manual/break-glass deploy. `stage` and `prod`
applies ask you to type the environment name to confirm.

## CI deployment (Jenkins)

1. Trigger the pipeline with `ENVIRONMENT` = `dev` / `stage` / `prod`.
2. Stages run in order: `Initialize` → `IaC Scan (Checkov)` →
   `Dependency Scan (Snyk)` → `Build & Test` → `Image Scan (Trivy)` →
   `Push Images` → `Infrastructure Plan` → **Manual Approval (prod only)** →
   `Infrastructure Apply` → `Kubernetes Deploy` → `Smoke Tests` →
   `Monitoring Setup`. With `ACTION=plan`, everything after the plan is
   skipped, and so is `Push Images`.
3. Review the archived `tfplan.json` before approving a `prod` apply.
4. Results post to the Slack webhook in `slack-webhook-url`. A failed deploy or
   smoke test rolls back automatically (see `docs/incident-response.md`).

## Promoting a build between environments

The same image tag should move `dev → stage → prod` unchanged:

```bash
./product-deployment-pipeline/scripts/deploy.sh stage apply <tag-that-passed-dev> false true
./product-deployment-pipeline/scripts/deploy.sh prod  apply <tag-that-passed-stage> false true
```

`security_scan` stays `true` because scans can only be disabled for `dev`.

## Rolling back

```bash
./product-deployment-pipeline/scripts/rollback.sh <environment>
```

It prints the image before and after, so the restored version is visible in
the output.

## Destroying an environment

```bash
./product-deployment-pipeline/scripts/deploy.sh dev destroy
```

You must type the environment name to confirm. Destroy isn't offered in Jenkins.
Delete the Ingresses and PVCs first, or the controller-created ALBs and EBS
volumes will block the VPC destroy (see `EXECUTION.md` §6).

## Proof of execution

See `EXECUTION.md` for what has been run and `docs/evidence-checklist.md` for
what still has to be captured.
