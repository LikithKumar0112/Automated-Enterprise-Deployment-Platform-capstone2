output "environment" {
  value = local.environment
}

output "cluster_name" {
  value = module.eks_cluster.cluster_id
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc_networking.vpc_id
}

output "alerts_topic_arn" {
  value = module.monitoring_stack.alerts_topic_arn
}
