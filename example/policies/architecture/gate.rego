# policies/architecture/gate.rego
#
# Boundary gate — fails a boundary-affecting change that lacks a linked ADR.
#
# Input: the ADR catalog (docs/generated/architecture-catalog.json) extended
# with the pull request's change set:
#
#   {
#     "adrs": [...], "policies": [...], "requirements": [...], "scan": {...},
#     "changedPaths": ["terraform/main.tf", "policies/architecture/gate.rego"],
#     "adrLinks":   ["ADR-0001", "ADR-0012"]
#   }
#
# Matching semantics (deliberately simple, deterministic):
#   a changed path is governed by an Accepted ADR when the path equals one of
#   the ADR's governs entries, or starts with a governs entry that ends in
#   "/" (a directory prefix).
#
# Convention: a pull request links an ADR by citing its id (ADR-####) in the
# PR description; the gate input carries the extracted ids in adrLinks.
#
# Findings (all ERROR — the gate is blocking by design):
#   gate/boundary-change-without-adr  a governed path changed, but none of its
#                                     governing ADRs is linked by the PR
#   gate/unknown-adr-link              the PR cites an ADR that does not exist
#   gate/superseded-adr-link          the PR cites a superseded ADR — cite its
#                                     current successor instead (named in the
#                                     finding, traversed by chain.rego)
#
# Run:
#   opa eval --data policies/architecture/ \
#            --input <gate-input.json> \
#            'data.architecture.gate.report'

package architecture.gate

import data.architecture.chain

import rego.v1

__rego__metadoc__ := {
	"id": "ARCH-003",
	"title": "Boundary Gate for Pull Requests",
	"description": "Blocks a boundary-affecting change whose pull request links none of the governing ADRs; redirects superseded ADR links to their current successor.",
	"severity": "CRITICAL",
	"remediation": "Cite the governing ADR id (ADR-####) named in the finding in the pull request description.",
	"related_adr": ["ADR-0012"],
	"related_requirements": ["S-006", "M-005", "D-001"],
}

# ---------------------------------------------------------------------------
# Catalog indexes (defined locally so the gate is self-contained)
# ---------------------------------------------------------------------------

accepted_governs[id] := patterns if {
	some a in input.adrs
	a.status == "Accepted"
	id := a.id
	patterns := a.governs
}

adr_ids := {a.id | some a in input.adrs}

adr_file(id) := a.file if {
	some a in input.adrs
	a.id == id
}

# ---------------------------------------------------------------------------
# Governs matching
# ---------------------------------------------------------------------------

# A governs pattern matches a path exactly, or as a directory prefix
# (pattern ending in "/").
pattern_matches(pattern, path) if {
	pattern == path
}

pattern_matches(pattern, path) if {
	endswith(pattern, "/")
	startswith(path, pattern)
}

# Sorted ids of every Accepted ADR governing the path.
governing(path) := sort([id |
	some id, patterns in accepted_governs
	some p in patterns
	pattern_matches(p, path)
])

# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------

# A boundary-affecting change with no linked governing ADR is blocked.  The
# finding cites the governing ADRs and their files, so the author knows
# exactly which decisions to cite in the PR description.
findings contains f if {
	some i, path in input.changedPaths
	gov := governing(path)
	count(gov) > 0
	not any_linked(gov)
	f := {
		"severity": "ERROR",
		"rule": "gate/boundary-change-without-adr",
		"message": sprintf("changed path '%v' is governed by %v, but the pull request links none of them — cite the governing ADR id(s) in the PR description", [path, governing_description(gov)]),
		"path": sprintf("$.changedPaths[%d]", [i]),
	}
}

any_linked(gov) if {
	some g in gov
	g in input.adrLinks
}

governing_description(gov) := concat("; ", [sprintf("%v (%v)", [g, adr_file(g)]) | some g in gov])

# A linked ADR that does not exist in the catalog.
findings contains f if {
	some i, link in input.adrLinks
	not link in adr_ids
	f := {
		"severity": "ERROR",
		"rule": "gate/unknown-adr-link",
		"message": sprintf("the pull request links %v, but the ADR catalog declares no such ADR — check the id", [link]),
		"path": sprintf("$.adrLinks[%d]", [i]),
	}
}

# A linked ADR that is superseded — the chain traversal names the successor.
findings contains f if {
	some i, link in input.adrLinks
	link in adr_ids
	successor := chain.successor(link)
	f := {
		"severity": "ERROR",
		"rule": "gate/superseded-adr-link",
		"message": sprintf("the pull request links %v, which is superseded — link its current successor %v instead (%v)", [link, successor, adr_file(successor)]),
		"path": sprintf("$.adrLinks[%d]", [i]),
	}
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

all_findings := [f | some f in findings]

error_count := count([f | some f in findings; f.severity == "ERROR"])

report := {
	"valid": error_count == 0,
	"finding_count": count(all_findings),
	"findings": sort(all_findings),
}
