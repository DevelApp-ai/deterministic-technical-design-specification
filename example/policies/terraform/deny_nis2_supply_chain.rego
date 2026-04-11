# policies/terraform/deny_nis2_supply_chain.rego
#
# SC-001 — NIS2 Article 21(2)(d): IaC Dependency Pinning
#
# EU Directive 2022/2555 (NIS2), Article 21(2)(d) requires entities to address
# "security in supply chain" including "security aspects of the relationships
# between each entity and its direct suppliers or service providers".
#
# Infrastructure-as-Code dependencies (Terraform providers and modules) are
# direct software supply chain components.  A mutable or unpinned reference
# means a CI/CD run could silently download a different — potentially compromised
# — artefact than the one reviewed and approved.
#
# This policy enforces the IaC dependency-pinning rules defined in
# docs/compliance/nis2.md §Art.21(2)(d) — Supply Chain Security:
#
#   Rule 1 — Git-sourced modules must declare an explicit `?ref=` parameter.
#             Absence of `?ref=` resolves to the default branch HEAD,
#             giving an attacker who can push to that branch control over
#             what code is executed in the pipeline.
#
#   Rule 2 — Git-sourced module `?ref=` must not point to a mutable branch.
#             Refs such as `main`, `master`, `HEAD`, `develop`, or `trunk` are
#             mutable — a force-push rewrites the history the ref resolves to.
#             Only version tags (e.g. `v1.3.0`) are immutable and auditable.
#
#   Rule 3 — Registry module version constraints must not be absent.
#             A missing `version` attribute in a registry module call downloads
#             the latest available version, which is entirely outside the
#             team's control.
#
#   Rule 4 — Registry module version constraints must not be floating.
#             A constraint of `>= X` with no upper bound allows any future
#             version including a malicious one injected via registry compromise.
#             Use `~> X.Y` (pessimistic) or an exact pin instead.
#
#   Rule 5 — Provider version constraints must not be absent.
#             A provider without a `version` constraint uses the latest
#             available version, which is outside the team's control.
#
#   Rule 6 — Provider version constraints must not be floating.
#             Same rationale as Rule 4, applied to provider dependencies.
#
# Input:      terraform plan -json  (input.configuration section)
# Related ADR:          docs/adrs/0010-nis2-compliance.md
# Related requirements: NIS2-007, M-003, S-001
# NIS2:                 Art.21(2)(d) — Supply chain security
# NIST 800-53:          SA-12 (Supply Chain Protection), SA-15 (Dev Security)
# CIS Supply Chain:     SLSA Level 2+

package terraform.supply_chain

import rego.v1

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------

