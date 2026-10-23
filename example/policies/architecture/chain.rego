# policies/architecture/chain.rego
#
# Supersede-chain traversal — the machine-readable ADR catalog's chains,
# traversed by policy instead of by hand.
#
# Given the catalog (input), chain.effective maps every ADR id to the
# current (terminal) ADR of its supersede chain:
#
#   ADR-0004 supersedes ADR-0001   (0004 is newer)
#   ADR-0009 supersedes ADR-0004
#   => effective["ADR-0001"] = "ADR-0009"
#
# An ADR that nothing supersedes is its own effective version.  Chains that
# cycle or fork have no single terminal; validate.rego flags those
# (catalog/supersede-cycle, catalog/ambiguous-supersede-chain) and the id is
# omitted from the effective map here.
#
# Implementation note (honest scope): the traversal is a bounded-hop closure
# — closure_1..closure_8 — because Rego forbids recursion.  Eight hops is
# the declared cap; validate.rego flags any chain still growing at the cap
# (catalog/chain-depth-exceeded), so the limit is loud, never silent.
# (graph.reachable is deliberately not used: in OA 0.69 it stops after one
# hop when the graph object is produced by a rule rather than a literal.)
#
# Run:
#   opa eval --data policies/architecture/ \
#            --input docs/generated/architecture-catalog.json \
#            'data.architecture.chain.effective'

package architecture.chain

import rego.v1

__rego__metadoc__ := {
	"id": "ARCH-002",
	"title": "Supersede-Chain Traversal",
	"description": "Traverses ADR supersede chains: effective[id] resolves the current ADR of each decision through a bounded-hop closure; successor() names the current version of a superseded ADR.",
	"severity": "HIGH",
	"remediation": "Fix the supersede refs in ADR front-matter; the validate policy names the exact chain defect.",
	"related_adr": ["ADR-0012"],
	"related_requirements": ["S-006", "M-005"],
}

# ---------------------------------------------------------------------------
# Supersede edges
# ---------------------------------------------------------------------------

# x supersedes y (x is the newer decision that replaces y).
supersedes(x, y) if {
	some a in input.adrs
	a.id == x
	y in a.supersedes
}

# One hop up the chain: every ADR that supersedes a member of the set.
# (Edge lookup inlined — OPA's safety analysis cannot bind a variable that
# appears only as an argument to a rule call.)
step_up(members) := {x |
	some m in members
	some a in input.adrs
	m in a.supersedes
	x := a.id
}

# ---------------------------------------------------------------------------
# Bounded-hop closure (explicit rules — Rego forbids recursion)
# ---------------------------------------------------------------------------

# closure_k(i) = every ADR that supersedes i within k hops.
# closure_1 starts ABOVE i, so i itself appears only through a cycle —
# that is the cycle check: i in chain_superseders(i).

closure_1(i) := step_up({i})

closure_2(i) := closure_1(i) | step_up(closure_1(i))

closure_3(i) := closure_2(i) | step_up(closure_2(i))

closure_4(i) := closure_3(i) | step_up(closure_3(i))

closure_5(i) := closure_4(i) | step_up(closure_4(i))

closure_6(i) := closure_5(i) | step_up(closure_5(i))

closure_7(i) := closure_6(i) | step_up(closure_6(i))

closure_8(i) := closure_7(i) | step_up(closure_7(i))

# The traversal cap: everything superseding i within 8 hops.
chain_superseders(i) := closure_8(i)

# A chain still growing at the cap — either a 9-hop chain or worse.
growing_at_cap(i) if {
	count(closure_8(i)) > count(closure_7(i))
}

# The full chain of an ADR, including itself.
chain_members(i) := {i} | chain_superseders(i)

# ---------------------------------------------------------------------------
# Terminals and effective versions
# ---------------------------------------------------------------------------

# Something in the catalog supersedes m.
is_superseded(m) if {
	some a in input.adrs
	m in a.supersedes
}

# m is terminal when nothing supersedes it.
terminal(m) if {
	not is_superseded(m)
}

# The current ADR of each supersede chain.  Only defined for chains that
# resolve to exactly one terminal ADR — cycles and forks are omitted and
# flagged by validate.rego.
effective[i] := t if {
	some a in input.adrs
	i := a.id
	members := chain_members(i)
	terminals := {m | some m in members; terminal(m)}
	count(terminals) == 1
	t := sort([x | some x in terminals])[0]
}

# The successor of a superseded ADR: the terminal of its chain when that
# terminal is a different (newer) ADR.  Used by gate.rego to redirect a PR
# that cites a superseded ADR to its current version.
successor(superseded) := t if {
	t := effective[superseded]
	t != superseded
}
