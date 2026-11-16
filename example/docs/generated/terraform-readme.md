<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [local_file.app_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.auto_scaling_group](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.backup_compliance_report](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.backup_plan_daily](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.backup_plan_monthly](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.backup_plan_weekly](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.backup_selection](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.backup_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.backup_vault_dr](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.backup_vault_primary](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.cloudtrail](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.cloudtrail_s3_bucket](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.cloudwatch_log_groups](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.compute_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.db_parameter_group](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.db_security_group](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.db_subnet_group](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.deployment_manifest](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.dns_records](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.iam_app_policy](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.iam_app_role](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.iam_cicd_role](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.iam_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.kms_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.kms_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.launch_template](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.logging_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.monitoring_alarms](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.monitoring_dashboard](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.monitoring_log_groups](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.monitoring_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.network_security_rules](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.network_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.network_topology](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.rds_alarms](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.rds_instance](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.rds_read_replica](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.rds_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.secrets_manager](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.security_alarms](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.security_group_app](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.ssm_parameters](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.storage_backup_bucket](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.storage_logs_bucket](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.storage_primary_bucket](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.storage_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.waf_admin_ip_set](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.waf_summary_md](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.waf_web_acl](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | Amazon Machine Image ID for the application tier (pin to a hardened AMI in production). | `string` | `"ami-0123456789abcdef0"` | no |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Name of the application being deployed. | `string` | n/a | yes |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones to spread subnets across. | `list(string)` | <pre>[<br/>  "az-1",<br/>  "az-2"<br/>]</pre> | no |
| <a name="input_cloudwatch_retention_days"></a> [cloudwatch\_retention\_days](#input\_cloudwatch\_retention\_days) | CloudWatch log group retention in days. Must be > 0 (DORA-ICT-001 requirement). | `number` | `90` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | Financial cost-center code used for FinOps reporting (FinOps cost-allocation tag). | `string` | n/a | yes |
| <a name="input_desired_capacity"></a> [desired\_capacity](#input\_desired\_capacity) | Desired number of instances in the Auto Scaling group at steady state. | `number` | `2` | no |
| <a name="input_dns_zone"></a> [dns\_zone](#input\_dns\_zone) | Internal DNS zone name used for service discovery records. | `string` | `"internal.example.com"` | no |
| <a name="input_enable_backups"></a> [enable\_backups](#input\_enable\_backups) | Whether to enable automated backups for the application data volume. | `bool` | `true` | no |
| <a name="input_enable_cloudtrail"></a> [enable\_cloudtrail](#input\_enable\_cloudtrail) | Enable CloudTrail with log file validation (DORA Art.9/10 requirement). | `bool` | `true` | no |
| <a name="input_enable_dns_support"></a> [enable\_dns\_support](#input\_enable\_dns\_support) | Enable DNS resolution and DNS hostnames for the virtual network. | `bool` | `true` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | When true, provision a NAT gateway in each public subnet so private subnets can reach the internet for egress. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (dev \| staging \| prod). | `string` | `"dev"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for application tier launch template. | `string` | `"t3.medium"` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | Maximum number of instances in the Auto Scaling group. | `number` | `4` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | Minimum number of instances in the Auto Scaling group. | `number` | `1` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Team or individual responsible for this resource (FinOps cost-allocation tag). | `string` | n/a | yes |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | List of CIDR blocks for private subnets (no direct internet route; egress via NAT gateway). | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | List of CIDR blocks for public subnets (internet-gateway attached; hosts load balancers and NAT gateways only). | `list(string)` | <pre>[<br/>  "10.0.10.0/24",<br/>  "10.0.11.0/24"<br/>]</pre> | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of application replicas to provision. | `number` | `1` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | Primary CIDR block for the virtual network / VPC. | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_config_path"></a> [app\_config\_path](#output\_app\_config\_path) | Filesystem path to the generated application configuration file. |
| <a name="output_auto_scaling_group_path"></a> [auto\_scaling\_group\_path](#output\_auto\_scaling\_group\_path) | Filesystem path to the generated Auto Scaling group JSON manifest. |
| <a name="output_backup_rpo_hours"></a> [backup\_rpo\_hours](#output\_backup\_rpo\_hours) | Documented RPO target in hours (DORA Art.12). |
| <a name="output_backup_rto_hours"></a> [backup\_rto\_hours](#output\_backup\_rto\_hours) | Documented RTO target in hours (DORA Art.12). |
| <a name="output_backup_vault_dr_path"></a> [backup\_vault\_dr\_path](#output\_backup\_vault\_dr\_path) | Filesystem path to the generated DR backup vault JSON manifest. |
| <a name="output_backup_vault_primary_path"></a> [backup\_vault\_primary\_path](#output\_backup\_vault\_primary\_path) | Filesystem path to the generated primary backup vault JSON manifest. |
| <a name="output_cloudtrail_path"></a> [cloudtrail\_path](#output\_cloudtrail\_path) | Filesystem path to the generated CloudTrail JSON manifest. |
| <a name="output_cloudwatch_log_groups_path"></a> [cloudwatch\_log\_groups\_path](#output\_cloudwatch\_log\_groups\_path) | Filesystem path to the generated CloudWatch log groups JSON manifest. |
| <a name="output_cloudwatch_retention_days"></a> [cloudwatch\_retention\_days](#output\_cloudwatch\_retention\_days) | Effective CloudWatch log group retention period in days. |
| <a name="output_dns_records_path"></a> [dns\_records\_path](#output\_dns\_records\_path) | Filesystem path to the generated DNS records JSON manifest. |
| <a name="output_iam_app_role_path"></a> [iam\_app\_role\_path](#output\_iam\_app\_role\_path) | Filesystem path to the generated IAM application role JSON manifest. |
| <a name="output_iam_cicd_role_path"></a> [iam\_cicd\_role\_path](#output\_iam\_cicd\_role\_path) | Filesystem path to the generated IAM CI/CD role JSON manifest. |
| <a name="output_kms_key_alias"></a> [kms\_key\_alias](#output\_kms\_key\_alias) | KMS key alias used for encryption across all resources in this module. |
| <a name="output_kms_key_path"></a> [kms\_key\_path](#output\_kms\_key\_path) | Filesystem path to the generated KMS key JSON manifest. |
| <a name="output_launch_template_path"></a> [launch\_template\_path](#output\_launch\_template\_path) | Filesystem path to the generated EC2 launch template JSON manifest. |
| <a name="output_manifest_path"></a> [manifest\_path](#output\_manifest\_path) | Filesystem path to the generated deployment manifest. |
| <a name="output_monitoring_alarms_path"></a> [monitoring\_alarms\_path](#output\_monitoring\_alarms\_path) | Filesystem path to the generated CloudWatch alarms JSON manifest. |
| <a name="output_monitoring_dashboard_path"></a> [monitoring\_dashboard\_path](#output\_monitoring\_dashboard\_path) | Filesystem path to the generated operations dashboard JSON manifest. |
| <a name="output_network_security_rules_path"></a> [network\_security\_rules\_path](#output\_network\_security\_rules\_path) | Filesystem path to the generated network security group rules JSON manifest. |
| <a name="output_network_topology_path"></a> [network\_topology\_path](#output\_network\_topology\_path) | Filesystem path to the generated network topology JSON manifest. |
| <a name="output_private_subnets"></a> [private\_subnets](#output\_private\_subnets) | Map of private subnet names to their CIDR blocks and metadata. |
| <a name="output_public_subnets"></a> [public\_subnets](#output\_public\_subnets) | Map of public subnet names to their CIDR blocks and metadata. |
| <a name="output_secrets_manager_path"></a> [secrets\_manager\_path](#output\_secrets\_manager\_path) | Filesystem path to the generated Secrets Manager JSON manifest. |
| <a name="output_ssm_parameters_path"></a> [ssm\_parameters\_path](#output\_ssm\_parameters\_path) | Filesystem path to the generated SSM Parameter Store JSON manifest. |
| <a name="output_storage_logs_bucket_name"></a> [storage\_logs\_bucket\_name](#output\_storage\_logs\_bucket\_name) | Name of the S3 access-logs bucket. |
| <a name="output_storage_primary_bucket_name"></a> [storage\_primary\_bucket\_name](#output\_storage\_primary\_bucket\_name) | Name of the primary application data S3 bucket. |
| <a name="output_tags"></a> [tags](#output\_tags) | Map of cost-allocation tags applied to every resource in this module. |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | CIDR block of the virtual network. |
| <a name="output_waf_rate_limit"></a> [waf\_rate\_limit](#output\_waf\_rate\_limit) | Maximum requests per 5-minute window per IP before WAF blocks the source. |
| <a name="output_waf_web_acl_path"></a> [waf\_web\_acl\_path](#output\_waf\_web\_acl\_path) | Filesystem path to the generated WAF Web ACL JSON manifest. |
<!-- END_TF_DOCS -->