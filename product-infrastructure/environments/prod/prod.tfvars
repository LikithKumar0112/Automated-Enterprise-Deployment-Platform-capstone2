# Usage: terraform workspace select prod && terraform apply -var-file=environments/prod/prod.tfvars
aws_region = "us-east-1"

vpc_cidr           = "10.30.0.0/16"
az_count           = 3
single_nat_gateway = false

k8s_version = "1.35"
eks_public_access_enabled = false
eks_public_access_cidrs   = []

node_groups = {
  general = {
    desired_size = 3
    max_size       = 10
    min_size       = 1
    instance_types = ["m7i-flex.large"]
    capacity_type  = "ON_DEMAND"
    labels         = {}
    taints         = []
  }
  spot = {
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
