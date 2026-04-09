# policies/terraform/deny_unencrypted_storage.rego
#
# Policy: storage resources must not be provisioned with encryption disabled.
# In the local-provider example this rule is satisfied by default; in a real
# AWS/Azure/GCP deployment it prevents unencrypted EBS volumes, S3 buckets,
# or storage accounts from reaching production.

package terraform.security

import rego.v1

__rego__metadoc__ := {
	"id": "SEC-001",
	"title": "Storage Encryption Required",
	"description": "All storage resources must have encryption enabled to protect data at rest and satisfy compliance frameworks such as CIS, SOC 2, and PCI-DSS.",
	"severity": "CRITICAL",
	"remediation": "Set `encrypted = true` (AWS EBS / RDS) or `enable_https_traffic_only = true` (Azure Storage) on the offending resource.",
}

# Deny AWS EBS volumes that have encryption explicitly disabled.
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_ebs_volume"
	resource.values.encrypted == false
	msg := sprintf(
		"[SEC-001] AWS EBS volume '%s' must have encryption enabled.",
		[resource.address],
	)
}

# Deny AWS S3 buckets that allow public ACLs.
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket_public_access_block"
	resource.values.block_public_acls == false
	msg := sprintf(
		"[SEC-001] S3 bucket public access block '%s' must set block_public_acls = true.",
		[resource.address],
	)
}