__rego__metadoc__ := {
	"id":    "SC-001",
	"title": "NIS2 Art.21(2)(d) — IaC Dependency Pinning",
	"description": "Terraform module and provider dependencies must be pinned to immutable, verifiable references. Git-sourced modules must use a semver tag ref (not main/master/HEAD); registry modules and providers must declare non-floating version constraints. Floating or absent constraints allow silent supply chain substitution.",
	"severity": "HIGH",
	"remediation": "1) Add ?ref=vX.Y.Z to git module sources. 2) Replace ?ref=main/master/HEAD with a semver tag. 3) Add version = \"~> X.Y\" to registry module calls. 4) Replace >= X constraints with ~> X.Y on modules and providers.",
	"related_adr":          ["ADR-0010", "ADR-0002"],
	"related_requirements": ["NIS2-007", "M-003", "S-001"],
	"compliance": {
		"nis2":        ["Art.21(2)(d)"],
		"nist_800_53": ["SA-12", "SA-15"],
	},
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Mutable branch names that must not be used as module ref values.
_mutable_refs := {"main", "master", "HEAD", "develop", "trunk", "latest"}

# Detect a git-sourced module by common URL prefixes.
_is_git_source(source) if startswith(source, "git::")

_is_git_source(source) if startswith(source, "github.com/")

_is_git_source(source) if startswith(source, "gitlab.com/")

_is_git_source(source) if startswith(source, "bitbucket.org/")

# A version constraint is "floating" when it uses >= with no upper bound.
# A lower-bound-only constraint allows any future version, including a
# compromised one.  Acceptable forms: exact pin ("2.5.0"), pessimistic
# constraint ("~> 2.5"), or bounded range (">= 2.0, < 3.0").
_is_floating_constraint(constraint) if {
	contains(constraint, ">=")
	not contains(constraint, "<")
}

# Extract the ?ref= value from a git module source URI.
# Returns an empty string when no ?ref= parameter is present.
_git_ref(source) := ref if {
	contains(source, "?ref=")
	parts := split(source, "?ref=")
	ref_and_rest := parts[1]
	ref := split(ref_and_rest, "&")[0]
}

_git_ref(source) := "" if {
	not contains(source, "?ref=")
}

# ---------------------------------------------------------------------------
# Rule 1 — Git module source has no ?ref= parameter
# ---------------------------------------------------------------------------
deny contains msg if {
	module := input.configuration.root_module.module_calls[name]
	_is_git_source(module.source)
	_git_ref(module.source) == ""
	msg := sprintf(
		"[SC-001] Terraform module '%s' uses git source '%s' with no ?ref= parameter. Add ?ref=vX.Y.Z to pin to an immutable semver tag and satisfy NIS2 Art.21(2)(d) supply chain requirements.",
		[name, module.source],
	)
}

# ---------------------------------------------------------------------------
# Rule 2 — Git module source uses a mutable branch ref
# ---------------------------------------------------------------------------
deny contains msg if {
	module := input.configuration.root_module.module_calls[name]
	_is_git_source(module.source)
	ref := _git_ref(module.source)
	ref != ""
	ref in _mutable_refs
	msg := sprintf(
		"[SC-001] Terraform module '%s' uses git source with mutable ref '?ref=%s'. Replace with an immutable semver tag (e.g. ?ref=v1.3.0) to satisfy NIS2 Art.21(2)(d) supply chain requirements.",
		[name, ref],
	)
}

# ---------------------------------------------------------------------------
# Rule 3 — Registry module has no version constraint
# ---------------------------------------------------------------------------
deny contains msg if {
	module := input.configuration.root_module.module_calls[name]
	not _is_git_source(module.source)
	constraint := object.get(module, "version_constraint", "")
	constraint == ""
	msg := sprintf(
		"[SC-001] Terraform module '%s' (source: '%s') has no version constraint. Add version = \"~> X.Y\" to pin the module and prevent silent supply chain substitution (NIS2 Art.21(2)(d)).",
		[name, module.source],
	)
}

# ---------------------------------------------------------------------------
# Rule 4 — Registry module has a floating version constraint
# ---------------------------------------------------------------------------
deny contains msg if {
	module := input.configuration.root_module.module_calls[name]
	not _is_git_source(module.source)
	constraint := object.get(module, "version_constraint", "")
	constraint != ""
	_is_floating_constraint(constraint)
	msg := sprintf(
		"[SC-001] Terraform module '%s' uses floating version constraint '%s'. Replace with a pessimistic constraint (~> X.Y) or exact pin to satisfy NIS2 Art.21(2)(d) supply chain requirements.",
		[name, constraint],
	)
}

# ---------------------------------------------------------------------------
# Rule 5 — Provider has no version constraint
# ---------------------------------------------------------------------------
deny contains msg if {
	provider_cfg := input.configuration.root_module.provider_config[provider_name]
	constraint := object.get(provider_cfg, "version_constraint", "")
	constraint == ""
	msg := sprintf(
		"[SC-001] Terraform provider '%s' has no version constraint. Add version = \"~> X.Y\" in required_providers to pin the provider and prevent silent supply chain substitution (NIS2 Art.21(2)(d)).",
		[provider_name],
	)
}

# ---------------------------------------------------------------------------
# Rule 6 — Provider has a floating version constraint
# ---------------------------------------------------------------------------
deny contains msg if {
	provider_cfg := input.configuration.root_module.provider_config[provider_name]
	constraint := object.get(provider_cfg, "version_constraint", "")
	constraint != ""
	_is_floating_constraint(constraint)
	msg := sprintf(
		"[SC-001] Terraform provider '%s' uses floating version constraint '%s'. Replace with a pessimistic constraint (~> X.Y) or exact pin to satisfy NIS2 Art.21(2)(d) supply chain requirements.",
		[provider_name, constraint],
	)
}
