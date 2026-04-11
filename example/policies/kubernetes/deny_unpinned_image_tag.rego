# policies/kubernetes/deny_unpinned_image_tag.rego
#
# K8S-004 — NIS2 Article 21(2)(d): No Unpinned Container Image Tags
#
# EU Directive 2022/2555 (NIS2), Article 21(2)(d) requires "security in
# supply chain" including software artefact provenance.  Container images
# are a critical supply chain component: an image tagged `:latest` (or
# carrying no tag) resolves to whatever the registry serves at pull time,
# making it impossible to guarantee the same artefact is deployed across
# environments or to reproduce a specific deployment for forensic analysis.
#
# This policy enforces two rules against Kubernetes workload manifests:
#
#   Rule 1 — Container images must carry an explicit tag.
#             A bare image name (e.g. `nginx`) has no tag and is implicitly
#             treated as `:latest` by the container runtime.  Without an
#             explicit identifier an organisation cannot determine which version
#             of the image is running or was running at a given point in time.
#
#   Rule 2 — Container images must not use the `:latest` tag.
#             The `:latest` tag is mutable — the registry may point it at a
#             different image layer at any time including after a supply chain
#             compromise.  Use a semver tag (e.g. `:1.25.3`) or, preferably,
#             a SHA256 digest reference (`image@sha256:<digest>`) for
#             production workloads.
#
# Note: images pinned by SHA256 digest (e.g. `nginx:1.25.3@sha256:<digest>`)
#       satisfy both rules and represent the gold standard for supply chain
#       security.  This policy does not require digest pinning — only that a
#       non-mutable tag is present — to avoid breaking standard registry
#       workflows.  See the NIS2 supply chain section for the digest pinning
#       recommendation.
#
# Input:      Kubernetes manifest (a single resource object per evaluation)
# Related ADR:          docs/adrs/0010-nis2-compliance.md
# Related requirements: NIS2-007, K-001
# NIS2:                 Art.21(2)(d) — Supply chain security
# NIST 800-53:          SA-12 (Supply Chain Protection), CM-11 (User-installed Software)
# CIS Kubernetes:       5.4.1 (prefer digests)

package kubernetes.supply_chain

import rego.v1

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------

__rego__metadoc__ := {
	"id":    "K8S-004",
	"title": "No Unpinned Container Image Tags",
	"description": "Container images in Kubernetes workloads must carry an explicit, non-mutable tag. Untagged images (implicitly :latest) and images explicitly tagged :latest are denied because they make the deployed artefact non-deterministic and non-auditable, violating NIS2 Art.21(2)(d) supply chain security requirements.",
	"severity": "HIGH",
	"remediation": "Replace :latest (or no-tag) image references with an explicit semver tag (e.g. nginx:1.25.3) or a SHA256 digest reference (e.g. nginx:1.25.3@sha256:<digest>).",
	"related_adr":          ["ADR-0010", "ADR-0008"],
	"related_requirements": ["NIS2-007", "K-001"],
	"compliance": {
		"nis2":        ["Art.21(2)(d)"],
		"nist_800_53": ["SA-12", "CM-11"],
	},
}

# ---------------------------------------------------------------------------
# Helpers — workload kinds and container extraction
# ---------------------------------------------------------------------------

_workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"}

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

# Strip the `@<digest>` suffix so that tag detection operates only on
# the registry/name:tag portion of the reference.
# Example: "nginx:1.25.3@sha256:abc" → "nginx:1.25.3"
# Example: "nginx@sha256:abc"         → "nginx"
_base_ref(image) := base if {
	contains(image, "@")
	base := split(image, "@")[0]
}

_base_ref(image) := image if {
	not contains(image, "@")
}

# ---------------------------------------------------------------------------
# Rule 1 — Image has no tag (and no digest — digest-only refs are safe)
# ---------------------------------------------------------------------------
deny contains msg if {
	container := _containers(input)[_]
	image     := container.image
	not contains(image, "@sha256:") # digest-pinned images are acceptable
	base      := _base_ref(image)
	not contains(base, ":") # no colon → no tag
	msg := sprintf(
		"[K8S-004] Container '%v' in %v '%v' uses image '%v' with no tag. Specify an explicit semver tag (e.g. %v:X.Y.Z) to satisfy NIS2 Art.21(2)(d) supply chain requirements.",
		[container.name, input.kind, input.metadata.name, image, image],
	)
}

# ---------------------------------------------------------------------------
# Rule 2 — Image is tagged :latest (mutable reference)
# ---------------------------------------------------------------------------
deny contains msg if {
	container := _containers(input)[_]
	image     := container.image
	base      := _base_ref(image)
	endswith(base, ":latest")
	msg := sprintf(
		"[K8S-004] Container '%v' in %v '%v' uses image '%v' with the ':latest' tag. Replace with an explicit semver tag or digest reference to satisfy NIS2 Art.21(2)(d) supply chain requirements.",
		[container.name, input.kind, input.metadata.name, image],
	)
}
