# Jenkins Shared Library

Reusable pipeline steps referenced from `product-deployment-pipeline/Jenkinsfile`.
Load it in Jenkins under **Manage Jenkins > System > Global Pipeline
Libraries** pointing at this directory, then call the functions in `vars/`
as top-level pipeline steps, e.g. `runSecurityScan(image: '...')`.

- `vars/deployToKubernetes.groovy` - the sed + kubectl apply + rollout-wait
  sequence used for the flat `product-kubernetes/` manifests, in one place
  so the Jenkinsfile and `scripts/deploy.sh` don't drift apart.
- `vars/runSecurityScan.groovy` - Trivy + Checkov wrapper with a consistent
  severity threshold across pipelines.
- `vars/notifySlack.groovy` - standard success/failure Slack message format.
