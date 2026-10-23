# policies/architecture/validate_test.rego
#
# Unit tests for the ARCH-001 catalog validation policy.  Run with:
#   opa test policies/architecture/ -v
#
# Every fixture is a synthetic, minimal catalog; `with input as` stays
# inline in the test rule bodies (house rule).

package architecture.validate_test

import data.architecture.validate
import rego.v1

# ---------------------------------------------------------------------------
# Fixture helpers — minimal catalog objects in the shape scan-architecture.py
# emits.
# ---------------------------------------------------------------------------

adr(id, status, supersedes, reqs, governs) := {
	"id": id,
	"title": sprintf("decision %v", [id]),
	"status": status,
	"date": "2026-01-01",
	"author": "platform-team",
	"tags": [],
	"supersedes": supersedes,
	"related_requirements": reqs,
	"governs": governs,
	"file": sprintf("docs/adrs/%v.md", [id]),
}

policy(id, related_adr, reqs) := {
	"id": id,
	"title": sprintf("policy %v", [id]),
	"severity": "HIGH",
	"package": sprintf("fixture.%v", [id]),
	"related_adr": related_adr,
	"related_requirements": reqs,
	"file": sprintf("policies/%v.rego", [id]),
}

catalog(adrs, policies) := {
	"adrs": adrs,
	"policies": policies,
	"requirements": [{"id": "M-001"}, {"id": "S-006"}, {"id": "D-001"}],
	"scan": {"scanner": "fixture"},
}

# A fully-formed ADR: accepted, requirement-linked, with territory.
good_adr := adr("ADR-0001", "Accepted", [], ["M-001"], ["terraform/"])

# ---------------------------------------------------------------------------
# The clean case — a coherent catalog produces no findings at all
# ---------------------------------------------------------------------------

test_clean_catalog_validates if {
	report := validate.report with input as catalog([good_adr], [policy("POL-001", ["ADR-0001"], ["M-001"])])
	report.valid
	report.finding_count == 0
}

test_findings_carry_rule_severity_and_json_path if {
	report := validate.report with input as catalog([adr("ADR-0001", "Accepted", [], [], [])], [])
	not report.valid
	report.finding_count > 0
	every f in report.findings {
		f.severity == "ERROR"
		startswith(f.rule, "catalog/")
		startswith(f.path, "$.")
		contains(f.message, "ADR-0001")
	}
}

# ---------------------------------------------------------------------------
# catalog/duplicate-adr-id
# ---------------------------------------------------------------------------

fixture_duplicate_adr := catalog(
	[adr("ADR-0001", "Accepted", [], ["M-001"], ["terraform/"]), adr("ADR-0001", "Accepted", [], ["M-001"], ["dsc/"])],
	[],
)

test_duplicate_adr_id_flagged if {
	report := validate.report with input as fixture_duplicate_adr
	not report.valid
	some f in report.findings
	f.rule == "catalog/duplicate-adr-id"
	contains(f.message, "ADR-0001")
}

# ---------------------------------------------------------------------------
# catalog/unknown-supersedes-ref
# ---------------------------------------------------------------------------

fixture_unknown_supersedes := catalog([adr("ADR-0001", "Accepted", ["ADR-0099"], ["M-001"], ["terraform/"])], [])

test_unknown_supersedes_ref_flagged if {
	report := validate.report with input as fixture_unknown_supersedes
	not report.valid
	some f in report.findings
	f.rule == "catalog/unknown-supersedes-ref"
	contains(f.message, "ADR-0099")
	f.path == "$.adrs[0].supersedes[0]"
}

# ---------------------------------------------------------------------------
# catalog/supersede-cycle — a2 supersedes a1, a1 supersedes a2
# ---------------------------------------------------------------------------

fixture_cycle := catalog(
	[
		adr("ADR-0001", "Superseded", ["ADR-0002"], ["M-001"], ["terraform/"]),
		adr("ADR-0002", "Superseded", ["ADR-0001"], ["M-001"], ["dsc/"]),
	],
	[],
)

test_supersede_cycle_flagged if {
	report := validate.report with input as fixture_cycle
	not report.valid
	cycle_findings := [f | some f in report.findings; f.rule == "catalog/supersede-cycle"]
	count(cycle_findings) == 2
	some f in cycle_findings
	contains(f.message, "ADR-0001")
	some g in cycle_findings
	contains(g.message, "ADR-0002")
}

