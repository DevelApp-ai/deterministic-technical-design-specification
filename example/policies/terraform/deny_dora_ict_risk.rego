# policies/terraform/deny_dora_ict_risk.rego
#
# DORA-ICT-001 — EU DORA Chapter II: ICT Risk Management Controls
#
# EU Regulation 2022/2554 (DORA — Digital Operational Resilience Act) applies
# to financial entities from 17 January 2025.  Chapter II (Art.5-16) requires
# entities to establish and maintain a sound and comprehensive ICT risk
# management framework.
#
# This policy enforces three ICT risk-management controls that are NOT already
# covered by existing SEC- or NIS2-CRYPTO- policies:
#
#   Rule 1 — CloudTrail log-file validation (DORA Art.9 / Art.10)
#             aws_cloudtrail resources must enable log-file validation so that
#             CloudTrail log integrity can be verified after the fact.  Tampered
#             or deleted logs undermine audit evidence required by DORA.
#
#   Rule 2 — CloudWatch log group retention (DORA Art.10 / Art.15)
#             aws_cloudwatch_log_group resources must set an explicit retention
#             period (retention_in_days > 0).  Setting 0 means indefinite
#             retention with no lifecycle governance, which prevents systematic
#             log management required by DORA Art.10.
#
#   Rule 3 — S3 bucket versioning enabled (DORA Art.12)
#             aws_s3_bucket_versioning resources must have status = "Enabled".
#             Versioning is the minimum prerequisite for a DORA-compliant backup
#             and point-in-time-recovery policy.
#
# Related ADR:          docs/adrs/0011-dora-compliance.md
# Related requirements: DORA-002, DORA-003, M-003, S-001
# DORA:                 Art.9 (ICT security), Art.10 (Logging), Art.12 (Backup)
# NIST 800-53:          AU-2, AU-9, CP-9, SI-12
# SOC 2 CC:             CC7.2, A1.2

package terraform.dora

import rego.v1

__rego__metadoc__ := {
	"id":          "DORA-ICT-001",
	"title":       "DORA Chapter II — ICT Risk Management: Logging, Retention, and Backup",
	"description": "CloudTrail must enable log-file validation, CloudWatch log groups must define a retention period, and S3 bucket versioning must be enabled — as required by DORA Articles 9, 10, and 12 for ICT risk management and backup policies.",
	"severity":    "HIGH",
	"remediation": "1) Set enable_log_file_validation = true on aws_cloudtrail. 2) Set retention_in_days > 0 on aws_cloudwatch_log_group. 3) Set versioning_configuration { status = \"Enabled\" } on aws_s3_bucket_versioning.",
	"related_adr":          ["ADR-0011", "ADR-0002"],
	"related_requirements": ["DORA-002", "DORA-003", "M-003", "S-001"],
	"compliance": {
		"dora":       ["Art.9", "Art.10", "Art.12"],
		"nist_800_53": ["AU-2", "AU-9", "CP-9", "SI-12"],
		"soc2_cc":    ["CC7.2", "A1.2"],
	},
}

# ---------------------------------------------------------------------------
# Rule 1 — CloudTrail log-file validation must be enabled
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_cloudtrail"
	object.get(resource.values, "enable_log_file_validation", false) != true
	msg := sprintf(
		"[DORA-ICT-001] CloudTrail trail '%s' does not have log-file validation enabled. Set enable_log_file_validation = true to satisfy DORA Art.9/10 audit-log integrity requirements.",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 2 — CloudWatch log group must have an explicit retention period
#           retention_in_days = 0 means indefinite (no lifecycle governance)
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_cloudwatch_log_group"
	retention := object.get(resource.values, "retention_in_days", 0)
	retention == 0
	msg := sprintf(
		"[DORA-ICT-001] CloudWatch log group '%s' has no retention period (retention_in_days = 0 or absent). Set a positive retention_in_days value to satisfy DORA Art.10/15 log lifecycle requirements.",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 3 — S3 bucket versioning must be enabled
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket_versioning"
	status := object.get(
		object.get(resource.values, "versioning_configuration", [{}])[0],
		"status", "Disabled",
	)
	status != "Enabled"
	msg := sprintf(
		"[DORA-ICT-001] S3 bucket versioning resource '%s' does not have versioning enabled. Set versioning_configuration { status = \"Enabled\" } to satisfy DORA Art.12 backup policy requirements.",
		[resource.address],
	)
}
