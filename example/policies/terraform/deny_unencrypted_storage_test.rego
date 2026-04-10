# policies/terraform/deny_unencrypted_storage_test.rego
#
# Unit tests for SEC-001: deny_unencrypted_storage.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.security_test

import data.terraform.security
import rego.v1

_mock_input(resources) := {"planned_values": {"root_module": {"resources": resources}}}

# ===========================================================================
# EBS volume encryption
# ===========================================================================

test_ebs_unencrypted_denied if {
	mock := _mock_input([{
		"address": "aws_ebs_volume.data",
		"type":    "aws_ebs_volume",
		"values":  {"encrypted": false},
	}])
	msgs := security.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SEC-001")
	contains(msg, "aws_ebs_volume.data")
}

test_ebs_encrypted_passes if {
	mock := _mock_input([{
		"address": "aws_ebs_volume.data",
		"type":    "aws_ebs_volume",
		"values":  {"encrypted": true},
	}])
	count(security.deny) == 0 with input as mock
}

# ===========================================================================
# S3 public access block
# ===========================================================================

test_s3_public_acls_not_blocked_denied if {
	mock := _mock_input([{
		"address": "aws_s3_bucket_public_access_block.app",
		"type":    "aws_s3_bucket_public_access_block",
		"values":  {"block_public_acls": false},
	}])
	msgs := security.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SEC-001")
	contains(msg, "block_public_acls")
}

test_s3_public_acls_blocked_passes if {
	mock := _mock_input([{
		"address": "aws_s3_bucket_public_access_block.app",
		"type":    "aws_s3_bucket_public_access_block",
		"values":  {"block_public_acls": true},
	}])
	count(security.deny) == 0 with input as mock
}

# ===========================================================================
# Combined: multiple violations in one plan
# ===========================================================================

test_multiple_violations_counted if {
	mock := _mock_input([
		{
			"address": "aws_ebs_volume.vol1",
			"type":    "aws_ebs_volume",
			"values":  {"encrypted": false},
		},
		{
			"address": "aws_ebs_volume.vol2",
			"type":    "aws_ebs_volume",
			"values":  {"encrypted": false},
		},
	])
	count(security.deny) == 2 with input as mock
}

test_no_storage_resources_passes if {
	mock := _mock_input([{
		"address": "local_file.readme",
		"type":    "local_file",
		"values":  {"content": "hello", "filename": "/tmp/readme.md"},
	}])
	count(security.deny) == 0 with input as mock
}
