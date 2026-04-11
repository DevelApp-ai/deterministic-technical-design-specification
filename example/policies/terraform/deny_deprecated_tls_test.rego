# policies/terraform/deny_deprecated_tls_test.rego
#
# Unit tests for SEC-006: deny_deprecated_tls.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.tls_test

import data.terraform.tls
import rego.v1

_mock_input(resources) := {"planned_values": {"root_module": {"resources": resources}}}

# ===========================================================================
# Rule 1: AWS ALB HTTPS listener — deprecated SSL policy
# ===========================================================================

test_alb_deprecated_tls10_policy_denied if {
	mock := _mock_input([{
		"address": "aws_alb_listener.https",
		"type":    "aws_alb_listener",
		"values": {
			"port":       443,
			"protocol":   "HTTPS",
			"ssl_policy": "ELBSecurityPolicy-TLS-1-0-2015-04",
		},
	}])
	msgs := tls.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SEC-006")
	contains(msg, "ELBSecurityPolicy-TLS-1-0")
}

test_alb_deprecated_tls11_policy_denied if {
	mock := _mock_input([{
		"address": "aws_alb_listener.https",
		"type":    "aws_alb_listener",
		"values": {
			"port":       443,
			"protocol":   "HTTPS",
			"ssl_policy": "ELBSecurityPolicy-TLS-1-1-2017-01",
		},
	}])
	msgs := tls.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SEC-006")
}

test_alb_modern_tls_policy_passes if {
	mock := _mock_input([{
		"address": "aws_alb_listener.https",
		"type":    "aws_alb_listener",
		"values": {
			"port":       443,
			"protocol":   "HTTPS",
			"ssl_policy": "ELBSecurityPolicy-TLS13-1-2-2021-06",
		},
	}])
	count(tls.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 2: AWS CloudFront deprecated minimum protocol
# ===========================================================================

test_cloudfront_tls10_denied if {
	mock := _mock_input([{
		"address": "aws_cloudfront_distribution.cdn",
		"type":    "aws_cloudfront_distribution",
		"values": {
			"viewer_certificate": [{"minimum_protocol_version": "TLSv1"}],
		},
	}])
	msgs := tls.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SEC-006")
	contains(msg, "TLSv1")
}

test_cloudfront_sslv3_denied if {
	mock := _mock_input([{
		"address": "aws_cloudfront_distribution.cdn",
		"type":    "aws_cloudfront_distribution",
		"values": {
			"viewer_certificate": [{"minimum_protocol_version": "SSLv3"}],
		},
	}])
	msgs := tls.deny with input as mock
	some msg in msgs
	contains(msg, "SEC-006")
}

test_cloudfront_tls12_passes if {
	mock := _mock_input([{
		"address": "aws_cloudfront_distribution.cdn",
		"type":    "aws_cloudfront_distribution",
		"values": {
			"viewer_certificate": [{"minimum_protocol_version": "TLSv1.2_2021"}],
		},
	}])
	count(tls.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 4: Generic min_tls_version attribute
# ===========================================================================

test_generic_tls10_attribute_denied if {
	mock := _mock_input([{
		"address": "azurerm_storage_account.app",
		"type":    "azurerm_storage_account",
		"values":  {"min_tls_version": "TLS1_0"},
	}])
	msgs := tls.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SEC-006")
	contains(msg, "TLS1_0")
}

test_generic_tls11_attribute_denied if {
	mock := _mock_input([{
		"address": "azurerm_storage_account.app",
		"type":    "azurerm_storage_account",
		"values":  {"min_tls_version": "TLS1_1"},
	}])
	msgs := tls.deny with input as mock
	count(msgs) == 1
}

test_generic_tls12_attribute_passes if {
	mock := _mock_input([{
		"address": "azurerm_storage_account.app",
		"type":    "azurerm_storage_account",
		"values":  {"min_tls_version": "TLS1_2"},
	}])
	count(tls.deny) == 0 with input as mock
}

test_resource_without_tls_attribute_passes if {
	mock := _mock_input([{
		"address": "local_file.readme",
		"type":    "local_file",
		"values":  {"filename": "/tmp/readme.md", "content": "hello"},
	}])
	count(tls.deny) == 0 with input as mock
}
