# policies/terraform/deny_public_iam_test.rego
#
# Unit tests for SEC-003: deny_public_iam.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.iam_test

import data.terraform.iam
import rego.v1

# ---------------------------------------------------------------------------
# Helper: wrap resources in planned_values structure
# ---------------------------------------------------------------------------
_mock_input(resources) := {"planned_values": {"root_module": {"resources": resources}}}

# ===========================================================================
# Rule 1: IAM role trust policy with wildcard principal
# ===========================================================================

_wildcard_trust_policy := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"sts:AssumeRole"}]}`
_scoped_trust_policy   := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}`

test_iam_role_wildcard_principal_denied if {
	mock := _mock_input([{
		"address": "aws_iam_role.example",
		"type":    "aws_iam_role",
		"values":  {"assume_role_policy": _wildcard_trust_policy},
	}])
	count(iam.deny) == 1 with input as mock
}

test_iam_role_scoped_principal_passes if {
	mock := _mock_input([{
		"address": "aws_iam_role.example",
		"type":    "aws_iam_role",
		"values":  {"assume_role_policy": _scoped_trust_policy},
	}])
	count(iam.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 2: IAM policy with wildcard action on sensitive service
# ===========================================================================

_wildcard_iam_policy    := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"iam:*","Resource":"*"}]}`
_star_policy            := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}`
_least_privilege_policy := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject"],"Resource":"arn:aws:s3:::my-bucket/*"}]}`

test_iam_policy_wildcard_iam_action_denied if {
	mock := _mock_input([{
		"address": "aws_iam_policy.example",
		"type":    "aws_iam_policy",
		"values":  {"policy": _wildcard_iam_policy},
	}])
	count(iam.deny) == 1 with input as mock
}

test_iam_policy_star_action_denied if {
	mock := _mock_input([{
		"address": "aws_iam_policy.example",
		"type":    "aws_iam_policy",
		"values":  {"policy": _star_policy},
	}])
	count(iam.deny) == 1 with input as mock
}

test_iam_policy_least_privilege_passes if {
	mock := _mock_input([{
		"address": "aws_iam_policy.example",
		"type":    "aws_iam_policy",
		"values":  {"policy": _least_privilege_policy},
	}])
	count(iam.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 3: S3 bucket policy with wildcard principal
# ===========================================================================

_public_bucket_policy  := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::my-bucket/*"}]}`
_private_bucket_policy := `{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::123456789012:root"},"Action":"s3:GetObject","Resource":"arn:aws:s3:::my-bucket/*"}]}`

test_s3_bucket_policy_wildcard_principal_denied if {
	mock := _mock_input([{
		"address": "aws_s3_bucket_policy.example",
		"type":    "aws_s3_bucket_policy",
		"values":  {"policy": _public_bucket_policy},
	}])
	count(iam.deny) == 1 with input as mock
}

test_s3_bucket_policy_scoped_principal_passes if {
	mock := _mock_input([{
		"address": "aws_s3_bucket_policy.example",
		"type":    "aws_s3_bucket_policy",
		"values":  {"policy": _private_bucket_policy},
	}])
	count(iam.deny) == 0 with input as mock
}
