# policies/kubernetes/deny_unpinned_image_tag_test.rego
#
# Unit tests for K8S-004 — No Unpinned Container Image Tags.
# Run with: opa test policies/kubernetes/ -v

package kubernetes.supply_chain_test

import data.kubernetes.supply_chain
import rego.v1

# ---------------------------------------------------------------------------
# Fixtures — Deployment wrappers
# ---------------------------------------------------------------------------

_deployment(containers) := {
	"kind":     "Deployment",
	"metadata": {"name": "test-app"},
	"spec":     {"template": {"spec": {"containers": containers}}},
}

_statefulset(containers) := {
	"kind":     "StatefulSet",
	"metadata": {"name": "test-db"},
	"spec":     {"template": {"spec": {"containers": containers}}},
}

_pod(containers) := {
	"kind":     "Pod",
	"metadata": {"name": "test-pod"},
	"spec":     {"containers": containers},
}

_container(name, image) := {"name": name, "image": image}

# ---------------------------------------------------------------------------
# Rule 1: Untagged images denied
# ---------------------------------------------------------------------------

test_bare_image_name_denied if {
	manifest := _deployment([_container("app", "nginx")])
	msgs := supply_chain.deny with input as manifest
	count(msgs) == 1
	some msg in msgs
	contains(msg, "K8S-004")
	contains(msg, "no tag")
}

test_registry_image_no_tag_denied if {
	manifest := _deployment([_container("app", "gcr.io/org/myapp")])
	msgs := supply_chain.deny with input as manifest
	count(msgs) == 1
	some msg in msgs
	contains(msg, "K8S-004")
}

# ---------------------------------------------------------------------------
# Rule 2: :latest tag denied
# ---------------------------------------------------------------------------

test_explicit_latest_tag_denied if {
	manifest := _deployment([_container("app", "nginx:latest")])
	msgs := supply_chain.deny with input as manifest
	count(msgs) == 1
	some msg in msgs
	contains(msg, "K8S-004")
	contains(msg, "latest")
}

test_registry_latest_tag_denied if {
	manifest := _deployment([_container("app", "registry.io/org/nginx:latest")])
	msgs := supply_chain.deny with input as manifest
	count(msgs) == 1
	some msg in msgs
	contains(msg, "K8S-004")
}

# ---------------------------------------------------------------------------
# Compliant image references pass
# ---------------------------------------------------------------------------

test_semver_tag_passes if {
	manifest := _deployment([_container("app", "nginx:1.25.3")])
	count(supply_chain.deny) == 0 with input as manifest
}

test_registry_semver_tag_passes if {
	manifest := _deployment([_container("app", "registry.io/org/nginx:1.25.3")])
	count(supply_chain.deny) == 0 with input as manifest
}

test_digest_pinned_image_passes if {
	# Image with semver tag AND digest — gold standard
	manifest := _deployment([_container("app", "nginx:1.25.3@sha256:abc123def456")])
	count(supply_chain.deny) == 0 with input as manifest
}

test_digest_only_image_passes if {
	# Digest-only reference is safe even without a tag
	manifest := _deployment([_container("app", "nginx@sha256:abc123def456")])
	count(supply_chain.deny) == 0 with input as manifest
}

# ---------------------------------------------------------------------------
# Workload kind coverage
# ---------------------------------------------------------------------------

test_statefulset_latest_denied if {
	manifest := _statefulset([_container("db", "postgres:latest")])
	msgs := supply_chain.deny with input as manifest
	count(msgs) == 1
	some msg in msgs
	contains(msg, "K8S-004")
}

test_pod_untagged_denied if {
	manifest := _pod([_container("sidecar", "envoy")])
	msgs := supply_chain.deny with input as manifest
	count(msgs) == 1
	some msg in msgs
	contains(msg, "K8S-004")
}

# ---------------------------------------------------------------------------
# Multiple containers — violations counted per container
# ---------------------------------------------------------------------------

test_multiple_containers_violations_counted if {
	manifest := _deployment([
		_container("app", "myapp:1.0.0"),        # compliant
		_container("sidecar", "envoy:latest"),    # violates Rule 2
		_container("init", "busybox"),            # violates Rule 1
	])
	count(supply_chain.deny) == 2 with input as manifest
}
