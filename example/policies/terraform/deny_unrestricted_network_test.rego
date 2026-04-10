# policies/terraform/deny_unrestricted_network_test.rego
#
# Unit tests for SEC-004: deny_unrestricted_network.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.network_test

import data.terraform.network
import rego.v1

_mock_input(resources) := {"planned_values": {"root_module": {"resources": resources}}}

# ===========================================================================
# Rule 1: AWS Security Group unrestricted egress
# ===========================================================================

test_sg_unrestricted_egress_denied if {
	mock := _mock_input([{
		"address": "aws_security_group.open",
		"type":    "aws_security_group",
		"values": {
			"egress": [{"cidr_blocks": ["0.0.0.0/0"], "from_port": 0, "to_port": 0, "protocol": "-1"}],
		},
	}])
	count(network.deny) == 1 with input as mock
}

test_sg_restricted_egress_passes if {
	mock := _mock_input([{
		"address": "aws_security_group.restricted",
		"type":    "aws_security_group",
		"values": {
			"egress": [{"cidr_blocks": ["0.0.0.0/0"], "from_port": 443, "to_port": 443, "protocol": "tcp"}],
		},
	}])
	count(network.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 2: Azure NSG unrestricted outbound allow rule
# ===========================================================================

test_azure_nsg_unrestricted_outbound_denied if {
	mock := _mock_input([{
		"address": "azurerm_network_security_rule.allow_all_out",
		"type":    "azurerm_network_security_rule",
		"values": {
			"direction":                    "Outbound",
			"access":                       "Allow",
			"destination_address_prefix":   "*",
			"destination_port_range":       "*",
		},
	}])
	count(network.deny) == 1 with input as mock
}

test_azure_nsg_specific_outbound_passes if {
	mock := _mock_input([{
		"address": "azurerm_network_security_rule.https_out",
		"type":    "azurerm_network_security_rule",
		"values": {
			"direction":                    "Outbound",
			"access":                       "Allow",
			"destination_address_prefix":   "10.0.0.0/8",
			"destination_port_range":       "443",
		},
	}])
	count(network.deny) == 0 with input as mock
}

test_azure_nsg_deny_rule_passes if {
	# A Deny rule with wildcard is fine — it's the default-deny baseline
	mock := _mock_input([{
		"address": "azurerm_network_security_rule.deny_all_out",
		"type":    "azurerm_network_security_rule",
		"values": {
			"direction":                    "Outbound",
			"access":                       "Deny",
			"destination_address_prefix":   "*",
			"destination_port_range":       "*",
		},
	}])
	count(network.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 3: Subnet CIDR outside RFC-1918
# ===========================================================================

test_public_subnet_cidr_denied if {
	mock := _mock_input([{
		"address": "aws_subnet.public_direct",
		"type":    "aws_subnet",
		"values":  {"cidr_block": "203.0.113.0/24"},
	}])
	count(network.deny) == 1 with input as mock
}

test_private_subnet_10_passes if {
	mock := _mock_input([{
		"address": "aws_subnet.private1",
		"type":    "aws_subnet",
		"values":  {"cidr_block": "10.0.1.0/24"},
	}])
	count(network.deny) == 0 with input as mock
}

test_private_subnet_172_passes if {
	mock := _mock_input([{
		"address": "aws_subnet.private2",
		"type":    "aws_subnet",
		"values":  {"cidr_block": "172.16.1.0/24"},
	}])
	count(network.deny) == 0 with input as mock
}

test_private_subnet_192_passes if {
	mock := _mock_input([{
		"address": "aws_subnet.private3",
		"type":    "aws_subnet",
		"values":  {"cidr_block": "192.168.1.0/24"},
	}])
	count(network.deny) == 0 with input as mock
}
