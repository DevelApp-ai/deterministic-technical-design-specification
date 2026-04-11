# policies/kubernetes/deny_privileged_containers_test.rego
#
# Unit tests for K8S-001 — No Privileged Containers.
# Run with: opa test policies/kubernetes/ -v

package kubernetes.security

import rego.v1

# ── Fixtures ────────────────────────────────────────────────────────────────

_compliant_deployment := {
	"kind": "Deployment",
	"metadata": {"name": "dtds-docs"},
	"spec": {"template": {"spec": {"containers": [{
		"name": "docs",
		"securityContext": {
			"privileged": false,
			"allowPrivilegeEscalation": false,
		},
	}]}}},
}

_privileged_deployment := {
	"kind": "Deployment",
	"metadata": {"name": "bad-app"},
	"spec": {"template": {"spec": {"containers": [{
		"name": "bad",
		"securityContext": {
			"privileged": true,
			"allowPrivilegeEscalation": false,
		},
	}]}}},
}

_escalation_deployment := {
	"kind": "Deployment",
	"metadata": {"name": "esc-app"},
	"spec": {"template": {"spec": {"containers": [{
		"name": "esc",
		"securityContext": {
			"privileged": false,
			"allowPrivilegeEscalation": true,
		},
	}]}}},
}

_no_secctx_deployment := {
	"kind": "Deployment",
	"metadata": {"name": "nosec-app"},
	"spec": {"template": {"spec": {"containers": [{"name": "nosec"}]}}},
}

# ── Tests ────────────────────────────────────────────────────────────────────

test_compliant_deployment_no_violations if {
	count(deny) == 0 with input as _compliant_deployment
}

test_privileged_container_denied if {
	msgs := deny with input as _privileged_deployment
	count(msgs) == 1
	some m in msgs
	contains(m, "must not be privileged")
}

test_privilege_escalation_denied if {
	msgs := deny with input as _escalation_deployment
	count(msgs) == 1
	some m in msgs
	contains(m, "allowPrivilegeEscalation: false")
}

test_missing_security_context_denied if {
	msgs := deny with input as _no_secctx_deployment
	count(msgs) == 1
	some m in msgs
	contains(m, "allowPrivilegeEscalation: false")
}
