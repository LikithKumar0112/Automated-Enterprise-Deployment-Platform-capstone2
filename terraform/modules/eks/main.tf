# EKS Cluster Module
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.11"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.6"
    }
  }
}

# EKS Cluster
resource "aws_eks_cluster" "analytics_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.k8s_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.public_access_enabled
    public_access_cidrs     = var.public_access_cidrs
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_encryption.arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(var.tags, {
    Name = var.cluster_name
  })
}

# Node Groups
resource "aws_eks_node_group" "analytics_nodes" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.analytics_cluster.name
  node_group_name = "${var.cluster_name}-${each.key}"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  instance_types = each.value.instance_types

  capacity_type = each.value.capacity_type

  labels = merge(each.value.labels, {
    component = each.key
  })

  taint = each.value.taints

  update_config {
    max_unavailable_percentage = 33
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${each.key}"
  })
}

# IAM Roles
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# KMS for encryption
resource "aws_kms_key" "eks_encryption" {
  description             = "EKS Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = var.tags
}

# Outputs
output "cluster_id" {
  value = aws_eks_cluster.analytics_cluster.id
}

output "cluster_endpoint" {
  value = aws_eks_cluster.analytics_cluster.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.analytics_cluster.certificate_authority[0].data
}

output "node_group_arns" {
  value = { for k, v in aws_eks_node_group.analytics_nodes : k => v.arn }
}
