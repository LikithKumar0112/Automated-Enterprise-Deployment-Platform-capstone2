variable "name_prefix" {
  description = "Prefix applied to all named resources, e.g. analytics-dev"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name to scope alarms/log groups to"
  type        = string
}

variable "aws_region" {
  description = "AWS region, used in dashboard widget definitions"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address for SNS alarm notifications. Leave empty to skip."
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack incoming-webhook URL for SNS alarm notifications. Leave empty to skip."
  type        = string
  default     = ""
  sensitive   = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention for EKS control-plane logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
