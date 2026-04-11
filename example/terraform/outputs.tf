# outputs.tf — Output value definitions.
# terraform-docs reads these to generate the "Outputs" table in README.md.

output "app_config_path" {
  description = "Filesystem path to the generated application configuration file."
  value       = local_file.app_config.filename
}

output "manifest_path" {
  description = "Filesystem path to the generated deployment manifest."
  value       = local_file.deployment_manifest.filename
}

output "tags" {
  description = "Map of cost-allocation tags applied to every resource in this module."
  value       = local.common_tags
}

output "network_topology_path" {
  description = "Filesystem path to the generated network topology JSON manifest."
  value       = local_file.network_topology.filename
}

output "network_security_rules_path" {
  description = "Filesystem path to the generated network security group rules JSON manifest."
  value       = local_file.network_security_rules.filename
}

output "dns_records_path" {
  description = "Filesystem path to the generated DNS records JSON manifest."
  value       = local_file.dns_records.filename
}

output "vpc_cidr" {
  description = "CIDR block of the virtual network."
  value       = var.vpc_cidr
}

output "private_subnets" {
  description = "Map of private subnet names to their CIDR blocks and metadata."
  value       = local.private_subnet_map
}

output "public_subnets" {
  description = "Map of public subnet names to their CIDR blocks and metadata."
  value       = local.public_subnet_map
}

output "iam_app_role_path" {
  description = "Filesystem path to the generated IAM application role JSON manifest."
  value       = local_file.iam_app_role.filename
}

output "iam_cicd_role_path" {
  description = "Filesystem path to the generated IAM CI/CD role JSON manifest."
  value       = local_file.iam_cicd_role.filename
}

output "storage_primary_bucket_name" {
  description = "Name of the primary application data S3 bucket."
  value       = local.primary_bucket_name
}

output "storage_logs_bucket_name" {
  description = "Name of the S3 access-logs bucket."
  value       = local.logs_bucket_name
}

output "monitoring_alarms_path" {
  description = "Filesystem path to the generated CloudWatch alarms JSON manifest."
  value       = local_file.monitoring_alarms.filename
}

output "monitoring_dashboard_path" {
  description = "Filesystem path to the generated operations dashboard JSON manifest."
  value       = local_file.monitoring_dashboard.filename
}

output "kms_key_path" {
  description = "Filesystem path to the generated KMS key JSON manifest."
  value       = local_file.kms_key.filename
}

output "kms_key_alias" {
  description = "KMS key alias used for encryption across all resources in this module."
  value       = local.kms_key_alias
}

output "ssm_parameters_path" {
  description = "Filesystem path to the generated SSM Parameter Store JSON manifest."
  value       = local_file.ssm_parameters.filename
}

output "secrets_manager_path" {
  description = "Filesystem path to the generated Secrets Manager JSON manifest."
  value       = local_file.secrets_manager.filename
}

output "launch_template_path" {
  description = "Filesystem path to the generated EC2 launch template JSON manifest."
  value       = local_file.launch_template.filename
}

output "auto_scaling_group_path" {
  description = "Filesystem path to the generated Auto Scaling group JSON manifest."
  value       = local_file.auto_scaling_group.filename
}

output "cloudtrail_path" {
  description = "Filesystem path to the generated CloudTrail JSON manifest."
  value       = local_file.cloudtrail.filename
}

output "cloudwatch_log_groups_path" {
  description = "Filesystem path to the generated CloudWatch log groups JSON manifest."
  value       = local_file.cloudwatch_log_groups.filename
}

output "cloudwatch_retention_days" {
  description = "Effective CloudWatch log group retention period in days."
  value       = local.effective_retention_days
}

output "waf_web_acl_path" {
  description = "Filesystem path to the generated WAF Web ACL JSON manifest."
  value       = local_file.waf_web_acl.filename
}

output "waf_rate_limit" {
  description = "Maximum requests per 5-minute window per IP before WAF blocks the source."
  value       = local.waf_rate_limit
}

output "backup_vault_primary_path" {
  description = "Filesystem path to the generated primary backup vault JSON manifest."
  value       = local_file.backup_vault_primary.filename
}

output "backup_vault_dr_path" {
  description = "Filesystem path to the generated DR backup vault JSON manifest."
  value       = local_file.backup_vault_dr.filename
}

output "backup_rto_hours" {
  description = "Documented RTO target in hours (DORA Art.12)."
  value       = local.dora_rto_hours
}

output "backup_rpo_hours" {
  description = "Documented RPO target in hours (DORA Art.12)."
  value       = local.dora_rpo_hours
}
