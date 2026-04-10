# policies/terraform/deny_public_access_test.rego
#
# Pester-style OPA unit tests for SEC-002: deny_public_access.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.security_test

import future.keywords.in

# ---------------------------------------------------------------------------
# Helper: build minimal plan.json input for a single resource
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
# Rule 1: AWS S3 public ACL
# ===========================================================================

test_s3_public_read_acl_denied if {
    input := _plan_with(
        "aws_s3_bucket",
        "aws_s3_bucket.example",
        {"acl": "public-read"},
    )
    count(data.terraform.security.deny) == 1 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}

test_s3_public_read_write_acl_denied if {
    input := _plan_with(
        "aws_s3_bucket",
        "aws_s3_bucket.example",
        {"acl": "public-read-write"},
    )
    count(data.terraform.security.deny) == 1 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}

test_s3_private_acl_passes if {
    input := _plan_with(
        "aws_s3_bucket",
        "aws_s3_bucket.example",
        {"acl": "private"},
    )
    count(data.terraform.security.deny) == 0 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}

# ===========================================================================
# Rule 2: AWS Security Group unrestricted ingress on sensitive port
# ===========================================================================

test_sg_ssh_open_to_internet_denied if {
    input := _plan_with(
        "aws_security_group",
        "aws_security_group.web",
        {"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]}]},
    )
    count(data.terraform.security.deny) == 1 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}

test_sg_rdp_open_to_internet_denied if {
    input := _plan_with(
        "aws_security_group",
        "aws_security_group.windows",
        {"ingress": [{"from_port": 3389, "to_port": 3389, "cidr_blocks": ["0.0.0.0/0"]}]},
    )
    count(data.terraform.security.deny) == 1 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}

test_sg_ssh_private_cidr_passes if {
    input := _plan_with(
        "aws_security_group",
        "aws_security_group.internal",
        {"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["10.0.0.0/8"]}]},
    )
    count(data.terraform.security.deny) == 0 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}

test_sg_http_open_to_internet_passes if {
    # Port 80/443 are not in the sensitive ports list — intentionally public
    input := _plan_with(
        "aws_security_group",
        "aws_security_group.web",
        {"ingress": [{"from_port": 80, "to_port": 80, "cidr_blocks": ["0.0.0.0/0"]}]},
    )
    count(data.terraform.security.deny) == 0 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}

# ===========================================================================
# Rule 3: Azure Storage Account public blob access
# ===========================================================================

test_azure_storage_public_blob_denied if {
    input := _plan_with(
        "azurerm_storage_account",
        "azurerm_storage_account.example",
        {"allow_blob_public_access": true},
    )
    count(data.terraform.security.deny) == 1 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}

test_azure_storage_no_public_blob_passes if {
    input := _plan_with(
        "azurerm_storage_account",
        "azurerm_storage_account.example",
        {"allow_blob_public_access": false},
    )
    count(data.terraform.security.deny) == 0 with data.terraform.security.deny as
        data.terraform.security.deny with input as input
}
