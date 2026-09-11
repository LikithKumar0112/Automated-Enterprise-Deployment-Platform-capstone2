# Usage: terraform workspace select stage && terraform apply -var-file=environments/stage/stage.tfvars
aws_region = "us-east-1"

vpc_cidr           = "10.20.0.0/16"
az_count           = 3
single_nat_gateway = true

k8s_version               = "1.27"
eks_public_access_enabled = false
eks_public_access_cidrs   = []

node_groups = {
  general = {
    desired_size   = 3
    max_size       = 5
    min_size       = 2
    instance_types = ["m5.large"]
    capacity_type  = "ON_DEMAND"
    labels         = {}
    taints         = []
  }
  spot = {
    desired_size   = 2
    max_size       = 6
    min_size       = 0
    instance_types = ["m5.large", "m5a.large"]
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
