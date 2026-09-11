variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.27"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (from the vpc-networking module)"
  type        = list(string)
}

variable "public_access_enabled" {
  description = "Whether the EKS API server endpoint is reachable from outside the VPC"
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint, if enabled"
  type        = list(string)
  default     = []
}

variable "node_groups" {
  description = "Map of managed node group configurations"
  type = map(object({
    desired_size   = number
    max_size       = number
    min_size       = number
    instance_types = list(string)
    capacity_type  = string
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