# ---------------------------------------------------------------------------
# catalog/ambiguous-supersede-chain — a fork: two ADRs supersede the same one
# ---------------------------------------------------------------------------

fixture_fork := catalog(
	[
		adr("ADR-0001", "Superseded", [], ["M-001"], ["terraform/"]),
		adr("ADR-0002", "Accepted", ["ADR-0001"], ["M-001"], ["dsc/"]),
		adr("ADR-0003", "Accepted", ["ADR-0001"], ["M-001"], ["kubernetes/"]),
	],
	[],
)

test_forked_chain_flagged_ambiguous if {
	report := validate.report with input as fixture_fork
	not report.valid
	some f in report.findings
	f.rule == "catalog/ambiguous-supersede-chain"
	contains(f.message, "ADR-0001")
}

# ---------------------------------------------------------------------------
# catalog/chain-depth-exceeded — a 9-hop chain is still growing at the cap
# ---------------------------------------------------------------------------

fixture_nine_hop := catalog(
	[
		adr("ADR-0001", "Superseded", [], ["M-001"], ["terraform/"]),
		adr("ADR-0002", "Superseded", ["ADR-0001"], ["M-001"], ["terraform/"]),
		adr("ADR-0003", "Superseded", ["ADR-0002"], ["M-001"], ["terraform/"]),
		adr("ADR-0004", "Superseded", ["ADR-0003"], ["M-001"], ["terraform/"]),
		adr("ADR-0005", "Superseded", ["ADR-0004"], ["M-001"], ["terraform/"]),
		adr("ADR-0006", "Superseded", ["ADR-0005"], ["M-001"], ["terraform/"]),
		adr("ADR-0007", "Superseded", ["ADR-0006"], ["M-001"], ["terraform/"]),
		adr("ADR-0008", "Superseded", ["ADR-0007"], ["M-001"], ["terraform/"]),
		adr("ADR-0009", "Superseded", ["ADR-0008"], ["M-001"], ["terraform/"]),
		adr("ADR-0010", "Accepted", ["ADR-0009"], ["M-001"], ["terraform/"]),
	],
	[],
)

test_nine_hop_chain_flagged_at_cap if {
	report := validate.report with input as fixture_nine_hop
	not report.valid
	some f in report.findings
	f.rule == "catalog/chain-depth-exceeded"
	contains(f.message, "8-hop")
}

test_seven_hop_chain_is_within_the_cap if {
	report := validate.report with input as catalog(
		[
			adr("ADR-0001", "Superseded", [], ["M-001"], ["terraform/"]),
			adr("ADR-0002", "Superseded", ["ADR-0001"], ["M-001"], ["terraform/"]),
			adr("ADR-0003", "Superseded", ["ADR-0002"], ["M-001"], ["terraform/"]),
			adr("ADR-0004", "Superseded", ["ADR-0003"], ["M-001"], ["terraform/"]),
			adr("ADR-0005", "Superseded", ["ADR-0004"], ["M-001"], ["terraform/"]),
			adr("ADR-0006", "Superseded", ["ADR-0005"], ["M-001"], ["terraform/"]),
			adr("ADR-0007", "Superseded", ["ADR-0006"], ["M-001"], ["terraform/"]),
			adr("ADR-0008", "Accepted", ["ADR-0007"], ["M-001"], ["terraform/"]),
		],
		[],
	)
	depth_findings := [f | some f in report.findings; f.rule == "catalog/chain-depth-exceeded"]
	count(depth_findings) == 0
	report.valid
}

# ---------------------------------------------------------------------------
# catalog/status-superseded-unmatched — status says Superseded, nothing does
# ---------------------------------------------------------------------------

test_status_superseded_unmatched_flagged if {
	report := validate.report with input as catalog([adr("ADR-0001", "Superseded", [], ["M-001"], ["terraform/"])], [])
	not report.valid
	some f in report.findings
	f.rule == "catalog/status-superseded-unmatched"
	contains(f.message, "ADR-0001")
	f.path == "$.adrs[0].status"
}

# ---------------------------------------------------------------------------
# catalog/superseded-but-accepted — superseded but status still Accepted
# ---------------------------------------------------------------------------

