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
