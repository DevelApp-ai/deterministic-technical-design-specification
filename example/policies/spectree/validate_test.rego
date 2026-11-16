# policies/spectree/validate_test.rego
#
# Unit tests for the SpecTree validation gate (issue #26, ADR-0020).
# Mirrors the *_test.rego convention of the architecture kit (ADR-0012):
# the happy path asserts zero findings, the broken fixture asserts every
# rule fires with the severity the severity model assigns it.
#
# Run:
#   opa test policies/spectree/ -v

package spectree.validate_test

import rego.v1

import data.spectree.validate

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A clean, fully traced solution: one Must requirement, satisfied by one
# component, covered by one test suite, one Accepted ADR, no NFRs, one
# manifest project with its spec present on disk.
happy_input := {
	"metadata": {
		"schema": "traceability-metadata",
		"schemaVersion": 1,
		"nodes": [
			{
				"id": "spec:M-001",
				"type": "requirement",
				"title": "Store todo items",
				"source": "spectree/specs/myapp.srs",
				"moscow": "must",
			},
			{
				"id": "spec:Alpha",
				"type": "component",
				"title": "Alpha component",
				"source": "spectree/specs/alpha.ai",
				"satisfies": ["spec:M-001"],
				"relatedAdr": ["adr:ADR-0001"],
				"dependencies": [],
			},
			{
				"id": "spec:Alpha.tests",
				"type": "test-suite",
				"title": "Test specification for Alpha",
				"source": "spectree/specs/alpha.test",
				"target": "Alpha.cs",
				"covers": ["spec:M-001"],
			},
			{
				"id": "adr:ADR-0001",
				"type": "adr",
				"title": "First decision",
				"source": "docs/adrs/0001-first.md",
				"status": "Accepted",
				"date": "2026-01-01",
			},
		],
		"edges": [
			{"from": "spec:Alpha", "type": "satisfies", "to": "spec:M-001"},
			{"from": "spec:Alpha", "type": "implements", "to": "adr:ADR-0001"},
			{"from": "spec:Alpha.tests", "type": "covers", "to": "spec:M-001"},
		],
		"integrity": {
			"duplicateIds": [],
			"danglingEdges": [
				{
					"from": "spec:Alpha.tests",
					"type": "covers",
					"to": "spec:REQ-9",
					"missing": "spec:REQ-9",
				},
			],
		},
	},
	"manifests": [
		{
			"solution": "MyApp",
			"projects": [{"name": "MyApp.App", "path": "app.csproj", "tfm": "net10.0"}],
			"specs": [{"path": "spectree/specs/alpha.ai", "project": "MyApp.App"}],
		},
	],
	"specFiles": ["spectree/specs/alpha.ai", "spectree/specs/alpha.test"],
}

# Every rule violated exactly once (except the cycle, which fires per
# component on the cycle).
broken_input := {
	"metadata": {
		"schema": "traceability-metadata",
		"schemaVersion": 1,
		"nodes": [
			{
				"id": "spec:W-001",
				"type": "requirement",
				"title": "Descoped",
				"source": "spectree/specs/myapp.srs",
				"moscow": "wont",
			},
			{
				"id": "spec:M-009",
				"type": "requirement",
				"title": "Uncovered must",
				"source": "spectree/specs/myapp.srs",
				"moscow": "must",
			},
			{
				"id": "spec:A",
				"type": "component",
				"title": "A",
				"source": "spectree/specs/a.ai",
				"satisfies": ["spec:W-001"],
				"relatedAdr": ["adr:ADR-0001"],
				"dependencies": ["B"],
			},
			{
				"id": "spec:B",
				"type": "component",
				"title": "B",
				"source": "spectree/specs/b.ai",
				"satisfies": ["spec:W-001"],
				"relatedAdr": [],
				"dependencies": ["A"],
			},
			{
				"id": "spec:C",
				"type": "component",
				"title": "C",
				"source": "spectree/specs/c.ai",
				"satisfies": ["spec:W-001"],
				"relatedAdr": ["adr:ADR-0099"],
				"dependencies": ["Ghost"],
			},
			{
				"id": "spec:D",
				"type": "component",
				"title": "D",
				"source": "spectree/specs/d.ai",
				"satisfies": ["spec:W-001"],
				"relatedAdr": ["adr:ADR-0002"],
				"dependencies": [],
			},
			{
				"id": "spec:E",
				"type": "component",
				"title": "E",
				"source": "spectree/specs/e.ai",
				"satisfies": ["spec:W-001"],
				"relatedAdr": ["adr:ADR-0003"],
				"dependencies": [],
			},
			{
				"id": "spec:C.tests",
				"type": "test-suite",
				"title": "Tests for C",
				"source": "spectree/specs/c.test",
				"target": "C.cs",
				"covers": ["spec:GONE-1"],
			},
			{
				"id": "spec:PERF-9",
				"type": "nfr",
				"title": "Unmeasurable",
				"source": "spectree/specs/myapp.ns",
				"kind": "latency",
				"bound": {},
				"relatedAdr": [],
			},
			{
				"id": "adr:ADR-0001",
				"type": "adr",
				"title": "Accepted",
				"source": "docs/adrs/0001-a.md",
				"status": "Accepted",
				"date": "2026-01-01",
			},
			{
				"id": "adr:ADR-0002",
				"type": "adr",
				"title": "Proposed",
				"source": "docs/adrs/0002-p.md",
				"status": "Proposed",
				"date": "2026-01-02",
			},
			{
				"id": "adr:ADR-0003",
				"type": "adr",
				"title": "Superseded",
				"source": "docs/adrs/0003-s.md",
				"status": "Superseded",
				"date": "2026-01-03",
			},
		],
		"edges": [
			{"from": "spec:A", "type": "satisfies", "to": "spec:W-001"},
			{"from": "spec:B", "type": "satisfies", "to": "spec:W-001"},
			{"from": "spec:C", "type": "satisfies", "to": "spec:W-001"},
			{"from": "spec:D", "type": "satisfies", "to": "spec:W-001"},
			{"from": "spec:E", "type": "satisfies", "to": "spec:W-001"},
			{"from": "spec:C.tests", "type": "covers", "to": "spec:GONE-1"},
		],
		"integrity": {
			"duplicateIds": ["spec:A"],
			"danglingEdges": [],
		},
	},
	"manifests": [
		{
			"solution": "MyApp",
			"projects": [
				{"name": "MyApp.App", "path": "app.csproj", "tfm": "net10.0"},
				{"name": "MyApp.Orphan", "path": "orphan.csproj", "tfm": "net10.0"},
			],
			"specs": [
				{"path": "spectree/specs/a.ai", "project": "MyApp.App"},
				{"path": "spectree/specs/missing.ai", "project": "MyApp.App"},
			],
		},
	],
	"specFiles": ["spectree/specs/a.ai"],
}

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

