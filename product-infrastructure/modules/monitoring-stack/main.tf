# Monitoring Stack Module
# AWS-native alerting layer that complements the in-cluster EFK/Grafana stack
# deployed from monitoring/ (see product-deployment-pipeline/Jenkinsfile).
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "slack" {
  count     = var.slack_webhook_url == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  alarm_name          = "${var.name_prefix}-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Worker node CPU sustained above 80% for 15 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  dimensions          = { ClusterName = var.cluster_name }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "node_memory_high" {
  alarm_name          = "${var.name_prefix}-node-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Worker node memory sustained above 85% for 15 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  dimensions          = { ClusterName = var.cluster_name }
  tags                = var.tags
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [{
      type   = "metric"
      x      = 0
      y      = 0
      width  = 12
      height = 6
      properties = {
        title = "Node CPU / Memory"
        metrics = [
          ["ContainerInsights", "node_cpu_utilization", "ClusterName", var.cluster_name],
          ["ContainerInsights", "node_memory_utilization", "ClusterName", var.cluster_name],
        ]
        period = 300
        region = var.aws_region
      }
    }]
  })
}
