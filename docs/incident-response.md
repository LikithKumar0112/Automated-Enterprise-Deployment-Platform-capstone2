# Incident Response

## Recovery objectives (per the capstone brief, Section 7)

| Metric | Target |
|---|---|
| RTO (Recovery Time Objective) | 4 hours |
| RPO (Recovery Point Objective) | 24 hours |
| Rollback time | < 15 minutes |

## Severity levels

| Level | Definition | Response |
|---|---|---|
| SEV1 | Prod fully down / data loss risk | Page on-call immediately |
| SEV2 | Prod degraded, no full outage | On-call investigates within 15 min |
| SEV3 | Non-prod issue, or prod issue with a workaround | Fix during business hours |

## The 10 failure scenarios (capstone Section 6)

For each, the brief asks you to: **cause a controlled failure → diagnose
→ fix and validate**, and produce logs, a root-cause write-up, resolution
steps, and a prevention strategy. What follows is the starting-point
guidance for each — the actual logs/RCA are yours to produce by running
the scenario.

### 1. Terraform state corruption
```bash
terraform force-unlock <lock-id>          # stale lock from a crashed run
terraform plan                             # review drift before applying
terraform import <resource.address> <id>   # resource exists but isn't tracked
```
State is versioned in S3, so a bad apply is recoverable via the previous
object version.

### 2. Docker registry (ECR) outage
Confirm via AWS Health Dashboard. Running pods are unaffected (no re-pull
unless a pod restarts) — this blocks new deploys, it isn't a live outage
by itself. Retry once ECR recovers.

### 3. EKS control plane outage
`kubectl` times out; already-scheduled workloads keep serving traffic
(the control plane isn't in the data path). Don't `terraform apply` during
the outage — wait for AWS to restore the endpoint.

### 4. Jenkins failure
Check the failed stage's logs. If `Infrastructure Apply` fails partway,
re-run `terraform plan` before retrying `apply` — a partial apply can
leave dependent resources inconsistent.

### 5. Maven dependency failure
Usually a repository/proxy outage or a version pin that no longer
resolves. Check `mvn dependency:tree` locally against the same settings.xml
the pipeline uses; pin the offending dependency if it's an upstream break.

### 6. Kubernetes node failure
The managed node group's ASG replaces unhealthy nodes automatically
(`kubectl get nodes`, `aws eks describe-nodegroup`). `podAntiAffinity` on
`analytics-api`/`analytics-web` (`product-kubernetes/deployment.yaml`)
spreads replicas across nodes so one node failure shouldn't fully outage a
service with replicas >= 2.

### 7. AWS region outage
Out of scope for automated failover in this repo (single-region design,
per `docs/cost-optimization.md`). Recovery is: wait for AWS, or manually
re-point DNS at a pre-provisioned DR region if one exists — documenting
that decision is part of this exercise.

### 8. Git repository corruption
```bash
git fsck --full
git reflog                 # find the last good commit
git reset --hard <good-sha>
```
Push to a new remote/branch and re-point CI if the corruption is on the
hosting side rather than local.

### 9. Certificate expiration
`aws acm describe-certificate --certificate-arn <arn>` to check status.
ACM DNS-validated certs auto-renew; expiration usually means the
validation CNAME was removed. Update the `alb.ingress.kubernetes.io/certificate-arn`
annotation in `product-kubernetes/ingress.yaml` if the ARN itself changed.

### 10. Configuration drift
```bash
terraform plan                                 # Terraform-managed drift
kubectl diff -f product-kubernetes/deployment.yaml   # Kubernetes-managed drift
```
Investigate before applying — a manual console/kubectl change should
either be reverted or captured back into code, not silently overwritten.

## Rollback procedure (application)

```bash
./product-deployment-pipeline/scripts/rollback.sh <environment>
```
Also triggered automatically by the Jenkinsfile's `post { failure { ... } }`
block for `prod`. Target: complete within 15 minutes of detection.

## Post-incident

Every SEV1/SEV2 gets a written postmortem: timeline, root cause, what
caught it (or didn't), and follow-up action items with owners.