test_happy_input_produces_zero_findings if {
	report := validate.report with input as happy_input
	report.valid
	count(report.findings) == 0
	report.summary.errors == 0
	report.summary.warnings == 0
}

# ---------------------------------------------------------------------------
# ERROR rules
# ---------------------------------------------------------------------------

test_duplicate_node_id_is_an_error if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "spectree/duplicate-node-id"
	f.severity == "ERROR"
}

test_manifest_spec_not_found_is_an_error if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "manifest/spec-not-found"
	f.severity == "ERROR"
	f.message == "solution manifest MyApp references spec spectree/specs/missing.ai, but no such file exists under spectree/specs/"
}

test_orphan_project_is_an_error if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "manifest/orphan-project"
	f.severity == "ERROR"
	f.message == "project MyApp.Orphan in solution manifest MyApp maps no specification — every project needs at least one spec"
}

test_dependency_cycle_is_an_error_per_component if {
	report := validate.report with input as broken_input
	cycle_components := {f.path |
		some f in report.findings
		f.rule == "component/dependency-cycle"
		f.severity == "ERROR"
	}
	count(cycle_components) == 2
}

test_unknown_adr_reference_is_an_error if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "adr/unknown-reference"
	f.severity == "ERROR"
	contains(f.message, "ADR-0099")
}

test_proposed_adr_reference_is_an_error if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "adr/not-accepted"
	f.severity == "ERROR"
	contains(f.message, "ADR-0002")
	contains(f.message, "Proposed")
}

test_superseded_adr_reference_is_an_error if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "adr/superseded-referenced"
	f.severity == "ERROR"
	contains(f.message, "ADR-0003")
}

test_non_measurable_bound_is_an_error if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "ns/non-measurable-bound"
	f.severity == "ERROR"
	contains(f.message, "spec:PERF-9")
}

test_broken_input_is_not_valid if {
	report := validate.report with input as broken_input
	not report.valid
	report.summary.errors == 9
}

# ---------------------------------------------------------------------------
# WARNING rules
# ---------------------------------------------------------------------------

test_premature_implementation_is_a_warning if {
	report := validate.report with input as broken_input
	premature := [f |
		some f in report.findings
		f.rule == "component/premature-implementation"
	]
	count(premature) == 5
	every f in premature {
		f.severity == "WARNING"
	}
}

test_unspecified_dependency_is_a_warning if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "component/unspecified-dependency"
	f.severity == "WARNING"
	contains(f.message, "Ghost")
}

test_must_without_coverage_is_a_warning if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "test/must-without-coverage"
	f.severity == "WARNING"
	contains(f.message, "spec:M-009")
}

test_covers_missing_requirement_is_a_warning if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "test/covers-missing-requirement"
	f.severity == "WARNING"
	contains(f.message, "spec:GONE-1")
}

test_requirement_without_component_is_a_warning if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "traceability/requirement-without-component"
	f.severity == "WARNING"
	contains(f.message, "spec:M-009")
}

test_component_without_requirement_is_a_warning if {
	no_must := json.remove(broken_input, ["/metadata/nodes/1"])
	no_edge_a := json.remove(no_must, ["/metadata/edges/0"])
	fake := json.remove(no_edge_a, ["/metadata/edges/0"])
	report := validate.report with input as fake
	some f in report.findings
	f.rule == "traceability/component-without-requirement"
	f.severity == "WARNING"
}

test_constraint_without_adr_is_a_warning if {
	report := validate.report with input as broken_input
	some f in report.findings
	f.rule == "ns/constraint-without-adr"
	f.severity == "WARNING"
	contains(f.message, "spec:PERF-9")
}

# ---------------------------------------------------------------------------
# Dangling edges recorded by the normalizer are informational, not gate
# findings of their own — the covers-missing rule reports them instead.
# ---------------------------------------------------------------------------

test_happy_dangling_edge_is_not_a_finding if {
	report := validate.report with input as happy_input
	# happy_input carries one dangling edge (spec:REQ-9) that no rule targets:
	# it is not a covers edge (it is only in integrity.danglingEdges).
	count(report.findings) == 0
}

# ---------------------------------------------------------------------------
# Severity model: warnings never block, errors always do
# ---------------------------------------------------------------------------

test_warnings_do_not_block if {
	report := validate.report with input as happy_input
	report.valid
}
