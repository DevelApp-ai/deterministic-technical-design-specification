# policies/terraform/deny_nis2_crypto_test.rego
#
# Unit tests for NIS2-CRYPTO-001: deny_nis2_crypto.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.nis2_test

import data.terraform.nis2
import rego.v1

_mock_input(resources) := {"planned_values": {"root_module": {"resources": resources}}}

# ===========================================================================
# Rule 1: AWS KMS key rotation
# ===========================================================================

test_kms_rotation_disabled_denied if {
	mock := _mock_input([{
		"address": "aws_kms_key.app",
		"type":    "aws_kms_key",
		"values":  {"enable_key_rotation": false, "description": "App key"},
	}])
	msgs := nis2.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "NIS2-CRYPTO-001")
	contains(msg, "key rotation")
}

test_kms_rotation_absent_denied if {
	mock := _mock_input([{
		"address": "aws_kms_key.app",
		"type":    "aws_kms_key",
		"values":  {"description": "App key"},
	}])
	msgs := nis2.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "NIS2-CRYPTO-001")
}

test_kms_rotation_enabled_passes if {
	mock := _mock_input([{
		"address": "aws_kms_key.app",
		"type":    "aws_kms_key",
		"values":  {"enable_key_rotation": true, "description": "App key"},
	}])
	count(nis2.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 2: AWS RDS storage encryption
# ===========================================================================

test_rds_unencrypted_denied if {
	mock := _mock_input([{
		"address": "aws_db_instance.main",
		"type":    "aws_db_instance",
		"values": {
			"identifier":        "mydb",
			"storage_encrypted": false,
			"engine":            "postgres",
		},
	}])
	msgs := nis2.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "NIS2-CRYPTO-001")
	contains(msg, "storage encryption")
}

test_rds_encryption_absent_denied if {
	mock := _mock_input([{
		"address": "aws_db_instance.main",
		"type":    "aws_db_instance",
		"values": {
			"identifier": "mydb",
			"engine":     "postgres",
		},
	}])
	msgs := nis2.deny with input as mock
	count(msgs) == 1
}

test_rds_encrypted_passes if {
	mock := _mock_input([{
		"address": "aws_db_instance.main",
		"type":    "aws_db_instance",
		"values": {
			"identifier":        "mydb",
			"storage_encrypted": true,
			"engine":            "postgres",
		},
	}])
	count(nis2.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 3: SSM parameter plaintext secret
# ===========================================================================

test_ssm_plaintext_password_denied if {
	mock := _mock_input([{
		"address": "aws_ssm_parameter.db_password",
		"type":    "aws_ssm_parameter",
		"values": {
			"name":  "/app/db/password",
			"type":  "String",
			"value": "s3cr3t",
		},
	}])
	msgs := nis2.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "NIS2-CRYPTO-001")
	contains(msg, "SecureString")
}

test_ssm_plaintext_token_denied if {
	mock := _mock_input([{
		"address": "aws_ssm_parameter.api_token",
		"type":    "aws_ssm_parameter",
		"values": {
			"name":  "/service/api/token",
			"type":  "String",
			"value": "tok_abc123",
		},
	}])
	msgs := nis2.deny with input as mock
	count(msgs) == 1
}

test_ssm_plaintext_credential_denied if {
	mock := _mock_input([{
		"address": "aws_ssm_parameter.cred",
		"type":    "aws_ssm_parameter",
		"values": {
			"name":  "/app/credential",
			"type":  "String",
			"value": "secret_value",
		},
	}])
	msgs := nis2.deny with input as mock
	count(msgs) == 1
}

test_ssm_securestring_secret_passes if {
	mock := _mock_input([{
		"address": "aws_ssm_parameter.db_password",
		"type":    "aws_ssm_parameter",
		"values": {
			"name":  "/app/db/password",
			"type":  "SecureString",
			"value": "s3cr3t",
		},
	}])
	count(nis2.deny) == 0 with input as mock
}

test_ssm_plaintext_non_secret_name_passes if {
	# A plain String parameter whose name contains no secret-like words is fine
	mock := _mock_input([{
		"address": "aws_ssm_parameter.config",
		"type":    "aws_ssm_parameter",
		"values": {
			"name":  "/app/region",
			"type":  "String",
			"value": "eu-west-1",
		},
	}])
	count(nis2.deny) == 0 with input as mock
}

# ===========================================================================
# Combined violations
# ===========================================================================

test_multiple_violations_counted if {
	mock := _mock_input([
		{
			"address": "aws_kms_key.app",
			"type":    "aws_kms_key",
			"values":  {"enable_key_rotation": false},
		},
		{
			"address": "aws_db_instance.main",
			"type":    "aws_db_instance",
			"values":  {"storage_encrypted": false, "engine": "mysql"},
		},
	])
	count(nis2.deny) == 2 with input as mock
}

test_non_crypto_resource_passes if {
	mock := _mock_input([{
		"address": "local_file.readme",
		"type":    "local_file",
		"values":  {"filename": "/tmp/readme.md", "content": "hello"},
	}])
	count(nis2.deny) == 0 with input as mock
}
