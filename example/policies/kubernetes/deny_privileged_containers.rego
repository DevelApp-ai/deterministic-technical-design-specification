# policies/kubernetes/deny_privileged_containers.rego
#
# K8S-001 — No Privileged Containers
# ====================================
# Blocks any Kubernetes workload (Deployment, StatefulSet, DaemonSet, Pod)
# that runs a container in privileged mode or allows privilege escalation.
#
# __rego__metadoc__ fields are machine-readable and consumed by the
# traceability generator.

package kubernetes.security

import rego.v1

__rego__metadoc__ := {
	"id": "K8S-001",
	"title": "No Privileged Containers",
	"description": "Kubernetes workloads must not run privileged containers or allow privilege escalation.",
	"severity": "CRITICAL",
	"related_adr": ["ADR-0008"],
	"related_requirements": ["K-001", "CYB-002"],
}

# Workload kinds that contain pod specs
_workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"}

# Extract containers from different resource shapes
_containers(resource) := containers if {
	resource.kind in _workload_kinds
	resource.kind != "CronJob"
	containers := resource.spec.template.spec.containers
}

_containers(resource) := containers if {
	resource.kind == "CronJob"
	containers := resource.spec.jobTemplate.spec.template.spec.containers
}

_containers(resource) := containers if {
	resource.kind == "Pod"
	containers := resource.spec.containers
}

# Rule 1: deny privileged containers
deny contains msg if {
	some container in _containers(input)
	container.securityContext.privileged == true
	msg := sprintf(
		"K8S-001: container '%v' in %v '%v' must not be privileged",
		[container.name, input.kind, input.metadata.name],
	)
}

# Rule 2: deny allowPrivilegeEscalation: true (or unset, which defaults to true)
deny contains msg if {
	some container in _containers(input)
	not container.securityContext.allowPrivilegeEscalation == false
	msg := sprintf(
		"K8S-001: container '%v' in %v '%v' must set allowPrivilegeEscalation: false",
		[container.name, input.kind, input.metadata.name],
	)
}
