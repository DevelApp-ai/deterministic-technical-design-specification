# policies/kubernetes/deny_missing_resource_limits_test.rego
#
# Unit tests for K8S-002 — CPU and Memory Limits Required.

package kubernetes.resources

import rego.v1

_compliant := {
	"kind": "Deployment",
	"metadata": {"name": "dtds-docs"},
	"spec": {"template": {"spec": {"containers": [{
		"name": "docs",
		"resources": {
			"requests": {"cpu": "50m", "memory": "64Mi"},
			"limits": {"cpu": "100m", "memory": "128Mi"},
		},
	}]}}},
}

_no_cpu_limit := {
	"kind": "Deployment",
	"metadata": {"name": "no-cpu"},
	"spec": {"template": {"spec": {"containers": [{
		"name": "app",
		"resources": {"limits": {"memory": "128Mi"}},
	}]}}},
}

_no_memory_limit := {
	"kind": "Deployment",
	"metadata": {"name": "no-mem"},
	"spec": {"template": {"spec": {"containers": [{
		"name": "app",
		"resources": {"limits": {"cpu": "100m"}},
	}]}}},
}

_no_limits := {
	"kind": "Deployment",
	"metadata": {"name": "no-limits"},
	"spec": {"template": {"spec": {"containers": [{"name": "app"}]}}},
}

test_compliant_no_violations if {
	count(deny) == 0 with input as _compliant
}

test_missing_cpu_limit_denied if {
	msgs := deny with input as _no_cpu_limit
	count(msgs) == 1
	some m in msgs
	contains(m, "resources.limits.cpu")
}

test_missing_memory_limit_denied if {
	msgs := deny with input as _no_memory_limit
	count(msgs) == 1
	some m in msgs
	contains(m, "resources.limits.memory")
}

test_no_limits_two_violations if {
	msgs := deny with input as _no_limits
	count(msgs) == 2
}
