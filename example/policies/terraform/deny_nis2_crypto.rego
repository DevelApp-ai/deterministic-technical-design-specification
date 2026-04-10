# policies/terraform/deny_nis2_crypto.rego
#
# NIS2-CRYPTO-001 — NIS2 Article 21(2)(h): Cryptography and Key Management
#
# EU Directive 2022/2555 (NIS2), Article 21(2)(h) requires entities to adopt
# "policies and procedures regarding the use of cryptography and, where
# appropriate, encryption" including proper key management practices.
#
# This policy enforces the key-management and encryption obligations that are
# NOT already covered by SEC-001 (storage encryption) or SEC-006 (TLS version):
#
#   Rule 1 — AWS KMS keys must have automatic key rotation enabled.
#             Rotating encryption keys limits the blast radius of a key
#             compromise and satisfies the cryptographic lifecycle requirement.
#
#   Rule 2 — AWS RDS database instances must have storage encryption enabled.
#             Databases contain the most sensitive data; unencrypted databases
#             violate both NIS2 Art.21(2)(h) and GDPR Art.32.
#
#   Rule 3 — AWS SSM Parameter Store entries whose name suggests a secret
#             (password / secret / key / token / credential) must use
#             SecureString type, not plaintext String.
#
# Related ADR:          docs/adrs/0010-nis2-compliance.md
# Related requirements: NIS2-002, M-003, S-001
# NIS2:                 Art.21(2)(h) — Cryptography and encryption
# NIST 800-53:          SC-12 (Cryptographic Key Management), SC-28, SC-13
# SOC 2 CC:             CC6.1, CC6.7
# GDPR:                 Art.32 (Security of processing)

package terraform.nis2

import rego.v1

# Parameter name patterns that indicate the value is a secret
_secret_name_patterns := {"password", "secret", "token", "credential", "apikey", "api_key", "private_key"}

__rego__metadoc__ := {
	"id":          "NIS2-CRYPTO-001",
	"title":       "NIS2 Art.21(2)(h) — Cryptography and Key Management",
	"description": "AWS KMS keys must have key rotation enabled, AWS RDS instances must be encrypted at rest, and secret-like SSM parameters must use SecureString — as required by NIS2 Article 21(2)(h) on cryptography and encryption policies.",
	"severity":    "HIGH",
	"remediation": "1) Set enable_key_rotation = true on aws_kms_key resources. 2) Set storage_encrypted = true on aws_db_instance resources. 3) Use type = \"SecureString\" for SSM parameters that contain passwords, secrets, or tokens.",
	"related_adr":          ["ADR-0010", "ADR-0002"],
	"related_requirements": ["NIS2-002", "M-003", "S-001"],
	"compliance": {
		"nis2":        ["Art.21(2)(h)"],
		"dora":        ["Art.9"],
		"nist_800_53": ["SC-12", "SC-28", "SC-13"],
		"soc2_cc":     ["CC6.1", "CC6.7"],
		"gdpr":        ["Art.32"],
	},
}

# ---------------------------------------------------------------------------
# Rule 1 — AWS KMS key without automatic key rotation
#           Covers both explicit `enable_key_rotation = false` and absent attribute
#           (AWS provider defaults to false when omitted).
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_kms_key"
	object.get(resource.values, "enable_key_rotation", false) != true
	msg := sprintf(
		"[NIS2-CRYPTO-001] KMS key '%s' does not have automatic key rotation enabled. Set enable_key_rotation = true to satisfy NIS2 Art.21(2)(h) key management requirements.",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 2 — AWS RDS instance without storage encryption
#           Covers both explicit `storage_encrypted = false` and absent attribute.
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_db_instance"
	object.get(resource.values, "storage_encrypted", false) != true
	msg := sprintf(
		"[NIS2-CRYPTO-001] RDS instance '%s' does not have storage encryption enabled. Set storage_encrypted = true to protect data at rest per NIS2 Art.21(2)(h) and GDPR Art.32.",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 3 — SSM Parameter with secret-like name stored as plaintext String
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_ssm_parameter"
	resource.values.type == "String"
	name_lower := lower(resource.values.name)
	pattern := _secret_name_patterns[_]
	contains(name_lower, pattern)
	msg := sprintf(
		"[NIS2-CRYPTO-001] SSM parameter '%s' has a secret-like name but is stored as plaintext 'String' type. Use type = \"SecureString\" with a KMS key to satisfy NIS2 Art.21(2)(h) encryption requirements.",
		[resource.address],
	)
}
