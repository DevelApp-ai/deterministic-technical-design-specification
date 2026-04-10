# policies/terraform/deny_unrestricted_network.rego
#
# SEC-004 — Deny Unrestricted Network Egress
#
# Network security rules that allow ALL outbound traffic (destination 0.0.0.0/0
# on all ports and protocols) create an uncontrolled egress path that can be used
# for data exfiltration, C2 communication, or to pivot from a compromised resource.
#
# Covered resource patterns (evaluated against terraform plan JSON):
#   - AWS Security Group with unrestricted egress (allow all outbound)
#   - Azure NSG security rules with Outbound Allow to * on port *
#   - Any subnet_cidr_block that falls within a public IP range when it
#     should be private (RFC-1918 enforcement)
#
# Related ADR:          docs/adrs/0002-use-opa-for-policy.md
# Related requirements: M-003, S-001, CYB-004
# CIS Benchmark:        AWS CIS 5.3 (no unrestricted outbound), 5.4 (default SG restricts all)
# NIST 800-53:          SC-7, CA-3
# SOC 2 CC:             CC6.6, CC6.7

package terraform.network

import rego.v1

# RFC-1918 private IP ranges — subnets should use these
_private_cidr_prefixes := {"10.", "172.16.", "172.17.", "172.18.", "172.19.",
	"172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25.", "172.26.",
	"172.27.", "172.28.", "172.29.", "172.30.", "172.31.", "192.168."}

__rego__metadoc__ := {
	"id":          "SEC-004",
	"title":       "Deny Unrestricted Network Egress",
	"description": "Network security rules must not allow all outbound traffic. Unrestricted egress enables data exfiltration and lateral movement.",
	"severity":    "HIGH",
	"remediation": "Replace 'allow all outbound' rules with explicit allow-lists for required ports and destinations.",
	"related_adr":          ["ADR-0002"],
	"related_requirements": ["M-003", "S-001", "CYB-004"],
	"compliance": {
		"cis_aws":     ["5.3", "5.4"],
		"nist_800_53": ["SC-7", "CA-3"],
		"soc2_cc":     ["CC6.6", "CC6.7"],
	},
}

# ---------------------------------------------------------------------------
# Rule 1 — AWS Security Group: unrestricted outbound on all ports
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_security_group"
	rule := resource.values.egress[_]
	rule.cidr_blocks[_] == "0.0.0.0/0"
	rule.from_port == 0
	rule.to_port == 0
	rule.protocol == "-1"
	msg := sprintf(
		"[SEC-004] Security group '%s' has an unrestricted egress rule (all traffic to 0.0.0.0/0). Replace with explicit allow rules for required outbound ports. (CIS AWS 5.3)",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 2 — Azure NSG: Allow Outbound rule targeting Any destination on Any port
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "azurerm_network_security_rule"
	resource.values.direction == "Outbound"
	resource.values.access == "Allow"
	resource.values.destination_address_prefix == "*"
	resource.values.destination_port_range == "*"
	msg := sprintf(
		"[SEC-004] Azure NSG rule '%s' allows all outbound traffic to any destination on any port. Define specific destination prefixes and port ranges. (CIS Azure 6.2)",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 3 — Subnet CIDR outside RFC-1918 private ranges
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type in {"aws_subnet", "azurerm_subnet"}
	cidr := resource.values.cidr_block
	not _is_private_cidr(cidr)
	msg := sprintf(
		"[SEC-004] Subnet '%s' uses CIDR '%s' which is not in an RFC-1918 private range. Subnets must use private IP space (10.x.x.x, 172.16-31.x.x, 192.168.x.x). (NIST SC-7)",
		[resource.address, cidr],
	)
}

# ---------------------------------------------------------------------------
# Helper: check whether a CIDR starts with an RFC-1918 prefix
# ---------------------------------------------------------------------------
_is_private_cidr(cidr) if {
	prefix := _private_cidr_prefixes[_]
	startswith(cidr, prefix)
}
