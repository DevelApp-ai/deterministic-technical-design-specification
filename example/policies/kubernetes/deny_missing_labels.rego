# policies/kubernetes/deny_missing_labels.rego
#
# K8S-003 — Required FinOps Labels on All Workloads
# ===================================================
# Blocks Kubernetes resources that are missing the four mandatory
# cost-allocation labels.  Mirrors the FINOPS-001 Terraform policy for
# the Kubernetes plane.

package kubernetes.finops

import rego.v1

__rego__metadoc__ := {
	"id": "K8S-003",
	"title": "Required FinOps Labels on All Workloads",
	"description": "All Kubernetes workloads must carry the four mandatory cost-allocation labels: environment, app_name, owner, cost_center.",
	"severity": "HIGH",
	"related_adr": ["ADR-0008"],
	"related_requirements": ["K-003", "FIN-001", "M-002"],
}

_required_labels := {"environment", "app_name", "owner", "cost_center"}

_labelled_kinds := {
	"Deployment", "StatefulSet", "DaemonSet",
	"Pod", "Job", "CronJob", "Service", "Namespace",
}

deny contains msg if {
	input.kind in _labelled_kinds
	some label in _required_labels
	not input.metadata.labels[label]
	msg := sprintf(
		"K8S-003: %v '%v' is missing required label '%v'",
		[input.kind, input.metadata.name, label],
	)
}
