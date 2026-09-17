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
    # t3.medium is NOT free-tier-eligible on this account, and the block
    # applies to BOTH Spot and On-Demand launches alike (confirmed via ASG
    # scaling-activity errors on this exact node group, 2026-09-16 - Spot
    # failed first, then On-Demand failed with the identical message).
    # m7i-flex.large IS free-tier-eligible on this account (confirmed via
    # `aws ec2 describe-instance-types --filters Name=free-tier-eligible,
    # Values=true`) and is what this EC2 instance itself runs as - 2 vCPU,
    # 8GiB RAM, x86_64 (matches the AL2023_x86_64_STANDARD node AMI).
    instance_types = ["m7i-flex.large"]
    capacity_type  = "ON_DEMAND"
    labels         = {}
    taints         = []
  }
}

waf_rate_limit = 5000

# jenkins_role_arn / alert_email / slack_webhook_url are secrets - set via
# -var or TF_VAR_ environment variables in CI, never committed here.
