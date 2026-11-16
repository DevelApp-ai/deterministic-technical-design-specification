# policies/spectree/validate.rego
#
# SpecTree validation gate — loud findings over the normalized traceability
# metadata contract (ADR-0019) plus the solution-manifest ASTs produced by
# scripts/spectree-parse.py (ADR-0018).
#
# The gate ports the deterministic guarantee of the infrastructure pipeline
# (OPA blocks merge on policy violations) to specification content: rules
# from Minotaur-Grammars #94–#101 are evaluated over the spec graph in CI,
# and ERROR findings block the pull request while WARNING findings surface
# as annotations for gaps that are being closed incrementally.
#
# Every finding carries a severity, a rule name, a human message citing the
# spec file and node id, and a JSON path back into the gate input document.
#
# Rules enforced (ERROR — merge-blocking):
#   spectree/duplicate-node-id          the normalizer recorded duplicate ids
#   manifest/spec-not-found              a manifest spec path has no file
#   manifest/orphan-project              a manifest project maps no spec
#   component/dependency-cycle           component dependencies form a cycle
#   adr/unknown-reference                a spec node references a missing ADR
#   adr/not-accepted                     a spec node references a non-Accepted ADR
#   adr/superseded-referenced            an active spec references a Superseded ADR
#   ns/non-measurable-bound              a perf/scalability NFR lacks a numeric bound
#
# Rules enforced (WARNING — surfaced as annotations, non-blocking):
#   test/must-without-coverage           a Must requirement has no test coverage
#   test/covers-missing-requirement      a test suite covers an undeclared requirement
#   component/premature-implementation   a component satisfies only Won't requirements
#   component/unspecified-dependency     a dependency target has no component spec
#   traceability/requirement-without-component  a requirement no component satisfies
#   traceability/component-without-requirement   a component satisfies no requirement
#   ns/constraint-without-adr            a perf/scalability NFR traces to no ADR
#
# Input shape (assembled by scripts/spectree-gate.sh):
#   {
#     "metadata":  <docs/generated/traceability/metadata-v1.json>,
#     "manifests": [<solution-manifest ast> ...],
#     "specFiles": ["spectree/specs/x.srs", ...]   # files on disk
#   }
#
# Run:
#   opa eval --data policies/spectree/ \
#            --input <gate-input.json> \
#            'data.spectree.validate.report'

package spectree.validate

import rego.v1

__rego__metadoc__ := {
	"id": "SPEC-001",
	"title": "SpecTree Validation Gate",
	"description": "Validates the normalized SpecTree traceability graph (ADR-0019 contract): dependency cycles, orphan manifest projects, missing or non-accepted ADR references, measurable .ns bounds, test coverage of Must requirements, and requirement/component traceability completeness.",
	"severity": "HIGH",
	"remediation": "Fix the cited spec file and node; re-run scripts/normalize-traceability-metadata.py --all and scripts/spectree-gate.sh.",
	"related_adr": ["ADR-0020"],
	"related_requirements": ["S-006", "M-005"],
}

# ---------------------------------------------------------------------------
# Indexes over the normalized graph
# ---------------------------------------------------------------------------

nodes := input.metadata.nodes

node_ids := {n.id | some n in nodes}

components := [n | some n in nodes; n.type == "component"]

requirements := [n | some n in nodes; n.type == "requirement"]

adrs := {n.id: n | some n in nodes; n.type == "adr"}

suites := [n | some n in nodes; n.type == "test-suite"]

edges := input.metadata.edges

spec_files := {f | some f in input.specFiles}

covered_requirements := {e.to | some e in edges; e.type == "covers"}

satisfied_requirements := {e.to | some e in edges; e.type == "satisfies"}

component_name(n) := trim_prefix(n.id, "spec:")

# Component dependency graph, restricted to targets that are themselves
# declared components (undeclared targets get their own warning below).
component_graph[name] contains dep if {
	some c in components
	name := component_name(c)
	some dep in c.dependencies
	some target in components
	component_name(target) == dep
}

component_deps(c) := {dep | some dep in c.dependencies}

component_declared(dep) if {
	some c in components
	component_name(c) == dep
}

requirement_moscow(id) := moscow if {
	some r in requirements
	r.id == id
	moscow := r.moscow
}

satisfied_by(component_id) := {e.to | some e in edges; e.type == "satisfies"; e.from == component_id}

suite_source(suite_id) := src if {
	some s in suites
	s.id == suite_id
	src := s.source
}

