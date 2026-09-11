variable "name_prefix" {
  description = "Prefix applied to all named resources, e.g. analytics-dev"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name; used to tag subnets for the AWS load balancer/EBS controllers"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
