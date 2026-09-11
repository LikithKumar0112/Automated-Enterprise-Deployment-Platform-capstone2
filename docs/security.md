# Security Guide

## Principles

1. **No secrets in Git.** `product-kubernetes/secrets.yaml` is a
   structural template only — real values come from AWS Secrets Manager /
   Vault at deploy time.
2. **Least privilege, per environment.** Jenkins assumes the
   `ci_deploy` role from `product-infrastructure/modules/security-baseline`,
   scoped to one workspace's EKS cluster, ECR, secrets, and Terraform state
   path — never a long-lived, cross-environment credential.
3. **Non-root containers.** All three targets in `product-docker/Dockerfile`
   (`api`, `webapp`, `data-processor`) run as a dedicated non-root UID/GID.
4. **Defense in depth at the edge.** WAFv2 (managed rule set + rate
   limiting) sits in front of the ALB defined in `product-kubernetes/ingress.yaml`.

## Pipeline security gates (capstone Task 5)

| Tool | Scope | Failure behavior |
|---|---|---|
| SonarQube | SAST on the Maven project | Blocks build |
| Trivy | Container image vulnerability scan (HIGH/CRITICAL) | Blocks push |
| Checkov | Terraform static analysis | Blocks apply |
| Semgrep (local `deploy.sh` path) | Additional SAST pass | Blocks build |

`SECURITY_SCAN` can be disabled per run for fast `dev` iteration, but
should never be turned off for `stage`/`prod`.

## Secrets management (capstone Task 5)

- **Storage:** AWS Secrets Manager, one container per logical secret
  (`product-infrastructure/modules/security-baseline`'s `secret_names`),
  KMS-encrypted with rotation enabled.
- **In-cluster shape:** `product-kubernetes/secrets.yaml` documents the
  expected keys (`api-secrets` → `DB_USERNAME`, `DB_PASSWORD`, `DB_URL`,
  `JWT_SIGNING_KEY`). Populate via Vault Agent injector or an External
  Secrets Operator `ExternalSecret` — not by hand-editing real values in.
- **CI access:** Jenkins pulls short-lived AWS credentials from Vault in
  the `Initialize` stage (`withVault(...)`), never a static IAM user key.
- **Proof of dynamic secret injection** (the capstone's expected outcome
  for this task) means capturing that a pod's env var resolved from a
  freshly-issued Vault/Secrets Manager value, not a value baked into the
  manifest — e.g. `kubectl exec` into the pod and show the secret came
  from the mounted/injected source, with the Vault lease ID or Secrets
  Manager version ID in the log.

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

## Known gaps (intentionally left for you to close as a learning exercise)

- No default-deny `NetworkPolicy` resources in `product-kubernetes/`.
- No automated Secrets Manager rotation Lambda wired up.
- No image-signing/admission-control (e.g. Cosign + Kyverno).
- `sonar.company.com`, `vault.company.com`, `monitoring.company.com` in
  the Jenkinsfile are illustrative hostnames — point them at your real
  infrastructure before running this for real.
