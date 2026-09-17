# Single remote backend, shared across all three Terraform workspaces
# (dev/stage/prod - see environments/*/*.tfvars and docs/runbooks.md).
# workspace_key_prefix means each `terraform workspace select <env>` gets
# its own state path automatically:
#   s3://<bucket>/env:/dev/product-infrastructure/terraform.tfstate
#   s3://<bucket>/env:/stage/product-infrastructure/terraform.tfstate
#   s3://<bucket>/env:/prod/product-infrastructure/terraform.tfstate
# bucket/region are supplied at `terraform init` time via -backend-config
# flags (see product-deployment-pipeline/scripts and Jenkinsfile), so this
# file has no hardcoded environment-specific values.
terraform {
  backend "s3" {
    key                  = "product-infrastructure/terraform.tfstate"
    workspace_key_prefix = "env"
    encrypt              = true
    dynamodb_table       = "analytics-tf-lock"
  }
}

