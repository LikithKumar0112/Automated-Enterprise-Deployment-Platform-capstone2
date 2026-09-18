# Usage: terraform workspace select dev && terraform apply -var-file=environments/dev/dev.tfvars
aws_region = "us-east-1"

vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true

k8s_version               = "1.35"
eks_public_access_enabled = true
eks_public_access_cidrs   = ["0.0.0.0/0"] # dev only - tighten for shared/stage use

node_groups = {
  general = {
    desired_size = 2
    max_size     = 3
    min_size     = 1
    instance_types = ["m7i-flex.large"]
    capacity_type  = "ON_DEMAND"
    labels         = {}
    taints         = []
  }
}

waf_rate_limit = 5000

# jenkins_role_arn / alert_email / slack_webhook_url are secrets - set via
# -var or TF_VAR_ environment variables in CI, never committed here.
