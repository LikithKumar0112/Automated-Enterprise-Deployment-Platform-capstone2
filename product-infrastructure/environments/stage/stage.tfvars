# Usage: terraform workspace select stage && terraform apply -var-file=environments/stage/stage.tfvars
aws_region = "us-east-1"

vpc_cidr           = "10.20.0.0/16"
az_count           = 3
single_nat_gateway = true

k8s_version = "1.35" # 1.27 is no longer offered by EKS at all (checked
# 2026-09-16: aws eks describe-cluster-versions) -
# 1.34/1.35/1.36 are the current standard-support set
eks_public_access_enabled = false
eks_public_access_cidrs   = []

# Sized against this account's real EC2 quota (checked via
# `aws service-quotas get-service-quota`), not the reference m5.large x3-5
# figure documented in the manual: On-Demand Standard vCPU quota is 8, with
# ~2 already used by a running instance outside this project - leaving ~6
# vCPU of real headroom, shared across whatever environment is currently
# applied (dev/stage/prod all draw from the same account-wide quota, so
# destroy one before applying the next).
#
# Instance type m5.large is NOT free-tier-eligible on this account, and that
# block applies to BOTH Spot and On-Demand launches (confirmed on dev's node
# group, 2026-09-16 - m5/t3.medium failed identically under both capacity
# types). m7i-flex.large IS free-tier-eligible here (checked via
# `aws ec2 describe-instance-types --filters Name=free-tier-eligible,
# Values=true`) and is what this EC2 instance itself runs as.
node_groups = {
  general = {
    desired_size   = 2 # 2 x m7i-flex.large = 4 vCPU, leaving margin under the ~6 available
    max_size       = 5
    min_size       = 2
    instance_types = ["m7i-flex.large"]
    capacity_type  = "ON_DEMAND"
    labels         = {}
    taints         = []
  }
  spot = {
    # desired_size 0 - not just a quota issue: this account's Spot requests
    # are flatly rejected for any non-free-tier-eligible instance type,
    # regardless of quota headroom. 0 means EKS never attempts a launch, so
    # the node group still reaches ACTIVE cleanly - scales from zero for
    # batch load once this account's Spot restriction is lifted.
    desired_size   = 0
    max_size       = 6
    min_size       = 0
    instance_types = ["m7i-flex.large"]
    capacity_type  = "SPOT"
    labels         = { workload = "batch" }
    taints = [{
      key    = "spot"
      value  = "true"
      effect = "NO_SCHEDULE"
    }]
  }
}

waf_rate_limit = 3000
