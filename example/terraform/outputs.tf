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
