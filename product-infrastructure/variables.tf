variable "image_tag" {
  description = "Docker image tag being deployed (passed through from CI for traceability; not consumed by Terraform resources directly)"
  type        = string
  default     = "latest"
}

variable "aws_region" {
  description = "AWS region for this workspace/environment"
  type        = string
  default     = "us-east-1"
}

variable "jenkins_role_arn" {
  description = "ARN of the IAM principal Jenkins authenticates as"
  type        = string
}

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook for CloudWatch alarm notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR block for this environment's VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to span"
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ"
  type        = bool
  default     = false
}

variable "k8s_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.27"
}

variable "eks_public_access_enabled" {
  description = "Whether the EKS API server is reachable from outside the VPC"
  type        = bool
  default     = false
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint, if enabled"
  type        = list(string)
  default     = []
}

variable "node_groups" {
  description = "Managed node group configuration for this environment"
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

variable "waf_rate_limit" {
  description = "Max requests per 5-minute window per source IP before WAF blocks it"
  type        = number
  default     = 2000
}
