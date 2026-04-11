# policies/kubernetes/deny_missing_resource_limits.rego
#
# K8S-002 — CPU and Memory Limits Required
# ==========================================
# Blocks any Kubernetes workload (Deployment, StatefulSet, DaemonSet, Pod)
# where a container does not declare both CPU and memory limits.
# Containers without limits can starve neighbouring workloads and generate
# unpredictable cloud spend.

package kubernetes.resources

import rego.v1

__rego__metadoc__ := {
	"id": "K8S-002",
	"title": "CPU and Memory Limits Required",
	"description": "Every container must declare cpu and memory limits to prevent noisy-neighbour issues and runaway cloud cost.",
	"severity": "HIGH",
	"related_adr": ["ADR-0008"],
	"related_requirements": ["K-002", "FIN-001"],
}

_workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Job"}

_containers(resource) := containers if {
	resource.kind in _workload_kinds
	containers := resource.spec.template.spec.containers
}

_containers(resource) := containers if {
	resource.kind == "Pod"
	containers := resource.spec.containers
}

deny contains msg if {
	some container in _containers(input)
	not container.resources.limits.cpu
	msg := sprintf(
		"K8S-002: container '%v' in %v '%v' must declare resources.limits.cpu",
		[container.name, input.kind, input.metadata.name],
	)
}

deny contains msg if {
	some container in _containers(input)
	not container.resources.limits.memory
	msg := sprintf(
		"K8S-002: container '%v' in %v '%v' must declare resources.limits.memory",
		[container.name, input.kind, input.metadata.name],
	)
}
