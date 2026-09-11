variable "name_prefix" {
  description = "Prefix applied to all named resources, e.g. analytics-dev"
  type        = string
}

variable "secret_names" {
  description = "Logical names of app secrets to provision containers for"
  type        = list(string)
  default     = ["db-credentials", "api-keys"]
}

variable "jenkins_role_arn" {
  description = "ARN of the IAM role/user Jenkins authenticates as before assuming ci_deploy"
  type        = string
}

variable "tf_state_bucket_arn" {
  description = "ARN of the S3 bucket holding Terraform state"
  type        = string
}

variable "tf_lock_table_arn" {
  description = "ARN of the DynamoDB table used for Terraform state locking"
  type        = string
}

variable "waf_rate_limit" {
  description = "Max requests per 5-minute window per source IP before WAF blocks it"
  type        = number
  default     = 2000
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
