# policies/kubernetes/deny_missing_labels_test.rego
#
# Unit tests for K8S-003 — Required FinOps Labels.

package kubernetes.finops

import rego.v1

_good_labels := {
	"environment": "staging",
	"app_name": "dtds-example",
	"owner": "platform-team",
	"cost_center": "CC-1001",
}

_compliant_deployment := {
	"kind": "Deployment",
	"metadata": {"name": "dtds-docs", "labels": _good_labels},
}

_missing_one := {
	"kind": "Deployment",
	"metadata": {"name": "bad-app", "labels": {
		"environment": "staging",
		"app_name": "dtds-example",
		"owner": "platform-team",
		# cost_center missing
	}},
}

_missing_all := {
	"kind": "Deployment",
	"metadata": {"name": "unlabelled", "labels": {}},
}

_non_workload_kind := {
	"kind": "ConfigMap",
	"metadata": {"name": "my-config", "labels": {}},
}

test_compliant_no_violations if {
	count(deny) == 0 with input as _compliant_deployment
}

test_missing_one_label_one_violation if {
	msgs := deny with input as _missing_one
	count(msgs) == 1
	some m in msgs
	contains(m, "cost_center")
}

test_missing_all_labels_four_violations if {
	msgs := deny with input as _missing_all
	count(msgs) == 4
}

test_non_workload_kind_not_checked if {
	count(deny) == 0 with input as _non_workload_kind
}
