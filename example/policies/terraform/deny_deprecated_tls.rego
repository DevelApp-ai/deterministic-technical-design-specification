# policies/terraform/deny_deprecated_tls.rego
#
# SEC-006 — Prohibit Deprecated TLS Versions
#
# TLS 1.0 and TLS 1.1 are cryptographically broken and must not be used.
# Only TLS 1.2 or higher is permitted on internet-facing and internal
# endpoints.  This protects against BEAST, POODLE, DROWN, and LOGJAM attacks.
#
# Covered patterns (evaluated against terraform plan JSON):
#   - AWS ALB security policy that permits TLS 1.0 or 1.1
#   - AWS CloudFront distribution with minimum_protocol_version < TLS 1.2
#   - Azure Application Gateway SSL policy with deprecated cipher suites
#   - Any resource with a `min_tls_version` attribute set to "1.0" or "1.1"
#
# Related ADR:          docs/adrs/0002-use-opa-for-policy.md
# Related requirements: M-003, S-001, CYB-002
# CIS Benchmark:        AWS CIS 2.9 (CloudFront TLS 1.2+), Azure CIS 9.3 (App GW TLS 1.2+)
# NIST 800-53:          SC-8, SC-23, IA-7
# SOC 2 CC:             CC6.7, CC6.8

package terraform.tls

import rego.v1

# TLS policy name fragments that indicate TLS 1.0 or 1.1 is permitted
_deprecated_alb_policies := {
	"ELBSecurityPolicy-TLS-1-0",
	"ELBSecurityPolicy-TLS-1-1",
	"ELBSecurityPolicy-2015-05",
	"ELBSecurityPolicy-2016-08",
}

# CloudFront minimum protocol versions that permit pre-TLS-1.2
_deprecated_cf_protocols := {
	"SSLv3",
	"TLSv1",
	"TLSv1_2016",
	"TLSv1.1_2016",
}

# Deprecated Azure SSL policy names
_deprecated_azure_ssl_policies := {
	"AppGwSslPolicy20150501",
	"AppGwSslPolicy20170401",
}

__rego__metadoc__ := {
	"id":          "SEC-006",
	"title":       "Prohibit Deprecated TLS Versions (TLS 1.0 / 1.1)",
	"description": "TLS 1.0 and TLS 1.1 are cryptographically weak and must not be enabled on any internet-facing or internal endpoint. Require TLS 1.2 or higher.",
	"severity":    "HIGH",
	"remediation": "Update the SSL/TLS policy to one that requires TLS 1.2 or higher. For AWS ALB use ELBSecurityPolicy-TLS13-1-2-2021-06 or newer.",
	"related_adr":          ["ADR-0002"],
	"related_requirements": ["M-003", "S-001", "CYB-002"],
	"compliance": {
		"nis2":        ["Art.21(2)(h)"],
		"dora":        ["Art.9"],
		"cis_aws":     ["2.9"],
		"cis_azure":   ["9.3"],
		"nist_800_53": ["SC-8", "SC-23", "IA-7"],
		"soc2_cc":     ["CC6.7", "CC6.8"],
	},
}

# ---------------------------------------------------------------------------
# Rule 1 — AWS ALB listener: deprecated SSL security policy
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_alb_listener"
	resource.values.protocol == "HTTPS"
	policy := resource.values.ssl_policy
	# Match any policy name that starts with a deprecated prefix
	some prefix in _deprecated_alb_policies
	startswith(policy, prefix)
	msg := sprintf(
		"[SEC-006] ALB listener '%s' uses deprecated SSL policy '%s' which permits TLS 1.0 or 1.1. Upgrade to ELBSecurityPolicy-TLS13-1-2-2021-06 or newer. (CIS AWS 2.9)",
		[resource.address, policy],
	)
}

# ---------------------------------------------------------------------------
# Rule 2 — AWS CloudFront: minimum protocol version allows pre-TLS-1.2
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_cloudfront_distribution"
	viewer_cert := resource.values.viewer_certificate[_]
	proto := viewer_cert.minimum_protocol_version
	_deprecated_cf_protocols[proto]
	msg := sprintf(
		"[SEC-006] CloudFront distribution '%s' minimum protocol version '%s' permits TLS below 1.2. Set minimum_protocol_version to TLSv1.2_2021 or higher. (CIS AWS 2.9)",
		[resource.address, proto],
	)
}

# ---------------------------------------------------------------------------
# Rule 3 — Azure Application Gateway: deprecated SSL policy
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "azurerm_application_gateway"
	ssl_policy := resource.values.ssl_policy[_]
	policy_name := ssl_policy.policy_name
	_deprecated_azure_ssl_policies[policy_name]
	msg := sprintf(
		"[SEC-006] Azure Application Gateway '%s' uses deprecated SSL policy '%s'. Update to AppGwSslPolicy20220101 or newer. (CIS Azure 9.3)",
		[resource.address, policy_name],
	)
}

# ---------------------------------------------------------------------------
# Rule 4 — Generic: any resource with min_tls_version set to 1.0 or 1.1
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.values.min_tls_version in {"TLS1_0", "TLS1_1", "1.0", "1.1"}
	msg := sprintf(
		"[SEC-006] Resource '%s' has min_tls_version set to '%s'. Minimum allowed TLS version is 1.2. (NIST SC-8)",
		[resource.address, resource.values.min_tls_version],
	)
}
