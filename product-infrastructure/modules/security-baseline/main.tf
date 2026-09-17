# Security Baseline Module
# Secrets management, CI deploy-role IAM, and WAF in front of the ALB Ingress
# defined in product-kubernetes/ingress.yaml.
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

resource "aws_kms_key" "secrets" {
  description             = "Secrets encryption key for ${var.name_prefix}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  # no explicit "tags" here - identical to the provider's default_tags
  # block, and recent AWS provider versions reject that as redundant.
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Application secrets - populated out-of-band (Vault sync or manual);
# Terraform only owns the container/metadata, never the secret_string.
# product-kubernetes/secrets.yaml documents the expected shape for these.
resource "aws_secretsmanager_secret" "app" {
  for_each   = toset(var.secret_names)
  name       = "${var.name_prefix}/${each.key}"
  kms_key_id = aws_kms_key.secrets.arn
  # Secrets Manager soft-deletes by default (~30-day recovery window) -
  # `terraform destroy` then `apply` again with the same name (this repo's
  # actual workflow, given the account's shared vCPU quota forces frequent
  # destroy/recreate cycles between environments) fails with "already
  # scheduled for deletion" otherwise. Immediate delete, no recovery window.
  recovery_window_in_days = 0
  # no explicit "tags" here - see the note on aws_kms_key.secrets above.
}

# IAM role assumed by Jenkins (product-deployment-pipeline/Jenkinsfile
# "Initialize" stage pulls short-lived AWS creds from Vault, not static keys)
resource "aws_iam_role" "ci_deploy" {
  name = "${var.name_prefix}-ci-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = var.jenkins_role_arn }
      Condition = { StringEquals = { "sts:ExternalId" = var.name_prefix } }
    }]
  })
  # no explicit "tags" here - see the note on aws_kms_key.secrets above.
}

resource "aws_iam_role_policy" "ci_deploy" {
  name = "${var.name_prefix}-ci-deploy-policy"
  role = aws_iam_role.ci_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EKSAccess"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters"]
        Resource = "arn:aws:eks:*:*:cluster/${var.name_prefix}*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:GetAuthorizationToken",
        ]
        Resource = "*"
      },
      {
        Sid      = "SecretsRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [for s in aws_secretsmanager_secret.app : s.arn]
      },
      {
        Sid      = "TerraformState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [var.tf_state_bucket_arn, "${var.tf_state_bucket_arn}/*"]
      },
      {
        Sid      = "TerraformLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = var.tf_lock_table_arn
      },
    ]
  })
}

resource "aws_wafv2_web_acl" "alb" {
  name        = "${var.name_prefix}-alb-waf"
  description = "Baseline managed-rule protection for the product ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimit"
    priority = 2
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-waf"
    sampled_requests_enabled   = true
  }
  # no explicit "tags" here - see the note on aws_kms_key.secrets above.
}