measurable_bound(bound) if {
	object.get(bound, "comparator", "") != ""
	object.get(bound, "value", null) != null
	object.get(bound, "unit", "") != ""
}

# ---------------------------------------------------------------------------
# ERROR findings
# ---------------------------------------------------------------------------

# The normalizer fails loudly on duplicates by itself; the gate asserts the
# recorded integrity section so a hand-edited artefact cannot slip through.
findings contains f if {
	some id in input.metadata.integrity.duplicateIds
	f := {
		"severity": "ERROR",
		"rule": "spectree/duplicate-node-id",
		"message": sprintf("node id %v is declared more than once in the normalized graph", [id]),
		"path": "$.metadata.integrity.duplicateIds",
	}
}

# A manifest references a specification file that does not exist.
findings contains f if {
	some mi, m in input.manifests
	some si, s in m.specs
	not s.path in spec_files
	f := {
		"severity": "ERROR",
		"rule": "manifest/spec-not-found",
		"message": sprintf("solution manifest %v references spec %v, but no such file exists under spectree/specs/", [m.solution, s.path]),
		"path": sprintf("$.manifests[%d].specs[%d]", [mi, si]),
	}
}

# A manifest project that maps no specification at all.
findings contains f if {
	some mi, m in input.manifests
	some pi, p in m.projects
	count([s | some s in m.specs; s.project == p.name]) == 0
	f := {
		"severity": "ERROR",
		"rule": "manifest/orphan-project",
		"message": sprintf("project %v in solution manifest %v maps no specification — every project needs at least one spec", [p.name, m.solution]),
		"path": sprintf("$.manifests[%d].projects[%d]", [mi, pi]),
	}
}

# Component dependency cycles (rule from Minotaur-Grammars #96).  The walk
# starts from the component's *direct targets* (graph.reachable includes the
# start set, so starting from the component itself would always "find" it).
component_targets(c) := targets if {
	targets := {dep |
		some dep in c.dependencies
		some target in components
		component_name(target) == dep
	}
}

findings contains f if {
	some i, n in nodes
	n.type == "component"
	name := component_name(n)
	targets := component_targets(n)
	count(targets) > 0
	reachable := graph.reachable(component_graph, targets)
	name in reachable
	f := {
		"severity": "ERROR",
		"rule": "component/dependency-cycle",
		"message": sprintf("%v: component %v sits on a dependency cycle (reachable set %v) — component dependencies must be acyclic", [n.source, n.id, sort(reachable)]),
		"path": sprintf("$.metadata.nodes[%d]", [i]),
	}
}

# Spec nodes may only reference ADRs that exist and are Accepted.  The
# relatedAdr fields of the ADR-0019 contract are already namespace-qualified
# (adr:ADR-####).
findings contains f if {
	some i, n in nodes
	startswith(n.id, "spec:")
	some ref in object.get(n, "relatedAdr", [])
	not ref in node_ids
	f := {
		"severity": "ERROR",
		"rule": "adr/unknown-reference",
		"message": sprintf("%v: node %v references ADR %v, but no ADR with that id exists in docs/adrs/ or the spec ADR sources", [n.source, n.id, trim_prefix(ref, "adr:")]),
		"path": sprintf("$.metadata.nodes[%d].relatedAdr", [i]),
	}
}

findings contains f if {
	some i, n in nodes
	startswith(n.id, "spec:")
	some ref in object.get(n, "relatedAdr", [])
	status := adrs[ref].status
	status != "Accepted"
	status != "Superseded"
	f := {
		"severity": "ERROR",
		"rule": "adr/not-accepted",
		"message": sprintf("%v: node %v references ADR %v with status %v — active specs may only reference Accepted ADRs", [n.source, n.id, trim_prefix(ref, "adr:"), status]),
		"path": sprintf("$.metadata.nodes[%d].relatedAdr", [i]),
	}
}

findings contains f if {
	some i, n in nodes
	startswith(n.id, "spec:")
	some ref in object.get(n, "relatedAdr", [])
	adrs[ref].status == "Superseded"
	f := {
		"severity": "ERROR",
		"rule": "adr/superseded-referenced",
		"message": sprintf("%v: node %v references ADR %v, which is Superseded — reference its current successor instead", [n.source, n.id, trim_prefix(ref, "adr:")]),
		"path": sprintf("$.metadata.nodes[%d].relatedAdr", [i]),
	}
}

