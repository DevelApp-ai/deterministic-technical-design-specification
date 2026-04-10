# policies/terraform/deny_public_iam.rego
#
# SEC-003 — Deny Overly Permissive IAM (Wildcard Principals / Actions)
#
# IAM policies that grant permissions to ALL principals ("*") or allow ALL
# actions ("*") on sensitive services create a broad blast radius for any
# credential compromise.  This policy enforces least-privilege.
#
# Covered patterns (evaluated against terraform plan JSON):
#   - AWS IAM role trust policy with Principal = "*"
#   - AWS IAM policy/role_policy with Action = "*" or "<sensitive_service>:*"
#   - AWS S3 bucket policy with Principal = "*" and Effect = "Allow"
#
# Related ADR:          docs/adrs/0002-use-opa-for-policy.md
# Related requirements: M-003, S-001, CYB-003
# CIS Benchmark:        AWS CIS 1.16 (no full admin policy), 1.22 (no * principal)
# NIST 800-53:          AC-2, AC-6, IA-2
# SOC 2 CC:             CC6.3

package terraform.iam

import rego.v1

# IAM service prefixes whose wildcard actions are especially dangerous
_sensitive_iam_prefixes := {"iam", "kms", "secretsmanager", "sts", "organizations"}

__rego__metadoc__ := {
	"id":          "SEC-003",
	"title":       "Deny Overly Permissive IAM",
	"description": "IAM policies must not grant wildcard principals or actions on sensitive AWS services.",
	"severity":    "HIGH",
	"remediation": "Replace '*' principals and actions with least-privilege scoped values.",
	"related_adr":          ["ADR-0002"],
	"related_requirements": ["M-003", "S-001", "CYB-003"],
	"compliance": {
		"nis2":        ["Art.21(2)(i)"],
		"dora":        ["Art.9"],
		"cis_aws":     ["1.16", "1.22"],
		"nist_800_53": ["AC-2", "AC-6", "IA-2"],
		"soc2_cc":     ["CC6.3"],
	},
}

# ---------------------------------------------------------------------------
# Rule 1 — IAM role trust policy with wildcard principal
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_iam_role"
	policy := json.unmarshal(resource.values.assume_role_policy)
	stmt := policy.Statement[_]
	stmt.Effect == "Allow"
	_principal_is_wildcard(stmt.Principal)
	msg := sprintf(
		"[SEC-003] IAM role '%s' has a wildcard principal ('*') in its trust policy. Restrict to specific AWS services or accounts. (CIS AWS 1.22)",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 2a — IAM policy with wildcard action (string form) on sensitive service
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type in {"aws_iam_policy", "aws_iam_role_policy"}
	policy := json.unmarshal(resource.values.policy)
	stmt := policy.Statement[_]
	stmt.Effect == "Allow"
	is_string(stmt.Action)
	_action_is_sensitive_wildcard(stmt.Action)
	msg := sprintf(
		"[SEC-003] IAM policy '%s' grants wildcard action '%s' on a sensitive service. Use least-privilege action lists. (CIS AWS 1.16)",
		[resource.address, stmt.Action],
	)
}

# ---------------------------------------------------------------------------
# Rule 2b — IAM policy with wildcard action (array form) on sensitive service
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type in {"aws_iam_policy", "aws_iam_role_policy"}
	policy := json.unmarshal(resource.values.policy)
	stmt := policy.Statement[_]
	stmt.Effect == "Allow"
	is_array(stmt.Action)
	action := stmt.Action[_]
	_action_is_sensitive_wildcard(action)
	msg := sprintf(
		"[SEC-003] IAM policy '%s' grants wildcard action '%s' on a sensitive service. Use least-privilege action lists. (CIS AWS 1.16)",
		[resource.address, action],
	)
}

# ---------------------------------------------------------------------------
# Rule 3 — S3 bucket policy with wildcard principal + Allow
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket_policy"
	policy := json.unmarshal(resource.values.policy)
	stmt := policy.Statement[_]
	stmt.Effect == "Allow"
	_principal_is_wildcard(stmt.Principal)
	msg := sprintf(
		"[SEC-003] S3 bucket policy '%s' grants Allow to all principals ('*'). Restrict to specific IAM principals. (CIS AWS 1.22)",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_principal_is_wildcard(principal) if { principal == "*" }
_principal_is_wildcard(principal) if { principal.AWS == "*" }
_principal_is_wildcard(principal) if { principal.Service == "*" }

_action_is_sensitive_wildcard(action) if { action == "*" }
_action_is_sensitive_wildcard(action) if {
	parts := split(action, ":")
	count(parts) == 2
	parts[0] in _sensitive_iam_prefixes
	parts[1] == "*"
}

