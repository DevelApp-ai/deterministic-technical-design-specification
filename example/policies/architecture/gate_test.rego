# policies/architecture/gate_test.rego
#
# Unit tests for the ARCH-003 boundary gate.  Run with:
#   opa test policies/architecture/ -v

package architecture.gate_test

import data.architecture.gate
import rego.v1

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

adr(id, status, supersedes, governs) := {
	"id": id,
	"title": sprintf("decision %v", [id]),
	"status": status,
	"date": "2026-01-01",
	"author": "platform-team",
	"tags": [],
	"supersedes": supersedes,
	"related_requirements": ["M-001"],
	"governs": governs,
	"file": sprintf("docs/adrs/%v.md", [id]),
}

gate_input(adrs, changed, links) := {
	"adrs": adrs,
	"policies": [],
	"requirements": [],
	"scan": {"scanner": "fixture"},
	"changedPaths": changed,
	"adrLinks": links,
}

# ADR-0001 governs terraform/; ADR-0003 governs an exact file plus a prefix.
gov_adrs := [
	adr("ADR-0001", "Accepted", [], ["terraform/"]),
	adr("ADR-0003", "Accepted", [], ["policies/exact.rego", "kubernetes/"]),
]

# ADR-0002 supersedes ADR-0001 (both Accepted); 0002 governs other/.
supersede_adrs := [
	adr("ADR-0001", "Accepted", [], ["terraform/"]),
	adr("ADR-0002", "Accepted", ["ADR-0001"], ["other/"]),
]

# ---------------------------------------------------------------------------
# The done-when scenario: a boundary change with no linked ADR is blocked
# ---------------------------------------------------------------------------

test_boundary_change_without_adr_link_is_blocked if {
	report := gate.report with input as gate_input(gov_adrs, ["terraform/main.tf"], [])
	not report.valid
	some f in report.findings
	f.rule == "gate/boundary-change-without-adr"
	contains(f.message, "terraform/main.tf")
	contains(f.message, "ADR-0001")
	contains(f.message, "docs/adrs/ADR-0001.md")
	f.path == "$.changedPaths[0]"
}

test_boundary_change_passes_when_governing_adr_is_linked if {
	report := gate.report with input as gate_input(gov_adrs, ["terraform/main.tf"], ["ADR-0001"])
	report.valid
	report.finding_count == 0
}

# ---------------------------------------------------------------------------
# Matching semantics: exact file and directory prefix
# ---------------------------------------------------------------------------

test_exact_file_pattern_matches_only_that_file if {
	report := gate.report with input as gate_input(gov_adrs, ["policies/exact.rego"], [])
	not report.valid
	some f in report.findings
	contains(f.message, "ADR-0003")
}

test_prefix_without_trailing_slash_is_not_a_directory_match if {
	report := gate.report with input as gate_input(gov_adrs, ["policies/other.rego"], [])
	report.valid
	report.finding_count == 0
}

test_directory_prefix_matches_any_file_below_it if {
	report := gate.report with input as gate_input(gov_adrs, ["kubernetes/apps/deployment.yaml"], [])
	not report.valid
	some f in report.findings
	f.rule == "gate/boundary-change-without-adr"
}

# ---------------------------------------------------------------------------
# An unrelated link alongside the governing one is allowed
# ---------------------------------------------------------------------------

test_unrelated_link_alongside_governing_passes if {
	report := gate.report with input as gate_input(gov_adrs, ["terraform/main.tf"], ["ADR-0001", "ADR-0003"])
	report.valid
	report.finding_count == 0
}

# ---------------------------------------------------------------------------
# Ungoverned paths pass without any link
# ---------------------------------------------------------------------------

test_ungoverned_change_needs_no_link if {
	report := gate.report with input as gate_input(gov_adrs, ["docs/index.md", "scripts/run.sh"], [])
	report.valid
	report.finding_count == 0
}

# ---------------------------------------------------------------------------
# Non-Accepted ADRs confer no boundary
# ---------------------------------------------------------------------------

test_non_accepted_adr_governs_nothing if {
	proposed := [adr("ADR-0009", "Proposed", [], ["dsc/"])]
	report := gate.report with input as gate_input(proposed, ["dsc/config.mof"], [])
	report.valid
	report.finding_count == 0
}

# ---------------------------------------------------------------------------
# Unknown ADR links are rejected
# ---------------------------------------------------------------------------

test_unknown_adr_link_is_rejected if {
	report := gate.report with input as gate_input(gov_adrs, ["terraform/main.tf"], ["ADR-0001", "ADR-0099"])
	not report.valid
	some f in report.findings
	f.rule == "gate/unknown-adr-link"
	contains(f.message, "ADR-0099")
	f.path == "$.adrLinks[1]"
}

# ---------------------------------------------------------------------------
# Superseded links are redirected to the successor resolved by the chain
# ---------------------------------------------------------------------------

test_superseded_link_is_redirected_to_successor if {
	report := gate.report with input as gate_input(supersede_adrs, ["terraform/main.tf"], ["ADR-0001"])
	not report.valid
	some f in report.findings
	f.rule == "gate/superseded-adr-link"
	contains(f.message, "ADR-0001")
	contains(f.message, "ADR-0002")
	contains(f.message, "docs/adrs/ADR-0002.md")
}

test_superseded_link_fails_even_with_successor_linked if {
	report := gate.report with input as gate_input(supersede_adrs, ["terraform/main.tf"], ["ADR-0001", "ADR-0002"])
	not report.valid
	some f in report.findings
	f.rule == "gate/superseded-adr-link"
}

test_citing_only_the_successor_passes if {
	report := gate.report with input as gate_input(supersede_adrs, ["terraform/main.tf"], ["ADR-0002"])
	not report.valid
	some f in report.findings
	f.rule == "gate/boundary-change-without-adr"
	contains(f.message, "ADR-0001")
}

# ---------------------------------------------------------------------------
# Report shape
# ---------------------------------------------------------------------------

test_report_carries_severity_rule_message_path if {
	report := gate.report with input as gate_input(gov_adrs, ["terraform/main.tf", "kubernetes/svc.yaml"], [])
	not report.valid
	report.finding_count == 2
	every f in report.findings {
		f.severity == "ERROR"
		startswith(f.rule, "gate/")
		startswith(f.path, "$.changedPaths[")
	}
}
