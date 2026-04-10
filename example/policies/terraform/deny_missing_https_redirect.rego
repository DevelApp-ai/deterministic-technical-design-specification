# policies/terraform/deny_missing_https_redirect.rego
#
# SEC-005 — HTTPS Enforcement
#
# All public HTTP (port 80) listeners must redirect to HTTPS.  Serving
# application traffic over plain HTTP risks credential interception, session
# hijacking, and fails compliance frameworks that require encryption in transit.
#
# Covered patterns (evaluated against terraform plan JSON):
#   - AWS ALB listener on port 80 that is NOT a redirect to HTTPS
#   - Azure Application Gateway HTTP setting with `https_only = false`
#   - Any local_file deployment manifest that exposes port 80 without a
#     redirect annotation (demo-friendly rule for the local provider)
#
# Related ADR:          docs/adrs/0002-use-opa-for-policy.md
# Related requirements: M-003, S-001, CYB-002, SEC-005
# CIS Benchmark:        AWS CIS 2.1.1 (S3 HTTPS only), 8.2 (ALB HTTPS redirect)
# NIST 800-53:          SC-8, SC-23
# SOC 2 CC:             CC6.7

package terraform.https

import rego.v1

__rego__metadoc__ := {
	"id":          "SEC-005",
	"title":       "HTTPS Enforcement — HTTP Must Redirect to HTTPS",
	"description": "Public HTTP (port 80) listeners must redirect to HTTPS. Plain-text HTTP is prohibited on internet-facing load balancers and application gateways.",
	"severity":    "HIGH",
	"remediation": "Add a redirect action from HTTP (port 80) to HTTPS (port 443) on the load balancer listener. Do not serve application traffic over HTTP.",
	"related_adr":          ["ADR-0002"],
	"related_requirements": ["M-003", "S-001", "CYB-002"],
	"compliance": {
		"cis_aws":     ["8.2"],
		"nist_800_53": ["SC-8", "SC-23"],
		"soc2_cc":     ["CC6.7"],
	},
}

# ---------------------------------------------------------------------------
# Rule 1 — AWS ALB listener on port 80 without HTTPS redirect
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_alb_listener"
	resource.values.port == 80
	resource.values.protocol == "HTTP"
	# The default_action must be a redirect to HTTPS; anything else is a violation
	action := resource.values.default_action[_]
	action.type != "redirect"
	msg := sprintf(
		"[SEC-005] ALB listener '%s' serves HTTP on port 80 without a redirect action. Configure a redirect to HTTPS. (CIS AWS 8.2)",
		[resource.address],
	)
}

deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_alb_listener"
	resource.values.port == 80
	resource.values.protocol == "HTTP"
	action := resource.values.default_action[_]
	action.type == "redirect"
	# Redirect exists but does NOT target HTTPS
	redirect := action.redirect[_]
	redirect.protocol != "HTTPS"
	msg := sprintf(
		"[SEC-005] ALB listener '%s' has a redirect action but it does not redirect to HTTPS (protocol = '%s'). (CIS AWS 8.2)",
		[resource.address, redirect.protocol],
	)
}

# ---------------------------------------------------------------------------
# Rule 2 — Azure Application Gateway HTTP listener without HTTPS
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "azurerm_application_gateway"
	http_setting := resource.values.backend_http_settings[_]
	http_setting.protocol == "Http"
	# No request routing rule that maps to an HTTPS redirect
	msg := sprintf(
		"[SEC-005] Azure Application Gateway '%s' backend HTTP setting '%s' uses plain HTTP. Configure HTTPS and a redirect from port 80. (NIST SC-8)",
		[resource.address, http_setting.name],
	)
}

# ---------------------------------------------------------------------------
# Rule 3 — Deployment manifest exposes port 80 without redirect annotation
#           (demo-friendly: evaluates the local_file deployment manifests)
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "local_file"
	contains(resource.values.content, "containerPort: 80")
	not contains(resource.values.content, "redirect-https: \"true\"")
	msg := sprintf(
		"[SEC-005] Deployment manifest '%s' exposes port 80 but is missing the 'redirect-https: \"true\"' annotation. Add HTTPS redirect configuration. (NIST SC-8)",
		[resource.address],
	)
}
