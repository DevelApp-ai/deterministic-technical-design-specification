# policies/terraform/deny_public_access_test.rego
#
# Unit tests for SEC-002: deny_public_access.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.security_test

import data.terraform.security
import rego.v1

# ---------------------------------------------------------------------------
# Helper: wrap resources in the planned_values structure
# ---------------------------------------------------------------------------
_mock_input(resources) := {"planned_values": {"root_module": {"resources": resources}}}

# ===========================================================================
# Rule 1: AWS S3 public ACL
# ===========================================================================

test_s3_public_read_acl_denied if {
	mock := _mock_input([{
		"address": "aws_s3_bucket.example",
		"type":    "aws_s3_bucket",
		"values":  {"acl": "public-read"},
	}])
	count(security.deny) == 1 with input as mock
}

test_s3_public_read_write_acl_denied if {
	mock := _mock_input([{
		"address": "aws_s3_bucket.example",
		"type":    "aws_s3_bucket",
		"values":  {"acl": "public-read-write"},
	}])
	count(security.deny) == 1 with input as mock
}

test_s3_private_acl_passes if {
	mock := _mock_input([{
		"address": "aws_s3_bucket.example",
		"type":    "aws_s3_bucket",
		"values":  {"acl": "private"},
	}])
	count(security.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 2: AWS Security Group unrestricted ingress on sensitive port
# ===========================================================================

test_sg_ssh_open_to_internet_denied if {
	mock := _mock_input([{
		"address": "aws_security_group.web",
		"type":    "aws_security_group",
		"values":  {"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]}]},
	}])
	count(security.deny) == 1 with input as mock
}

test_sg_rdp_open_to_internet_denied if {
	mock := _mock_input([{
		"address": "aws_security_group.windows",
		"type":    "aws_security_group",
		"values":  {"ingress": [{"from_port": 3389, "to_port": 3389, "cidr_blocks": ["0.0.0.0/0"]}]},
	}])
	count(security.deny) == 1 with input as mock
}

test_sg_ssh_private_cidr_passes if {
	mock := _mock_input([{
		"address": "aws_security_group.internal",
		"type":    "aws_security_group",
		"values":  {"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["10.0.0.0/8"]}]},
	}])
	count(security.deny) == 0 with input as mock
}

test_sg_http_open_to_internet_passes if {
	# Port 80 is not in the sensitive ports list — intentionally public
	mock := _mock_input([{
		"address": "aws_security_group.web",
		"type":    "aws_security_group",
		"values":  {"ingress": [{"from_port": 80, "to_port": 80, "cidr_blocks": ["0.0.0.0/0"]}]},
	}])
	count(security.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 3: Azure Storage Account public blob access
# ===========================================================================

test_azure_storage_public_blob_denied if {
	mock := _mock_input([{
		"address": "azurerm_storage_account.example",
		"type":    "azurerm_storage_account",
		"values":  {"allow_blob_public_access": true},
	}])
	count(security.deny) == 1 with input as mock
}

test_azure_storage_no_public_blob_passes if {
	mock := _mock_input([{
		"address": "azurerm_storage_account.example",
		"type":    "azurerm_storage_account",
		"values":  {"allow_blob_public_access": false},
	}])
	count(security.deny) == 0 with input as mock
}
