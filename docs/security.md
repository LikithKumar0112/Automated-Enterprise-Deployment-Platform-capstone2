# Security Guide

## Principles

1. **No secrets in Git.** `product-kubernetes/secrets.yaml` is a
   reference only — real values come from AWS Secrets Manager at deploy
   time, through `scripts/sync-secrets.sh`.
2. **Least privilege, per environment (partly in place).** Terraform creates
   a `ci_deploy` role in `product-infrastructure/modules/security-baseline`,
   scoped to one workspace. The pipeline does not assume it yet; see Known gaps.
3. **Non-root containers.** All three targets in `product-docker/Dockerfile`
   (`api`, `webapp`, `data-processor`) run as a dedicated non-root UID/GID.
4. **Defense in depth at the edge (partly in place).** A WAFv2 web ACL is
   provisioned but not attached to the ALBs yet; see Known gaps.

## Pipeline security gates (capstone Task 5)

| Tool | Stage | Fails when | Effect |
|---|---|---|---|
| Checkov 3.3.19 | IaC Scan | A Terraform finding is not in `product-infrastructure/.checkov.baseline` | Nothing built, pushed, or applied |
| Snyk | Dependency Scan | A HIGH/CRITICAL dependency in `app/api` or `app/data-processor` | Nothing built, pushed, or applied |
| Trivy 0.69.3 | Image Scan | A fixable HIGH/CRITICAL vulnerability in any of the 3 images | Nothing pushed or applied |
| Semgrep (local `deploy.sh` only) | Before build | Any finding | Deploy stops |

`SECURITY_SCAN` can be disabled for `dev` only. The pipeline and `deploy.sh`
both refuse to run `stage` or `prod` without scans.

### Checkov baseline

The baseline records 22 existing findings so that new ones can block without
every run failing. They are accepted debt, not fixed: delete an entry once it's
fixed, and only regenerate the file after reviewing what is being added.

| Check | Finding | Resource |
|---|---|---|
| CKV_AWS_109, 111, 356 | Broad KMS key policy | `eks-cluster` KMS policy document |
| CKV_AWS_26 | SNS topic not encrypted | `monitoring-stack` alerts topic |
| CKV_AWS_158, 338 | Log groups lack KMS and 1-year retention | EKS control plane and flow logs |
| CKV_AWS_290, 355 | IAM write access / `*` resource | `ci_deploy`, flow log role |
| CKV2_AWS_64 | KMS key policy not defined | `security-baseline` secrets key |
| CKV2_AWS_57 | Automatic secret rotation off | `db-credentials`, `api-keys` |
| CKV2_AWS_31, CKV_AWS_192 | WAF logging and Log4j rule missing | WAF web ACL |
| CKV_AWS_130 | Public subnets assign public IPs | Public subnets (needed for ALBs and NAT) |
| CKV_AWS_394 | Availability zones not pinned | VPC module |
| CKV2_AWS_12 | Default security group not restricted | VPC |

## Secrets management (capstone Task 5)

- **Storage:** AWS Secrets Manager, one container per logical secret
  (`product-infrastructure/modules/security-baseline`'s `secret_names`),
  KMS-encrypted. Automatic rotation is not enabled yet; see Known gaps.
- **In-cluster shape:** `scripts/sync-secrets.sh` reads
  `analytics-<env>/db-credentials` (`DB_USERNAME`, `DB_PASSWORD`, `DB_URL`) and
  `analytics-<env>/api-keys` (`JWT_SIGNING_KEY`) and creates the `api-secrets`
  Secret. A missing value fails the deploy. `product-kubernetes/secrets.yaml`
  is a reference for the keys and is not applied.
- **CI access:** the pipeline uses the AWS credentials of the `jenkins` system
  user on the Jenkins host; see Known gaps. Jenkins credentials hold
  `snyk-api-token` and `slack-webhook-url`.

## Network security

- EKS API endpoint is private by default; only `dev` opens public access
  (`environments/dev/dev.tfvars`).
- VPC Flow Logs enabled on every workspace's VPC, shipped to CloudWatch.
- Default-deny `NetworkPolicy` resources for the `analytics` namespace are
  a known gap — see below.

## Data protection

- EKS secrets are envelope-encrypted with a dedicated KMS key
  (`modules/eks-cluster`), separate from the application-secrets KMS key
  (`modules/security-baseline`), so key access/rotation can be scoped and
  audited independently.
- The S3 Terraform state bucket has versioning enabled (see
  `docs/runbooks.md` bootstrap steps).

## Known gaps

- HTTP only: no domain or ACM certificate exists for this exercise.
- WAF web ACL is not attached to the ALBs.
- The pipeline does not assume the `ci_deploy` role, so the Jenkins host holds
  AWS credentials directly.
- Elasticsearch security is disabled and Kibana has no login, and Grafana uses
  the chart's default admin password. Reach these through `kubectl port-forward`
  on localhost only, never on a public IP.
- No default-deny `NetworkPolicy` resources in `product-kubernetes/`.
- No automated Secrets Manager rotation Lambda wired up.
- No image-signing/admission-control (e.g. Cosign + Kyverno).
