# Evidence Checklist

What still has to be captured on real infrastructure to close the review
feedback in [`feedback/project-feedback.pdf`](feedback/project-feedback.pdf).
The steps are in order, because some depend on earlier ones. Save images to
`docs/screenshots/` under the names shown, then add them to `EXECUTION.md`.

Keep the AWS spend short: do steps 4–12 in one sitting, then step 13.

## 1. Prepare

- [ ] Sign in to AWS as an IAM user or role, **not root**.
- [ ] Reach Grafana, Kibana, and Prometheus only through `kubectl port-forward`
      on `localhost`, not a public IP. Check that any public Jenkins URL is firewalled to your IP.
- [ ] On the Jenkins host: install `jq`, `helm`, JDK 17, and `snyk`.
- [ ] In Jenkins, add **Secret text** credentials `snyk-api-token` and `slack-webhook-url`.
- [ ] In Slack, create the webhook and channels `#monitoring-alerts`,
      `#operations-critical`, `#operations-warnings`.
- [ ] Create the ECR repositories (see `docs/runbooks.md`), and confirm the state bucket and lock table still exist.
- [ ] Point the Jenkins job at branch `submission-fixes`, Script Path `product-deployment-pipeline/Jenkinsfile`.

## 2. Security gates block (no cluster needed)

- [ ] The current code has the fix, so create a demo branch on the vulnerable version: `git branch gate-demo db24ded && git push origin gate-demo`. Use it for the Snyk and Trivy steps, and delete it afterwards.
- [ ] **Snyk blocks.** Run `dev` / `apply` on `gate-demo`. It should fail at `Dependency Scan` on
      Spring Boot 2.7.18, with Build, Push, and Deploy not run. Save `gate-snyk-blocked.png` (stage view) and `gate-snyk-blocked-log.png`.
- [ ] **Trivy blocks.** On the Jenkins host, with `gate-demo` checked out, from the repo root:
      ```bash
      (cd product-docker && ./build-scripts/stage-local-app.sh && docker build --target api -t analytics-api:scan .)
      product-deployment-pipeline/scripts/scan-image.sh analytics-api:scan; echo "exit=$?"
      ```
      Expect `exit=1`. Save `gate-trivy-blocked.png`.
- [ ] **Checkov blocks.** On a throwaway branch, add this to `product-infrastructure/main.tf` and run the job on that branch:
      ```hcl
      resource "aws_security_group" "demo_open_ssh" {
        ingress {
          from_port   = 22
          to_port     = 22
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
        }
      }
      ```
      It should fail at `IaC Scan`. Save `gate-checkov-blocked.png`, then delete the branch.

## 3. Fix the finding, then the gates pass

- [ ] Point the job back at `submission-fixes` (Spring Boot 4.1.2, Java 17) and run `dev` / `plan`. All scans should pass, with Push, Approval, Apply, Deploy, Smoke, and Monitoring skipped, and the log should say `Plan (nothing deployed)`.
      Save `gate-all-pass-dev-plan.png`. If a new CVE has been published since, it will block: that is the gate working, so update the dependency.

## 4. Deploy `dev`

- [ ] Run `dev` / `apply`. The **first** run should stop at `Kubernetes Deploy` with a missing-secret error,
      because Terraform has only just created the secret containers. This is expected.
- [ ] Set the secret values (see `docs/runbooks.md`) and re-run. Save `dev-apply-green.png` and `dev-smoke-tests-log.png`.
- [ ] Save `kubectl get pods,svc,ingress,rs -n analytics` as `dev-resources.png`.
- [ ] Investigate any Pending pod with `kubectl describe pod`. The earlier `data-processor` pod sat Pending for 82 minutes; if it recurs, set `desired_size = 3` in `dev.tfvars` (6 vCPU, within your quota).

## 5. Terraform evidence for all environments

- [ ] Run `stage` / `plan` and `prod` / `plan`. Save the `Plan: N to add` console lines as `tf-plan-stage.png` and `tf-plan-prod.png`, not just the stage view.
- [ ] Run `terraform validate` once in `product-infrastructure/` and save `tf-validate.png`.
- [ ] Update `EXECUTION.md` §5: it should report the plan totals you actually see.

## 6. Production approval gate

- [ ] Run `prod` / `apply`, wait at `Manual Approval`, save `prod-approval-gate.png`, then click **Abort**. Nothing reaches `Infrastructure Apply`.
- [ ] Run `prod` / `apply` with `SECURITY_SCAN` unticked. Save the refusal as `prod-scan-guard.png`.

## 7. Containers run

- [ ] On the Jenkins host, run the web and API images. Save `docker ps` showing `healthy` plus `curl` of `/health` and `/actuator/health` as `container-health.png`.

