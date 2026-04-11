# policies/terraform/deny_missing_tags_test.rego
#
# Unit tests for the FINOPS-001 policy.  Run with:
#   opa test policies/terraform/ -v

package terraform.finops_test

import data.terraform.finops
import rego.v1

# ---------------------------------------------------------------------------
# Helper fixtures
# ---------------------------------------------------------------------------

resource_with_all_tags := {
	"address": "local_file.app_config",
	"type": "local_file",
	"values": {
		"tags": {
			"environment": "dev",
			"app_name": "demo-webapp",
			"owner": "platform-team",
			"cost_center": "CC-1234",
		},
	},
}

resource_missing_owner := {
	"address": "local_file.bad_resource",
	"type": "local_file",
	"values": {
		"tags": {
			"environment": "dev",
			"app_name": "demo-webapp",
			"cost_center": "CC-1234",
		},
	},
}

resource_no_tags := {
	"address": "local_file.no_tags",
	"type": "local_file",
	"values": {},
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_compliant_resource_passes if {
	mock_input := {"planned_values": {"root_module": {"resources": [resource_with_all_tags]}}}
	count(finops.deny) == 0 with input as mock_input
}

test_resource_missing_tag_denied if {
	mock_input := {"planned_values": {"root_module": {"resources": [resource_missing_owner]}}}
	msgs := finops.deny with input as mock_input
	count(msgs) == 1
	some msg in msgs
	contains(msg, "FINOPS-001")
	contains(msg, "owner")
}

test_resource_no_tags_denied if {
	mock_input := {"planned_values": {"root_module": {"resources": [resource_no_tags]}}}
	msgs := finops.deny with input as mock_input
	count(msgs) == 1
}
