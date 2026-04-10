# policies/terraform/deny_public_access.rego
#
# SEC-002 — Deny Publicly Exposed Resources
#
# Terraform resources must not be configured to expose themselves to the
# public internet unless an explicit exception has been approved.
#
# Covered resource patterns (evaluated against terraform plan JSON):
#   - AWS S3 buckets with `acl = "public-read"` or `"public-read-write"`
#   - AWS Security Group rules with unrestricted ingress (0.0.0.0/0 or ::/0)
#     on sensitive ports (22/SSH, 3389/RDP, 5432/PostgreSQL, 1433/MSSQL)
#   - Azure Storage accounts with `allow_blob_public_access = true`
#
# Related ADR:          docs/adrs/0002-use-opa-for-policy.md
# Related requirements: M-003, S-001, CYB-002
# CIS Benchmark:        AWS CIS 2.1.2 (S3 no public ACL), 5.2 (SG no SSH 0.0.0.0/0)
# NIST 800-53:          AC-3, SC-7
# SOC 2 CC:             CC6.1, CC6.6

package terraform.security

import rego.v1

# Sensitive ports that must never be open to the internet
_sensitive_ports := {22, 3389, 5432, 1433, 27017}

# CIDR ranges that represent the entire internet
_public_cidrs := {"0.0.0.0/0", "::/0"}

# ---------------------------------------------------------------------------
# Self-describing metadata (machine-readable by traceability tooling)
# ---------------------------------------------------------------------------
__rego__metadoc__ := {
	"id":          "SEC-002",
	"title":       "Deny Publicly Exposed Resources",
	"description": "Terraform resources must not expose services to the public internet without an approved exception.",
	"severity":    "CRITICAL",
	"remediation": "Remove public ACLs, restrict security group CIDR ranges, and disable public blob access.",
	"related_adr":          ["ADR-0002"],
	"related_requirements": ["M-003", "S-001", "CYB-002"],
	"compliance": {
		"cis_aws":     ["2.1.2", "5.2"],
		"nist_800_53": ["AC-3", "SC-7"],
		"soc2_cc":     ["CC6.1", "CC6.6"],
	},
}

# ---------------------------------------------------------------------------
# Rule 1 — AWS S3 bucket public ACL
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket"
	resource.values.acl in {"public-read", "public-read-write"}
	msg := sprintf(
		"[SEC-002] S3 bucket '%s' has a public ACL ('%s'). Remove the public ACL to prevent internet exposure. (CIS AWS 2.1.2)",
		[resource.address, resource.values.acl],
	)
}

# ---------------------------------------------------------------------------
# Rule 2 — AWS Security Group unrestricted ingress on sensitive ports
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_security_group"
	rule := resource.values.ingress[_]
	rule.cidr_blocks[_] in _public_cidrs
	port := _sensitive_ports[_]
	rule.from_port <= port
	rule.to_port >= port
	msg := sprintf(
		"[SEC-002] Security group '%s' allows unrestricted internet ingress (0.0.0.0/0) on sensitive port %d. Restrict to known CIDR ranges. (CIS AWS 5.2)",
		[resource.address, port],
	)
}

# ---------------------------------------------------------------------------
# Rule 3 — Azure Storage Account public blob access
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "azurerm_storage_account"
	resource.values.allow_blob_public_access == true
	msg := sprintf(
		"[SEC-002] Azure Storage Account '%s' has public blob access enabled. Set allow_blob_public_access = false. (CIS Azure 3.7)",
		[resource.address],
	)
}

