# policies/terraform/deny_dora_ict_risk_test.rego
#
# Unit tests for DORA-ICT-001: deny_dora_ict_risk.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.dora_test

import data.terraform.dora
import rego.v1

_mock_input(resources) := {"planned_values": {"root_module": {"resources": resources}}}

# ===========================================================================
# Rule 1: CloudTrail log-file validation
# ===========================================================================

test_cloudtrail_validation_disabled_denied if {
	mock := _mock_input([{
		"address": "aws_cloudtrail.main",
		"type":    "aws_cloudtrail",
		"values": {
			"name":                        "main-trail",
			"enable_log_file_validation":  false,
			"s3_bucket_name":              "my-logs",
		},
	}])
	msgs := dora.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "DORA-ICT-001")
	contains(msg, "log-file validation")
}

test_cloudtrail_validation_absent_denied if {
	mock := _mock_input([{
		"address": "aws_cloudtrail.main",
		"type":    "aws_cloudtrail",
		"values": {
			"name":           "main-trail",
			"s3_bucket_name": "my-logs",
		},
	}])
	msgs := dora.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "DORA-ICT-001")
}

test_cloudtrail_validation_enabled_passes if {
	mock := _mock_input([{
		"address": "aws_cloudtrail.main",
		"type":    "aws_cloudtrail",
		"values": {
			"name":                       "main-trail",
			"enable_log_file_validation": true,
			"s3_bucket_name":             "my-logs",
		},
	}])
	count(dora.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 2: CloudWatch log group retention
# ===========================================================================

test_log_group_zero_retention_denied if {
	mock := _mock_input([{
		"address": "aws_cloudwatch_log_group.app",
		"type":    "aws_cloudwatch_log_group",
		"values": {
			"name":              "/app/service",
			"retention_in_days": 0,
		},
	}])
	msgs := dora.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "DORA-ICT-001")
	contains(msg, "retention")
}

test_log_group_absent_retention_denied if {
	mock := _mock_input([{
		"address": "aws_cloudwatch_log_group.app",
		"type":    "aws_cloudwatch_log_group",
		"values":  {"name": "/app/service"},
	}])
	msgs := dora.deny with input as mock
	count(msgs) == 1
}

test_log_group_90_day_retention_passes if {
	mock := _mock_input([{
		"address": "aws_cloudwatch_log_group.app",
		"type":    "aws_cloudwatch_log_group",
		"values": {
			"name":              "/app/service",
			"retention_in_days": 90,
		},
	}])
	count(dora.deny) == 0 with input as mock
}

test_log_group_365_day_retention_passes if {
	mock := _mock_input([{
		"address": "aws_cloudwatch_log_group.prod",
		"type":    "aws_cloudwatch_log_group",
		"values": {
			"name":              "/prod/audit",
			"retention_in_days": 365,
		},
	}])
	count(dora.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 3: S3 bucket versioning
# ===========================================================================

test_s3_versioning_disabled_denied if {
	mock := _mock_input([{
		"address": "aws_s3_bucket_versioning.backup",
		"type":    "aws_s3_bucket_versioning",
		"values": {
			"bucket":                   "my-backup-bucket",
			"versioning_configuration": [{"status": "Disabled"}],
		},
	}])
	msgs := dora.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "DORA-ICT-001")
	contains(msg, "versioning")
}

test_s3_versioning_suspended_denied if {
	mock := _mock_input([{
		"address": "aws_s3_bucket_versioning.backup",
		"type":    "aws_s3_bucket_versioning",
		"values": {
			"bucket":                   "my-backup-bucket",
			"versioning_configuration": [{"status": "Suspended"}],
		},
	}])
	msgs := dora.deny with input as mock
	count(msgs) == 1
}

test_s3_versioning_absent_config_denied if {
	mock := _mock_input([{
		"address": "aws_s3_bucket_versioning.backup",
		"type":    "aws_s3_bucket_versioning",
		"values":  {"bucket": "my-backup-bucket"},
	}])
	msgs := dora.deny with input as mock
	count(msgs) == 1
}

test_s3_versioning_enabled_passes if {
	mock := _mock_input([{
		"address": "aws_s3_bucket_versioning.backup",
		"type":    "aws_s3_bucket_versioning",
		"values": {
			"bucket":                   "my-backup-bucket",
			"versioning_configuration": [{"status": "Enabled"}],
		},
	}])
	count(dora.deny) == 0 with input as mock
}

# ===========================================================================
# Combined violations
# ===========================================================================

test_multiple_dora_violations_counted if {
	mock := _mock_input([
		{
			"address": "aws_cloudtrail.main",
			"type":    "aws_cloudtrail",
			"values": {
				"name":                       "main-trail",
				"enable_log_file_validation": false,
			},
		},
		{
			"address": "aws_cloudwatch_log_group.app",
			"type":    "aws_cloudwatch_log_group",
			"values":  {"name": "/app/service", "retention_in_days": 0},
		},
		{
			"address": "aws_s3_bucket_versioning.backup",
			"type":    "aws_s3_bucket_versioning",
			"values": {
				"bucket":                   "my-backup",
				"versioning_configuration": [{"status": "Disabled"}],
			},
		},
	])
	count(dora.deny) == 3 with input as mock
}

test_non_ict_resource_passes if {
	mock := _mock_input([{
		"address": "local_file.readme",
		"type":    "local_file",
		"values":  {"filename": "/tmp/readme.md", "content": "hello"},
	}])
	count(dora.deny) == 0 with input as mock
}

test_all_compliant_passes if {
	mock := _mock_input([
		{
			"address": "aws_cloudtrail.main",
			"type":    "aws_cloudtrail",
			"values": {
				"name":                       "main-trail",
				"enable_log_file_validation": true,
			},
		},
		{
			"address": "aws_cloudwatch_log_group.app",
			"type":    "aws_cloudwatch_log_group",
			"values":  {"name": "/app/service", "retention_in_days": 365},
		},
		{
			"address": "aws_s3_bucket_versioning.backup",
			"type":    "aws_s3_bucket_versioning",
			"values": {
				"bucket":                   "my-backup",
				"versioning_configuration": [{"status": "Enabled"}],
			},
		},
	])
	count(dora.deny) == 0 with input as mock
}