fixture_stale_status := catalog(
	[
		adr("ADR-0001", "Accepted", [], ["M-001"], ["terraform/"]),
		adr("ADR-0002", "Accepted", ["ADR-0001"], ["M-001"], ["dsc/"]),
	],
	[],
)

test_superseded_but_accepted_flagged if {
	report := validate.report with input as fixture_stale_status
	not report.valid
	some f in report.findings
	f.rule == "catalog/superseded-but-accepted"
	contains(f.message, "ADR-0001")
	contains(f.message, "ADR-0002")
}

# ---------------------------------------------------------------------------
# catalog/adr-without-requirements — an Accepted ADR must trace to MoSCoW
# ---------------------------------------------------------------------------

test_accepted_adr_without_requirements_flagged if {
	report := validate.report with input as catalog([adr("ADR-0001", "Accepted", [], [], ["terraform/"])], [])
	not report.valid
	some f in report.findings
	f.rule == "catalog/adr-without-requirements"
	contains(f.message, "MoSCoW")
	f.path == "$.adrs[0].related_requirements"
}

# ---------------------------------------------------------------------------
# catalog/adr-without-governs — an Accepted ADR must declare territory
# ---------------------------------------------------------------------------

test_accepted_adr_without_governs_flagged if {
	report := validate.report with input as catalog([adr("ADR-0001", "Accepted", [], ["M-001"], [])], [])
	not report.valid
	some f in report.findings
	f.rule == "catalog/adr-without-governs"
	contains(f.message, "governed paths")
	f.path == "$.adrs[0].governs"
}

# ---------------------------------------------------------------------------
# catalog/dangling-requirement-ref — ADR cites a requirement that does not exist
# ---------------------------------------------------------------------------

test_dangling_requirement_ref_flagged if {
	report := validate.report with input as catalog([adr("ADR-0001", "Accepted", [], ["M-999"], ["terraform/"])], [])
	not report.valid
	some f in report.findings
	f.rule == "catalog/dangling-requirement-ref"
	contains(f.message, "M-999")
	f.path == "$.adrs[0].related_requirements[0]"
}

# ---------------------------------------------------------------------------
# catalog/policy-* — policy metadoc defects
# ---------------------------------------------------------------------------

test_duplicate_policy_id_flagged if {
	report := validate.report with input as catalog(
		[good_adr],
		[policy("POL-001", ["ADR-0001"], ["M-001"]), policy("POL-001", ["ADR-0001"], ["M-001"])],
	)
	not report.valid
	some f in report.findings
	f.rule == "catalog/duplicate-policy-id"
	contains(f.message, "POL-001")
}

test_policy_unknown_adr_flagged if {
	report := validate.report with input as catalog([good_adr], [policy("POL-001", ["ADR-0099"], ["M-001"])])
	not report.valid
	some f in report.findings
	f.rule == "catalog/policy-unknown-adr"
	contains(f.message, "ADR-0099")
	f.path == "$.policies[0].related_adr[0]"
}

test_policy_unknown_requirement_flagged if {
	report := validate.report with input as catalog([good_adr], [policy("POL-001", ["ADR-0001"], ["S-999"])])
	not report.valid
	some f in report.findings
	f.rule == "catalog/policy-unknown-requirement"
	contains(f.message, "S-999")
}

test_policy_without_adr_flagged if {
	report := validate.report with input as catalog([good_adr], [policy("POL-001", [], ["M-001"])])
	not report.valid
	some f in report.findings
	f.rule == "catalog/policy-without-adr"
	contains(f.message, "POL-001")
	f.path == "$.policies[0].related_adr"
}

# ---------------------------------------------------------------------------
# The chain rules stay quiet on a healthy three-link chain — the traversal
# side is proven in chain_test.rego; here we assert the validation view.
# ---------------------------------------------------------------------------

fixture_three_link := catalog(
	[
		adr("ADR-0001", "Superseded", [], ["M-001"], ["terraform/"]),
		adr("ADR-0002", "Superseded", ["ADR-0001"], ["M-001"], ["terraform/"]),
		adr("ADR-0003", "Accepted", ["ADR-0002"], ["M-001"], ["terraform/"]),
	],
	[policy("POL-001", ["ADR-0003"], ["M-001"])],
)

test_three_link_chain_validates_clean if {
	report := validate.report with input as fixture_three_link
	report.valid
	report.finding_count == 0
}
