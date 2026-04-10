# policies/terraform/deny_public_iam.rego
#
# SEC-003 — Deny Overly Permissive IAM (Wildcard Principals / Actions)
#
# IAM policies that grant permissions to ALL principals ("*") or allow ALL
# actions ("*") on sensitive services create a broad blast radius for any
# credential compromise.  This policy enforces least-privilege.
#
# Covered patterns:
#   - AWS IAM role/policy with Principal = "*"
#   - AWS IAM role/policy with Action = "*" or "iam:*"
#   - AWS S3 bucket policy with Principal = "*" and Effect = "Allow"
#
# Related ADR:          docs/adrs/0002-use-opa-for-policy.md
# Related requirements: M-003, S-001, CYB-003
# CIS Benchmark:        AWS CIS 1.16 (no full admin policy), 1.22 (no * principal)
# NIST 800-53:          AC-2, AC-6, IA-2
# SOC 2 CC:             CC6.3

package terraform.iam

import future.keywords.in

# ---------------------------------------------------------------------------
# Self-describing metadata
# ---------------------------------------------------------------------------
__rego__metadoc__ := {
    "id":          "SEC-003",
    "title":       "Deny Overly Permissive IAM",
    "description": "IAM policies must not grant wildcard principals or actions on sensitive AWS services.",
    "severity":    "HIGH",
    "package":     "terraform.iam",
    "related_adr":          ["ADR-0002"],
    "related_requirements": ["M-003", "S-001", "CYB-003"],
    "compliance": {
        "cis_aws":    ["1.16", "1.22"],
        "nist_800_53": ["AC-2", "AC-6", "IA-2"],
        "soc2_cc":    ["CC6.3"],
    },
}

# IAM service prefixes whose wildcard actions are especially sensitive
_sensitive_iam_prefixes := {"iam", "kms", "secretsmanager", "sts", "organizations"}

# ---------------------------------------------------------------------------
# Helper: all planned resource changes
# ---------------------------------------------------------------------------
_planned_resources[resource] {
    resource := input.resource_changes[_]
    resource.change.actions[_] in {"create", "update"}
}

# ---------------------------------------------------------------------------
# Rule 1 — IAM role trust policy with wildcard principal
# ---------------------------------------------------------------------------
deny contains msg if {
    resource := _planned_resources[_]
    resource.type == "aws_iam_role"
    policy := json.unmarshal(resource.change.after.assume_role_policy)
    stmt := policy.Statement[_]
    stmt.Effect == "Allow"
    # Handle both string and array forms of Principal
    _principal_is_wildcard(stmt.Principal)
    msg := sprintf(
        "SEC-003 [%s]: IAM role '%s' has a wildcard principal ('*') in its trust policy. This allows any AWS entity to assume the role. (CIS AWS 1.22, NIST AC-6)",
        ["HIGH", resource.address],
    )
}

# ---------------------------------------------------------------------------
# Rule 2 — IAM policy document with wildcard action on sensitive services
# ---------------------------------------------------------------------------
deny contains msg if {
    resource := _planned_resources[_]
    resource.type in {"aws_iam_policy", "aws_iam_role_policy"}
    policy := json.unmarshal(resource.change.after.policy)
    stmt := policy.Statement[_]
    stmt.Effect == "Allow"
    action := _normalise_action(stmt.Action)
    _action_is_sensitive_wildcard(action)
    msg := sprintf(
        "SEC-003 [%s]: IAM policy '%s' grants wildcard action '%s' on a sensitive service. Use least-privilege action lists. (CIS AWS 1.16, NIST AC-6)",
        ["HIGH", resource.address, action],
    )
}

# ---------------------------------------------------------------------------
# Rule 3 — S3 bucket policy with wildcard principal + Allow
# ---------------------------------------------------------------------------
deny contains msg if {
    resource := _planned_resources[_]
    resource.type == "aws_s3_bucket_policy"
    policy := json.unmarshal(resource.change.after.policy)
    stmt := policy.Statement[_]
    stmt.Effect == "Allow"
    _principal_is_wildcard(stmt.Principal)
    msg := sprintf(
        "SEC-003 [%s]: S3 bucket policy '%s' allows ALL principals ('*'). This grants public read/write access to the bucket. (CIS AWS 1.22, NIST AC-3)",
        ["HIGH", resource.address],
    )
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Principal can be the string "*" or the object {"AWS": "*"}
_principal_is_wildcard(principal) if { principal == "*" }
_principal_is_wildcard(principal) if { principal.AWS == "*" }
_principal_is_wildcard(principal) if { principal.Service == "*" }

# Action can be a string or an array — normalise to a set
_normalise_action(action) := action if { is_string(action) }
_normalise_action(action) := action[_] if { is_array(action) }

# An action is a sensitive wildcard if it is bare "*" or "<prefix>:*" for a sensitive prefix
_action_is_sensitive_wildcard(action) if { action == "*" }
_action_is_sensitive_wildcard(action) if {
    parts := split(action, ":")
    count(parts) == 2
    parts[0] in _sensitive_iam_prefixes
    parts[1] == "*"
}
