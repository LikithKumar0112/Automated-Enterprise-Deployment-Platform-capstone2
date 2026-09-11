output "secrets_kms_key_arn" {
  value = aws_kms_key.secrets.arn
}

output "secret_arns" {
  value = { for k, v in aws_secretsmanager_secret.app : k => v.arn }
}

output "ci_deploy_role_arn" {
  value = aws_iam_role.ci_deploy.arn
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.alb.arn
}