# .ns performance/scalability constraints must be measurable (numeric bound
# with comparator, value, and unit).  Security controls are exempt: their
# grammar has no numeric bound slot.
findings contains f if {
	some i, n in nodes
	n.type == "nfr"
	not startswith(n.kind, "security-")
	not measurable_bound(n.bound)
	f := {
		"severity": "ERROR",
		"rule": "ns/non-measurable-bound",
		"message": sprintf("%v: constraint %v declares no measurable numeric bound — .ns constraints must carry comparator, value and unit", [n.source, n.id]),
		"path": sprintf("$.metadata.nodes[%d].bound", [i]),
	}
}

# ---------------------------------------------------------------------------
# WARNING findings
# ---------------------------------------------------------------------------

# A Must requirement that no test suite covers.
findings contains f if {
	some i, n in nodes
	n.type == "requirement"
	startswith(n.id, "spec:")
	n.moscow == "must"
	not n.id in covered_requirements
	f := {
		"severity": "WARNING",
		"rule": "test/must-without-coverage",
		"message": sprintf("%v: Must requirement %v has no .test coverage — every Must requirement needs at least one covering test suite", [n.source, n.id]),
		"path": sprintf("$.metadata.nodes[%d]", [i]),
	}
}

# A test suite covers a requirement id that no source declares.
findings contains f if {
	some j, e in edges
	e.type == "covers"
	not e.to in node_ids
	f := {
		"severity": "WARNING",
		"rule": "test/covers-missing-requirement",
		"message": sprintf("%v: test suite %v covers %v, but no SRS or component spec declares that requirement", [suite_source(e.from), e.from, e.to]),
		"path": sprintf("$.metadata.edges[%d]", [j]),
	}
}

# A component whose satisfied requirements are all Won't — premature
# implementation of descoped work.
findings contains f if {
	some i, n in nodes
	n.type == "component"
	refs := satisfied_by(n.id)
	count(refs) > 0
	every ref in refs {
		requirement_moscow(ref) == "wont"
	}
	f := {
		"severity": "WARNING",
		"rule": "component/premature-implementation",
		"message": sprintf("%v: component %v satisfies only Won't requirements (%v) — premature implementation of descoped work", [n.source, n.id, sort(refs)]),
		"path": sprintf("$.metadata.nodes[%d]", [i]),
	}
}

# A dependency target with no component spec of its own.
findings contains f if {
	some i, n in nodes
	n.type == "component"
	some dep in component_deps(n)
	not component_declared(dep)
	f := {
		"severity": "WARNING",
		"rule": "component/unspecified-dependency",
		"message": sprintf("%v: component %v depends on %v, which has no component spec — undeclared dependencies cannot be validated for cycles or coverage", [n.source, n.id, dep]),
		"path": sprintf("$.metadata.nodes[%d].dependencies", [i]),
	}
}

# Traceability completeness: every requirement maps to >= 1 component.
findings contains f if {
	some i, n in nodes
	n.type == "requirement"
	startswith(n.id, "spec:")
	not n.id in satisfied_requirements
	f := {
		"severity": "WARNING",
		"rule": "traceability/requirement-without-component",
		"message": sprintf("%v: requirement %v is satisfied by no component — every requirement needs at least one implementing component", [n.source, n.id]),
		"path": sprintf("$.metadata.nodes[%d]", [i]),
	}
}

# Traceability completeness: every component maps to >= 1 requirement.
findings contains f if {
	some i, n in nodes
	n.type == "component"
	count(satisfied_by(n.id)) == 0
	f := {
		"severity": "WARNING",
		"rule": "traceability/component-without-requirement",
		"message": sprintf("%v: component %v satisfies no requirement — every component needs at least one requirement link", [n.source, n.id]),
		"path": sprintf("$.metadata.nodes[%d]", [i]),
	}
}

# A .ns perf/scalability constraint that traces to no ADR at all.
findings contains f if {
	some i, n in nodes
	n.type == "nfr"
	not startswith(n.kind, "security-")
	count(object.get(n, "relatedAdr", [])) == 0
	f := {
		"severity": "WARNING",
		"rule": "ns/constraint-without-adr",
		"message": sprintf("%v: constraint %v traces to no ADR — every non-functional constraint should cite the decision that motivates it", [n.source, n.id]),
		"path": sprintf("$.metadata.nodes[%d]", [i]),
	}
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

error_findings := [f | some f in findings; f.severity == "ERROR"]

warning_findings := [f | some f in findings; f.severity == "WARNING"]

report := {
	"valid": count(error_findings) == 0,
	"summary": {
		"errors": count(error_findings),
		"warnings": count(warning_findings),
		"nodes": count(nodes),
		"edges": count(edges),
	},
	"findings": sort([f | some f in findings]),
}
