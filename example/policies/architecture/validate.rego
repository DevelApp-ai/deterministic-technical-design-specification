# policies/architecture/validate.rego
#
# Catalog validation — loud findings over the machine-readable ADR catalog
# produced by scripts/scan-architecture.py
# (docs/generated/architecture-catalog.json).
#
# Every finding carries a severity, a rule name, a human message, and a JSON
# path back into the catalog document, so a failing PR can cite exactly what
# is wrong and where.
#
# Rules enforced (all ERROR):
#   catalog/duplicate-adr-id            two ADRs share one id
#   catalog/unknown-supersedes-ref      supersedes references an unknown ADR id
#   catalog/supersede-cycle             a supersede chain loops back on itself
#   catalog/ambiguous-supersede-chain   a chain has zero or several terminal ADRs
#   catalog/chain-depth-exceeded        a chain is still growing at the 8-hop cap
#   catalog/status-superseded-unmatched status Superseded but nothing supersedes it
#   catalog/superseded-but-accepted     something supersedes it but status is not Superseded
#   catalog/adr-without-requirements    an Accepted ADR cites no MoSCoW requirement
#   catalog/adr-without-governs         an Accepted ADR declares no governed paths
#   catalog/dangling-requirement-ref    ADR cites a requirement id not in the MoSCoW document
#   catalog/duplicate-policy-id        two policies share one metadoc id
#   catalog/policy-unknown-adr          a policy metadoc links an unknown ADR
#   catalog/policy-unknown-requirement  a policy metadoc links an unknown requirement
#   catalog/policy-without-adr         a policy metadoc has no related_adr
#
# Run:
#   opa eval --data policies/architecture/ \
#            --input docs/generated/architecture-catalog.json \
#            'data.architecture.validate.report'

package architecture.validate

import data.architecture.chain

import rego.v1

__rego__metadoc__ := {
	"id": "ARCH-001",
	"title": "ADR Catalog Validation",
	"description": "Validates the machine-readable ADR catalog (ids, supersede chains, requirement refs, policy links, governed paths) with loud findings that carry rule names and JSON paths.",
	"severity": "HIGH",
	"remediation": "Fix the cited ADR front-matter or policy metadoc field; rescan with scripts/scan-architecture.py.",
	"related_adr": ["ADR-0012"],
	"related_requirements": ["S-006", "M-005", "D-001"],
}

# ---------------------------------------------------------------------------
# Indexes over the catalog
# ---------------------------------------------------------------------------

adr_ids := {a.id | some a in input.adrs}

requirement_ids := {r.id | some r in input.requirements}

# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------

# Two ADRs share one id.  Set semantics collapse the identical per-occurrence
# findings into one finding per duplicated id.
findings contains f if {
	some i, a in input.adrs
	instances := [x | some x in input.adrs; x.id == a.id]
	count(instances) > 1
	f := {
		"severity": "ERROR",
		"rule": "catalog/duplicate-adr-id",
		"message": sprintf("ADR id %v is declared in %v — ADR ids must be unique", [a.id, sort([x.file | some x in instances])]),
		"path": sprintf("$.adrs[%d]", [i]),
	}
}

findings contains f if {
	some i, a in input.adrs
	some j, s in a.supersedes
	not s in adr_ids
	f := {
		"severity": "ERROR",
		"rule": "catalog/unknown-supersedes-ref",
		"message": sprintf("ADR %v supersedes %v, but no ADR with id %v exists (%v)", [a.id, s, s, a.file]),
		"path": sprintf("$.adrs[%d].supersedes[%d]", [i, j]),
	}
}

# Cycle: the chain closure starts ABOVE the ADR itself, so the ADR can only
# appear in its own superseders through a cycle.
findings contains f if {
	some i, a in input.adrs
	a.id in chain.chain_superseders(a.id)
	f := {
		"severity": "ERROR",
		"rule": "catalog/supersede-cycle",
		"message": sprintf("ADR %v sits on a supersede cycle — the chain loops back to itself and has no current ADR", [a.id]),
		"path": sprintf("$.adrs[%d].supersedes", [i]),
	}
}

findings contains f if {
	some i, a in input.adrs
	terminals := {m | some m in chain.chain_members(a.id); chain.terminal(m)}
	count(terminals) != 1
	f := {
		"severity": "ERROR",
		"rule": "catalog/ambiguous-supersede-chain",
		"message": sprintf("the supersede chain of ADR %v resolves to %d terminal ADRs (%v) — exactly one current ADR is required", [a.id, count(terminals), sort([t | some t in terminals])]),
		"path": sprintf("$.adrs[%d]", [i]),
	}
}