## 8. Failed deploy and automatic rollback

- [ ] Save `kubectl rollout history deployment/analytics-api -n analytics` and the current image as `rollback-before.png`.
- [ ] On a throwaway branch, change the API `readinessProbe` path in `product-kubernetes/deployment.yaml` to `/does-not-exist`, then run `dev` / `apply`.
- [ ] Expect a failure at `Kubernetes Deploy` after about 5 minutes, then `Images before rollback` / `Images after rollback` in the log.
      Save `rollback-auto-log.png` and `rollback-auto-stage-view.png`.
- [ ] Save the same `kubectl` output as `rollback-after.png`. The image must match `rollback-before.png`. Note the time taken for the `< 15 minutes` target.
- [ ] Delete the throwaway branch. This covers `dev`; state in `EXECUTION.md` that `prod` wasn't run because of the quota.

## 9. Alert reaches Slack

- [ ] Run `kubectl set image deployment/analytics-web web=nginx:does-not-exist -n analytics`.
- [ ] After about 10 minutes, `DeploymentStuck` should fire. Save `alert-firing-prometheus.png` and `alert-slack-firing.png`.
- [ ] Run `kubectl rollout undo deployment/analytics-web -n analytics`. Save `alert-slack-resolved.png`.

## 10. Monitoring and logging

- [ ] Save fresh Grafana and Prometheus target screenshots with real traffic as `grafana-app-metrics-v2.png` and `prometheus-targets-v2.png`.
- [ ] In Kibana, filter on `kubernetes.container_name: api` and save `kibana-api-logs.png`. Earlier screenshots show only web logs.
- [ ] Run `GET _cat/indices/fluentd*?v` twice, 10 minutes apart. Save both as `fluentd-index-growth.png`.

## 11. Terraform state recovery

- [ ] In the `dev` workspace, with a stopwatch running:
      ```bash
      terraform state pull > backup.tfstate
      terraform state rm module.monitoring_stack.aws_sns_topic.alerts
      terraform plan -var-file=environments/dev/dev.tfvars    # shows it would be recreated
      terraform state push -force backup.tfstate
      terraform plan -var-file=environments/dev/dev.tfvars    # shows no changes for it
      aws s3api list-object-versions --bucket analytics-tf-state-<account-id> --prefix env:/dev/ --max-items 5
      ```
      Save `tf-state-recovery.png`. Do not commit `backup.tfstate`.

## 12. RTO and RPO

- [ ] Record real timings in `docs/incident-response.md`: rollback from step 8, plus a full rebuild time from step 13.
- [ ] Be explicit about RPO: this project has no database, so the only data with a recovery point is Terraform state (S3 versioning) and logs and metrics, which are rebuilt rather than restored.

## 13. Tear down and rebuild timing

- [ ] Delete the controller-created resources first: `kubectl delete ingress --all -n analytics` and `kubectl delete pvc --all -A`.
- [ ] Run `terraform destroy` and confirm in the AWS console that no ALBs, EBS volumes, or NAT gateways remain. Optionally, `time` a full re-apply first for the RTO figure.

## 14. Snyk report on the real code

- [ ] After `main` is updated, delete the four old Snyk projects (`docker/api/Dockerfile`, `docker/webapp/Dockerfile`, `kubernetes/base/api-deployment.yaml`, `terraform/modules/eks/main.tf`).
- [ ] Re-import the repo and save `snyk-report-real-code.png`. Replace `snyk-report-old-sample-files.png` in `EXECUTION.md`.

## 15. Clean-clone test (do this last)

- [ ] On a machine that has never had this repo:
      ```bash
      git clone https://github.com/LikithKumar0112/Automated-Enterprise-Deployment-Platform-capstone2.git
      cd Automated-Enterprise-Deployment-Platform-capstone2/product-infrastructure
      terraform init -backend=false && terraform validate
      cd ../product-docker && ./build-scripts/stage-local-app.sh && ./build-scripts/build-all.sh clean-clone
      ```
      Save `clean-clone.png`.
- [ ] Update `EXECUTION.md`: add the new screenshots and remove its "not yet re-run" note.

## How this maps to the feedback

| Feedback section | Steps |
|---|---|
| 1. Jenkins | 2, 3, 4, 8 |
| 2. Terraform | 4, 5 |
| 3. Docker | 2, 7 |
| 4. Kubernetes | 4, 8 |
| 5. Security | 1, 2, 3, 14 |
| 6. Monitoring | 9, 10 |
| 7. Rollback and DR | 6, 8, 11, 12 |
| 8. Completeness | 14, 15 |
