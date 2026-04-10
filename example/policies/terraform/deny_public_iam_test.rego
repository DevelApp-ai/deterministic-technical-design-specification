# policies/terraform/deny_public_iam_test.rego
#
# Unit tests for SEC-003: deny_public_iam.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.iam_test

import future.keywords.in

# ---------------------------------------------------------------------------
# Helper: build a plan input for a single resource
# ---------------------------------------------------------------------------
_plan_with(resource_type, resource_address, after_values) := {
    "resource_changes": [{
        "type":    resource_type,
        "address": resource_address,
        "change": {
            "actions": ["create"],
            "after":   after_values,
        },
    }]
}

# ===========================================================================
# Rule 1: IAM role trust policy with wildcard principal
# ===========================================================================

_wildcard_trust_policy := `{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": "*", "Action": "sts:AssumeRole"}]
}`

_scoped_trust_policy := `{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole"}]
}`

test_iam_role_wildcard_principal_denied if {
    input := _plan_with(
        "aws_iam_role",
        "aws_iam_role.example",
        {"assume_role_policy": _wildcard_trust_policy},
    )
    count(data.terraform.iam.deny) == 1 with data.terraform.iam.deny as
        data.terraform.iam.deny with input as input
}

test_iam_role_scoped_principal_passes if {
    input := _plan_with(
        "aws_iam_role",
        "aws_iam_role.example",
        {"assume_role_policy": _scoped_trust_policy},
    )
    count(data.terraform.iam.deny) == 0 with data.terraform.iam.deny as
        data.terraform.iam.deny with input as input
}

# ===========================================================================
# Rule 2: IAM policy with wildcard action on sensitive service
# ===========================================================================

_wildcard_iam_policy := `{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": "iam:*", "Resource": "*"}]
}`

_star_policy := `{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]
}`

_least_privilege_policy := `{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "arn:aws:s3:::my-bucket/*"}]
}`

test_iam_policy_wildcard_iam_action_denied if {
    input := _plan_with(
        "aws_iam_policy",
        "aws_iam_policy.example",
        {"policy": _wildcard_iam_policy},
    )
    count(data.terraform.iam.deny) == 1 with data.terraform.iam.deny as
        data.terraform.iam.deny with input as input
}

test_iam_policy_star_action_denied if {
    input := _plan_with(
        "aws_iam_policy",
        "aws_iam_policy.example",
        {"policy": _star_policy},
    )
    count(data.terraform.iam.deny) == 1 with data.terraform.iam.deny as
        data.terraform.iam.deny with input as input
}

test_iam_policy_least_privilege_passes if {
    input := _plan_with(
        "aws_iam_policy",
        "aws_iam_policy.example",
        {"policy": _least_privilege_policy},
    )
    count(data.terraform.iam.deny) == 0 with data.terraform.iam.deny as
        data.terraform.iam.deny with input as input
}

# ===========================================================================
# Rule 3: S3 bucket policy with wildcard principal
# ===========================================================================

_public_bucket_policy := `{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": "*", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::my-bucket/*"}]
}`

_private_bucket_policy := `{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::123456789012:root"}, "Action": "s3:GetObject", "Resource": "arn:aws:s3:::my-bucket/*"}]
}`

test_s3_bucket_policy_wildcard_principal_denied if {
    input := _plan_with(
        "aws_s3_bucket_policy",
        "aws_s3_bucket_policy.example",
        {"policy": _public_bucket_policy},
    )
    count(data.terraform.iam.deny) == 1 with data.terraform.iam.deny as
        data.terraform.iam.deny with input as input
}

test_s3_bucket_policy_scoped_principal_passes if {
    input := _plan_with(
        "aws_s3_bucket_policy",
        "aws_s3_bucket_policy.example",
        {"policy": _private_bucket_policy},
    )
    count(data.terraform.iam.deny) == 0 with data.terraform.iam.deny as
        data.terraform.iam.deny with input as input
}