findings contains f if {
	some i, a in input.adrs
	chain.growing_at_cap(a.id)
	f := {
		"severity": "ERROR",
		"rule": "catalog/chain-depth-exceeded",
		"message": sprintf("the supersede chain of ADR %v is still growing at the 8-hop traversal cap — flatten or split the chain", [a.id]),
		"path": sprintf("$.adrs[%d].supersedes", [i]),
	}
}

findings contains f if {
	some i, a in input.adrs
	a.status == "Superseded"
	count([x | some x in input.adrs; a.id in x.supersedes]) == 0
	f := {
		"severity": "ERROR",
		"rule": "catalog/status-superseded-unmatched",
		"message": sprintf("ADR %v has status Superseded, but no ADR supersedes it — either the successor's supersedes ref is missing or the status is stale", [a.id]),
		"path": sprintf("$.adrs[%d].status", [i]),
	}
}

findings contains f if {
	some i, a in input.adrs
	a.status != "Superseded"
	count([x | some x in input.adrs; a.id in x.supersedes]) > 0
	f := {
		"severity": "ERROR",
		"rule": "catalog/superseded-but-accepted",
		"message": sprintf("ADR %v is superseded by %v but its status is still %v — mark it Superseded", [a.id, sort([x.id | some x in input.adrs; a.id in x.supersedes]), a.status]),
		"path": sprintf("$.adrs[%d].status", [i]),
	}
}

findings contains f if {
	some i, a in input.adrs
	a.status == "Accepted"
	count(a.related_requirements) == 0
	f := {
		"severity": "ERROR",
		"rule": "catalog/adr-without-requirements",
		"message": sprintf("Accepted ADR %v cites no MoSCoW requirement — every decision must trace back to the requirements document (%v)", [a.id, a.file]),
		"path": sprintf("$.adrs[%d].related_requirements", [i]),
	}
}

findings contains f if {
	some i, a in input.adrs
	a.status == "Accepted"
	count(a.governs) == 0
	f := {
		"severity": "ERROR",
		"rule": "catalog/adr-without-governs",
		"message": sprintf("Accepted ADR %v declares no governed paths — the boundary gate cannot protect a decision with no territory (%v)", [a.id, a.file]),
		"path": sprintf("$.adrs[%d].governs", [i]),
	}
}

findings contains f if {
	some i, a in input.adrs
	some j, r in a.related_requirements
	not r in requirement_ids
	f := {
		"severity": "ERROR",
		"rule": "catalog/dangling-requirement-ref",
		"message": sprintf("ADR %v cites requirement %v, but the MoSCoW document declares no such requirement (%v)", [a.id, r, a.file]),
		"path": sprintf("$.adrs[%d].related_requirements[%d]", [i, j]),
	}
}

findings contains f if {
	some i, p in input.policies
	instances := [x | some x in input.policies; x.id == p.id]
	count(instances) > 1
	f := {
		"severity": "ERROR",
		"rule": "catalog/duplicate-policy-id",
		"message": sprintf("policy id %v is declared in %v — policy metadoc ids must be unique", [p.id, sort([x.file | some x in instances])]),
		"path": sprintf("$.policies[%d]", [i]),
	}
}

findings contains f if {
	some i, p in input.policies
	some j, x in p.related_adr
	not x in adr_ids
	f := {
		"severity": "ERROR",
		"rule": "catalog/policy-unknown-adr",
		"message": sprintf("policy %v links ADR %v, but no ADR with that id exists (%v)", [p.id, x, p.file]),
		"path": sprintf("$.policies[%d].related_adr[%d]", [i, j]),
	}
}

findings contains f if {
	some i, p in input.policies
	some j, r in p.related_requirements
	not r in requirement_ids
	f := {
		"severity": "ERROR",
		"rule": "catalog/policy-unknown-requirement",
		"message": sprintf("policy %v links requirement %v, but the MoSCoW document declares no such requirement (%v)", [p.id, r, p.file]),
		"path": sprintf("$.policies[%d].related_requirements[%d]", [i, j]),
	}
}

findings contains f if {
	some i, p in input.policies
	count(p.related_adr) == 0
	f := {
		"severity": "ERROR",
		"rule": "catalog/policy-without-adr",
		"message": sprintf("policy %v links no ADR — the traceability chain from requirement to policy must pass through a decision (%v)", [p.id, p.file]),
		"path": sprintf("$.policies[%d].related_adr", [i]),
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
