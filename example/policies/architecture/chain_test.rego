# policies/architecture/chain_test.rego
#
# Unit tests for the ARCH-002 supersede-chain traversal.  Run with:
#   opa test policies/architecture/ -v

package architecture.chain_test

import data.architecture.chain
import rego.v1

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

adr(id, supersedes) := {
	"id": id,
	"title": sprintf("decision %v", [id]),
	"status": "Accepted",
	"date": "2026-01-01",
	"author": "platform-team",
	"tags": [],
	"supersedes": supersedes,
	"related_requirements": ["M-001"],
	"governs": ["terraform/"],
	"file": sprintf("docs/adrs/%v.md", [id]),
}

adrs(list) := {"adrs": list, "policies": [], "requirements": [], "scan": {"scanner": "fixture"}}

# A three-link chain: 0003 supersedes 0002 supersedes 0001.
chain_three := adrs([
	adr("ADR-0001", []),
	adr("ADR-0002", ["ADR-0001"]),
	adr("ADR-0003", ["ADR-0002"]),
])

# A fork: two ADRs supersede the same base.
chain_fork := adrs([
	adr("ADR-0001", []),
	adr("ADR-0002", ["ADR-0001"]),
	adr("ADR-0003", ["ADR-0001"]),
])

# A cycle: each supersedes the other.
chain_cycle := adrs([adr("ADR-0001", ["ADR-0002"]), adr("ADR-0002", ["ADR-0001"])])

# A standalone ADR nobody supersedes.
chain_single := adrs([adr("ADR-0001", [])])

# ---------------------------------------------------------------------------
# Three-link chain: traversal resolves the terminal in both directions
# ---------------------------------------------------------------------------

test_effective_resolves_the_chain_terminal if {
	effective := chain.effective with input as chain_three
	effective["ADR-0001"] == "ADR-0003"
	effective["ADR-0002"] == "ADR-0003"
	effective["ADR-0003"] == "ADR-0003"
}

test_successor_names_the_current_version if {
	successor := chain.successor("ADR-0001") with input as chain_three
	successor == "ADR-0003"
}

test_terminal_adr_has_no_successor if {
	not chain.successor("ADR-0003") with input as chain_three
}

test_chain_members_include_the_whole_chain if {
	members := chain.chain_members("ADR-0001") with input as chain_three
	members == {"ADR-0001", "ADR-0002", "ADR-0003"}
}

test_only_the_newest_adr_is_terminal if {
	chain.terminal("ADR-0003") with input as chain_three
	not chain.terminal("ADR-0001") with input as chain_three
	not chain.terminal("ADR-0002") with input as chain_three
}

test_every_link_is_superseded_except_the_last if {
	chain.is_superseded("ADR-0001") with input as chain_three
	chain.is_superseded("ADR-0002") with input as chain_three
	not chain.is_superseded("ADR-0003") with input as chain_three
}

# ---------------------------------------------------------------------------
# Standalone ADR: its own current version
# ---------------------------------------------------------------------------

test_standalone_adr_is_its_own_effective_version if {
	effective := chain.effective with input as chain_single
	effective["ADR-0001"] == "ADR-0001"
}

test_standalone_adr_has_no_successor if {
	not chain.successor("ADR-0001") with input as chain_single
}

# ---------------------------------------------------------------------------
# Fork: two terminals means no effective version for the superseded base
# ---------------------------------------------------------------------------

test_forked_chain_has_no_effective_base if {
	effective := chain.effective with input as chain_fork
	not effective["ADR-0001"]

	# the two fork tips are their own current versions
	effective["ADR-0002"] == "ADR-0002"
	effective["ADR-0003"] == "ADR-0003"
}

test_forked_base_has_no_successor if {
	not chain.successor("ADR-0001") with input as chain_fork
}

# ---------------------------------------------------------------------------
# Cycle: the traversal detects the loop
# ---------------------------------------------------------------------------

test_cycle_reaches_the_adr_itself if {
	superseders := chain.chain_superseders("ADR-0001") with input as chain_cycle
	"ADR-0001" in superseders
	"ADR-0002" in superseders
}

test_cycle_has_no_effective_version if {
	effective := chain.effective with input as chain_cycle
	not effective["ADR-0001"]
	not effective["ADR-0002"]
}

# ---------------------------------------------------------------------------
# A known chain-shape regression guard: the closure must traverse more than
# one hop (the reason graph.reachable was rejected in ADR-0012).
# ---------------------------------------------------------------------------

test_two_hop_chain_is_not_stopped_after_one_hop if {
	superseders := chain.chain_superseders("ADR-0001") with input as chain_three
	count(superseders) == 2
}
