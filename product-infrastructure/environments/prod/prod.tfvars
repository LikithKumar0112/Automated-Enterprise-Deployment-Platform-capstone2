# Usage: terraform workspace select prod && terraform apply -var-file=environments/prod/prod.tfvars
aws_region = "us-east-1"

vpc_cidr           = "10.30.0.0/16"
az_count           = 3
single_nat_gateway = false

k8s_version = "1.35" # see the note in environments/stage/stage.tfvars -
# 1.27 is no longer offered by EKS at all
eks_public_access_enabled = false
eks_public_access_cidrs   = []

# Sized against this account's real EC2 quota - see the note in
# environments/stage/stage.tfvars. m5.xlarge x4 (the reference figure the
# manual documents) is 16 vCPU on its own, against an ~6 vCPU real ceiling -
# not remotely applicable here. max_size is left at the documented
# reference ceiling (this account's quota, not this config, is what
# actually blocks scaling that high - request a quota increase via
# `aws service-quotas request-service-quota-increase` if you need it for real).
#
# Instance type m5.xlarge is NOT free-tier-eligible on this account (neither
# is m5.large), and that block applies to Spot AND On-Demand alike -
# m7i-flex.large IS free-tier-eligible here - see the note in
# environments/stage/stage.tfvars.
node_groups = {
  general = {
    desired_size = 3 # 3 x m7i-flex.large = 6 vCPU - uses the full ~6 vCPU headroom,
    # so only apply prod once dev/stage are destroyed
    max_size       = 10
    min_size       = 1
    instance_types = ["m7i-flex.large"] # scaled down from m5.xlarge - see note above
    capacity_type  = "ON_DEMAND"
    labels         = {}
    taints         = []
  }
  spot = {
    # desired_size 0 - see the note in environments/stage/stage.tfvars;
    # this account's Spot restriction applies regardless of instance size.
    desired_size   = 0
    max_size       = 15
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

waf_rate_limit = 2000
