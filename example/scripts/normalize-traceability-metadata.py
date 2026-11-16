#!/usr/bin/env python3
"""
normalize-traceability-metadata.py — shared metadata & ID contract normalizer.

Implements issue #24: the machine-readable contract that lets the
traceability graph be assembled mechanically across SpecTree formats,
replacing the ad-hoc conventions (Markdown front-matter
`related_requirements`, Rego `__rego__metadoc__`) with one normalized shape.

Sources normalized (all stdlib-only, all deterministic):
  * docs/requirements/moscow.md          — MoSCoW requirement tables
  * docs/adrs/*.md + spectree/specs/*.adr — ADR decisions (merged per id)
  * policies/**/*.rego                   — OPA gate policies incl. metadoc
                                           compliance blocks (NIS2/DORA)
  * spectree/specs/*.srs/.ai/.test/.ns   — SpecTree spec suite (via the
                                           committed parsers in
                                           scripts/spectree-parse.py)

Output: docs/generated/traceability/metadata-v1.json — a committed,
drift-gated artefact conforming to the published JSON Schema
spectree/schemas/traceability-metadata-v1.schema.json. Node ids are
namespace-qualified (moscow:, spec:, adr:, policy:) per the ID registry
spectree/id-namespaces.json; the normalizer fails loudly on duplicate ids
and records unresolved references in the integrity section.

Determinism: byte-identical output for the same tree (sorted nodes/edges,
no timestamps, fixed construction order).

Usage (from the example/ root, i.e. the parent of this scripts/ dir):

    python3 scripts/normalize-traceability-metadata.py --all
    python3 scripts/normalize-traceability-metadata.py --selftest
"""

import argparse
import importlib.util
import json
import os
import re
import sys

SCHEMA_NAME = "traceability-metadata"
SCHEMA_VERSION = 1
NORMALIZER = "normalize-traceability-metadata.py"

MOSCOW_ID_RE = re.compile(r"^[A-Z]{1,6}[0-9]?-[0-9]{3}$")
MOSCOW_BY_HEADING = (
    ("Must Have", "must"),
    ("Should Have", "should"),
    ("Could Have", "could"),
    ("Won't Have", "wont"),
)
STATUS_MAP = {"proposed": "Proposed", "accepted": "Accepted",
              "deprecated": "Deprecated", "superseded": "Superseded"}


# ---------------------------------------------------------------------------
# Module loading (hyphenated filenames, same directory)
# ---------------------------------------------------------------------------

def _load_module(name, filename):
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, filename)
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ---------------------------------------------------------------------------
# MoSCoW requirements (docs/requirements/moscow.md)
# ---------------------------------------------------------------------------

def parse_moscow(text, source="docs/requirements/moscow.md"):
    """Parse MoSCoW requirement tables into requirement nodes."""
    nodes = []
    category = None
    moscow = None
    for line in text.splitlines():
        if line.startswith("## "):
            heading = line[3:].strip()
            for prefix, value in MOSCOW_BY_HEADING:
                if heading.startswith(prefix):
                    category, moscow = heading, value
                    break
            else:
                category, moscow = None, None
            continue
        if category is None:
            continue
        cells = [cell.strip() for cell in
                 line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        rid, title = cells[0], cells[1]
        if not MOSCOW_ID_RE.match(rid):
            continue  # header/separator rows and non-requirement tables
        # Three-column tables (ID | Requirement | Satisfied By) keep the last
        # cell as evidence; four-column compliance tables (ID | Requirement |
        # <Article> | Satisfied By) keep every cell after the title.
        evidence = [cell for cell in cells[2:] if cell]
        nodes.append({
            "id": "moscow:" + rid,
            "type": "requirement",
            "title": title,
            "source": source,
            "moscow": moscow,
            "category": category,
            "evidence": evidence,
        })
    return nodes


# ---------------------------------------------------------------------------
# OPA policy compliance (policies/**/*.rego metadoc compliance blocks)
# ---------------------------------------------------------------------------

def parse_compliance(src):
    """Extract the metadoc compliance block of one .rego source file."""
    scan = _load_module("scan_architecture", "scan-architecture.py")
    marker = re.search(r"__rego__metadoc__\s*:=\s*", src)
    if not marker:
        return []
    brace = src.find("{", marker.end())
    if brace == -1:
        return []
    metadoc, _ = scan.parse_rego_object(src, brace)
    block = metadoc.get("compliance", {})
    entries = []
    for framework in sorted(block):
        refs = block[framework]
        if not isinstance(refs, list):
            refs = []
        entries.append({"framework": framework.upper(), "refs": refs,
                        "description": None})
    return entries


# ---------------------------------------------------------------------------
# ADR nodes (markdown front-matter + AdrSpec, merged per ADR id)
# ---------------------------------------------------------------------------

def adr_node_from_catalog(entry):
    return {
        "id": "adr:" + entry["id"],
        "type": "adr",
        "title": entry["title"],
        "source": entry["file"],
        "status": STATUS_MAP.get(entry["status"].lower(), entry["status"]),
        "date": entry["date"],
        "author": entry.get("author", ""),
        "supersedes": ["adr:" + sid for sid in entry.get("supersedes", [])],
        "relatedRequirements": ["moscow:" + rid
                                 for rid in entry.get("related_requirements", [])],
        "evidence": sorted(entry.get("governs", [])),
    }


def merge_spec_adr(node, spec_adr, source):
    """Merge an AdrSpec parse result into an existing adr node."""
    node["source"] = node["source"] + " + " + source
    evidence = node.get("evidence", [])
    for requirement in spec_adr.get("relatedRequirements", []):
        evidence.append("spectree-adr related requirement: " + requirement)
    evidence.append("spectree-adr status: " + str(spec_adr.get("status")))
    node["evidence"] = sorted(set(evidence))
    return node


def spec_adr_node(spec_adr, source):
    status = STATUS_MAP.get(spec_adr["status"], spec_adr["status"].title())
    return {
        "id": "adr:" + spec_adr["id"],
        "type": "adr",
        "title": spec_adr["title"],
        "source": source,
        "status": status,
        "date": spec_adr["date"],
        "author": spec_adr["author"],
        "supersedes": ["adr:" + sid for sid in spec_adr.get("supersedes", [])],
        "relatedRequirements": [],
        "evidence": ["spectree-adr related requirements: " + ", ".join(
            spec_adr.get("relatedRequirements", []))],
    }


# ---------------------------------------------------------------------------
# SpecTree spec-suite nodes (spectree/specs/)
# ---------------------------------------------------------------------------

def spec_srs_nodes(ast, source):
    nodes = []
    for category in ast["moscow"]:
        moscow = {"Must Have": "must", "Should Have": "should",
                  "Could Have": "could", "Won't Have": "wont"}[category["category"]]
        for requirement in category["requirements"]:
            nodes.append({
                "id": "spec:" + requirement["id"],
                "type": "requirement",
                "title": requirement["text"],
                "source": source,
                "moscow": moscow,
                "category": category["category"],
                "evidence": list(requirement.get("satisfiedBy", [])),
            })
    return nodes


def spec_ai_node(ast, source):
    node = {
        "id": "spec:" + ast["component"],
        "type": "component",
        "title": ast.get("description") or ast["component"],
        "source": source,
        "version": ast.get("version"),
        "dependencies": list(ast.get("dependencies", [])),
        "satisfies": ["spec:" + rid
                      for rid in ast.get("compliance", {}).get("requirementLinks", [])],
        "relatedAdr": ["adr:" + aid
                       for aid in ast.get("compliance", {}).get("adrReferences", [])],
        "evidence": ["%s requirement (%s): %s" % (r["kind"], r["id"] or "implicit",
                                                  r["text"])
                     for r in ast.get("requirements", [])],
    }
    if ast.get("namespace"):
        node["namespace"] = ast["namespace"]
    return node


def spec_test_node(ast, source):
    return {
        "id": "spec:" + ast["component"] + ".tests",
        "type": "test-suite",
        "title": "Test specification for " + ast["component"],
        "source": source,
        "target": ast["target"],
        "covers": ["spec:" + rid for rid in ast.get("requirementCoverage", [])],
    }


def spec_ns_nodes(ast, source):
    nodes = [{
        "id": "spec:" + ast["system"],
        "type": "system",
        "title": "Non-functional requirements for " + ast["system"],
        "source": source,
        "appliesTo": list(ast["appliesTo"]),
        "compliesWith": [{"framework": entry["framework"], "refs": [],
                          "description": entry["description"]}
                         for entry in ast.get("compliance", [])],
    }]
    for nfr in ast["performance"] + ast["scalability"]:
        nodes.append({
            "id": "spec:" + nfr["id"],
            "type": "nfr",
            "title": nfr.get("note") or "%s %s bound" % (nfr["id"], nfr["kind"]),
            "source": source,
            "kind": nfr["kind"],
            "bound": nfr["bound"],
            "relatedAdr": ["adr:" + nfr["adr"]] if nfr.get("adr") else [],
        })
    for security in ast["security"]:
        control = security["control"]
        nodes.append({
            "id": "spec:" + security["id"],
            "type": "nfr",
            "title": "%s control: %s = %s" % (security["id"], control["kind"],
                                              control["value"]),
            "source": source,
            "kind": "security-" + control["kind"],
            "bound": control if control["kind"] == "egress" else {},
            "relatedAdr": [],
        })
    return nodes


# ---------------------------------------------------------------------------
# Document assembly
# ---------------------------------------------------------------------------

def build_document(root):
    """Assemble the normalized metadata document from the sources tree."""
    root_path = os.path.abspath(root)
    scan = _load_module("scan_architecture", "scan-architecture.py")
    spectree = _load_module("spectree_parse", "spectree-parse.py")
    from pathlib import Path

    nodes = []
    edges = []

    # — MoSCoW requirements (moscow namespace) —
    moscow_path = os.path.join(root_path, "docs", "requirements", "moscow.md")
    with open(moscow_path, "r", encoding="utf-8") as handle:
        moscow_nodes = parse_moscow(handle.read())
    nodes.extend(moscow_nodes)

    # — ADRs (adr namespace, markdown + spec merged) —
    catalog_adrs = scan.scan_adrs(Path(root_path))
    adr_nodes = {}
    for entry in catalog_adrs:
        node = adr_node_from_catalog(entry)
        adr_nodes[node["id"]] = node
    nodes.extend(adr_nodes.values())

    # — OPA policies (policy namespace) —
    catalog_policies = scan.scan_policies(Path(root_path))
    for entry in catalog_policies:
        policy_path = os.path.join(root_path, entry["file"])
        with open(policy_path, "r", encoding="utf-8") as handle:
            compliance = parse_compliance(handle.read())
        node = {
            "id": "policy:" + entry["id"],
            "type": "policy",
            "title": entry["title"],
            "source": entry["file"],
            "severity": entry["severity"],
            "package": entry["package"],
            "relatedAdr": ["adr:" + aid for aid in entry.get("related_adr", [])],
            "relatedRequirements": ["moscow:" + rid
                                    for rid in entry.get("related_requirements", [])],
            "compliesWith": compliance,
        }
        nodes.append(node)
        for requirement in node["relatedRequirements"]:
            edges.append((node["id"], "satisfies", requirement))
        for adr in node["relatedAdr"]:
            edges.append((node["id"], "implements", adr))

    # — SpecTree spec suite (spec namespace) —
    specs_dir = os.path.join(root_path, "spectree", "specs")
    spec_counts = {}
    for name in sorted(os.listdir(specs_dir)):
        path = os.path.join(specs_dir, name)
        if not os.path.isfile(path):
            continue
        ext = os.path.splitext(name)[1]
        if ext not in spectree.PARSERS:
            continue
        source = "spectree/specs/" + name
        with open(path, "r", encoding="utf-8") as handle:
            ast = spectree.PARSERS[ext](handle.read())
        spec_counts[ext] = spec_counts.get(ext, 0) + 1
        if ext == ".srs":
            for node in spec_srs_nodes(ast, source):
                nodes.append(node)
        elif ext == ".ai":
            node = spec_ai_node(ast, source)
            nodes.append(node)
            for requirement in node["satisfies"]:
                edges.append((node["id"], "satisfies", requirement))
            for adr in node["relatedAdr"]:
                edges.append((node["id"], "implements", adr))
        elif ext == ".test":
            node = spec_test_node(ast, source)
            nodes.append(node)
            for requirement in node["covers"]:
                edges.append((node["id"], "covers", requirement))
        elif ext == ".ns":
            for node in spec_ns_nodes(ast, source):
                nodes.append(node)
                if node["type"] == "nfr":
                    for adr in node.get("relatedAdr", []):
                        edges.append((node["id"], "traces", adr))
        elif ext == ".adr":
            node_id = "adr:" + ast["id"]
            if node_id in adr_nodes:
                merge_spec_adr(adr_nodes[node_id], ast, source)
            else:
                adr_nodes[node_id] = spec_adr_node(ast, source)

    # — ADR edges (after the spec merge, so every adr node is present) —
    for node in adr_nodes.values():
        for requirement in node.get("relatedRequirements", []):
            edges.append((node["id"], "references", requirement))
        for superseded in node.get("supersedes", []):
            edges.append((node["id"], "supersedes", superseded))

    # — integrity: duplicate ids fail loudly, dangling references recorded —
    seen = {}
    for node in nodes:
        seen.setdefault(node["id"], 0)
        seen[node["id"]] += 1
    duplicates = sorted(node_id for node_id, count in seen.items() if count > 1)

    edge_records = [{"from": f, "type": t, "to": to}
                    for f, t, to in sorted(set(edges))]
    dangling = []
    for edge in edge_records:
        if edge["to"] not in seen:
            dangling.append({"from": edge["from"], "type": edge["type"],
                             "to": edge["to"], "missing": edge["to"]})
    dangling.sort(key=lambda d: (d["from"], d["type"], d["to"]))

    # — deterministic ordering, no unstable keys —
    def node_key(node):
        return (node["id"], node["type"])

    nodes.sort(key=node_key)
    namespaces = {}
    for node in nodes:
        prefix = node["id"].split(":", 1)[0]
        namespaces[prefix] = namespaces.get(prefix, 0) + 1

    document = {
        "schema": SCHEMA_NAME,
        "schemaVersion": SCHEMA_VERSION,
        "generated": {
            "normalizer": NORMALIZER,
            "status": "normalized metadata scan (front-matter, metadoc and "
                      "spec grammar literals; namespace-qualified ids)",
            "namespaces": namespaces,
            "nodeCount": len(nodes),
            "edgeCount": len(edge_records),
        },
        "nodes": nodes,
        "edges": edge_records,
        "integrity": {
            "duplicateIds": duplicates,
            "danglingEdges": dangling,
        },
    }
    if duplicates:
        raise SystemExit("normalize-traceability-metadata: duplicate node ids: "
                          + ", ".join(duplicates))
    return document


def document_to_json(document):
    return json.dumps(document, indent=2, sort_keys=True,
                      ensure_ascii=False) + "\n"


def load_schema(root):
    schema_path = os.path.join(root, "spectree", "schemas",
                               "traceability-metadata-v1.schema.json")
    with open(schema_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_document(document, schema):
    spectree = _load_module("spectree_parse", "spectree-parse.py")
    return spectree.schema_errors(document, schema, schema)


# ---------------------------------------------------------------------------
# Selftest — embedded unit tests (no external test framework)
# ---------------------------------------------------------------------------

def run_selftest(root):
    failures = []
    passed = 0

    def check(name, condition, detail=""):
        nonlocal passed
        if condition:
            passed += 1
        else:
            failures.append("%s%s" % (name, (": " + detail) if detail else ""))

    # ---- MoSCoW parser -----------------------------------------------------
    moscow_text = ("# front matter ignored\n\n"
                   "## Must Have\n\n"
                   "| ID | Requirement | Satisfied By |\n"
                   "|----|-------------|-------------|\n"
                   "| M-001 | First must requirement | `src/a.cs` |\n"
                   "| APP-009 | Application requirement | |\n\n"
                   "## Should Have — Extra\n\n"
                   "| S-001 | A should requirement | `src/b.cs` |\n\n"
                   "## Could Have\n\n"
                   "| C-001 | A could requirement | `src/c.cs` |\n\n"
                   "## Won't Have (in this iteration)\n\n"
                   "| W-001 | A wont requirement | `src/d.cs` |\n"
                   "| NIS2-001 | Compliance requirement | Art.21(2)(a) | `docs/n.md` |\n\n"
                   "## Not A MoSCoW Section\n\n"
                   "| X-001 | not a requirement | `src/e.cs` |\n")
    nodes = parse_moscow(moscow_text)
    check("moscow/count", len(nodes) == 6, repr(len(nodes)))
    check("moscow/ids", [n["id"] for n in nodes] ==
          ["moscow:M-001", "moscow:APP-009", "moscow:S-001", "moscow:C-001",
           "moscow:W-001", "moscow:NIS2-001"],
          repr([n["id"] for n in nodes]))
    check("moscow/qualified",
          all(n["id"].startswith("moscow:") for n in nodes))
    check("moscow/must", nodes[0]["moscow"] == "must" and
          nodes[0]["title"] == "First must requirement" and
          nodes[0]["evidence"] == ["`src/a.cs`"])
    check("moscow/should-heading",
          nodes[2]["category"] == "Should Have — Extra" and
          nodes[2]["moscow"] == "should")
    check("moscow/could", nodes[3]["moscow"] == "could")
    check("moscow/wont", nodes[4]["moscow"] == "wont")
    check("moscow/empty-evidence", nodes[1]["evidence"] == [])
    check("moscow/four-col",
          nodes[5]["evidence"] == ["Art.21(2)(a)", "`docs/n.md`"],
          repr(nodes[5]["evidence"]))

    # ---- Rego compliance extraction ---------------------------------------
    rego_src = ("package terraform.finops\n\n"
                "__rego__metadoc__ := {\n"
                "\t\"id\": \"FINOPS-001\",\n"
                "\t\"title\": \"T\",\n"
                "\t\"related_adr\": [\"ADR-0002\"],\n"
                "\t\"compliance\": {\n"
                "\t\t\"nis2\": [\"Art.21(2)(i)\"],\n"
                "\t\t\"dora\": [\"Art.8\", \"Art.10\"],\n"
                "\t},\n"
                "}\n")
    compliance = parse_compliance(rego_src)
    check("compliance/frameworks",
          [c["framework"] for c in compliance] == ["DORA", "NIS2"],
          repr(compliance))
    check("compliance/refs", compliance[0]["refs"] == ["Art.8", "Art.10"])
    check("compliance/absent", parse_compliance("package x\n") == [])

    # ---- ADR merge ---------------------------------------------------------
    catalog_entry = {"id": "ADR-0001", "title": "T", "status": "Accepted",
                      "date": "2026-01-01", "author": "platform-team",
                      "supersedes": [], "related_requirements": ["M-001"],
                      "governs": ["terraform/"], "file": "docs/adrs/a.md"}
    node = adr_node_from_catalog(catalog_entry)
    check("adr/qualified", node["id"] == "adr:ADR-0001")
    check("adr/status", node["status"] == "Accepted")
    check("adr/related", node["relatedRequirements"] == ["moscow:M-001"])
    spec_adr = {"id": "ADR-0001", "title": "T", "status": "accepted",
                "date": "2026-01-01", "author": "larsbuch",
                "supersedes": [], "relatedRequirements": ["M-009", "S-001"]}
    merge_spec_adr(node, spec_adr, "spectree/specs/x.adr")
    check("adr/merged-source",
          node["source"] == "docs/adrs/a.md + spectree/specs/x.adr")
    check("adr/merged-evidence",
          any("M-009" in item for item in node["evidence"]))
    orphan = spec_adr_node(spec_adr, "spectree/specs/y.adr")
    check("adr/orphan-status", orphan["status"] == "Accepted")

    # ---- SpecTree node builders --------------------------------------------
    spectree = _load_module("spectree_parse", "spectree-parse.py")
    srs = spectree.parse_srs("# SRS: X\n\n### Must Have\n- M-001: t\n")
    srs_nodes = spec_srs_nodes(srs, "spectree/specs/x.srs")
    check("srs/node", srs_nodes[0]["id"] == "spec:M-001" and
          srs_nodes[0]["moscow"] == "must")
    ai = spectree.parse_ai("# Component: C\n## Namespace: MyApp.Application\n"
                            "## Version: 1.0.0\n\n### Requirements\n"
                            "- M-003: declared requirement\n\n"
                            "### Compliance\n"
                            "- satisfies M-002\n- complies-with ADR-0015\n")
    ai_node = spec_ai_node(ai, "spectree/specs/x.ai")
    check("ai/component", ai_node["id"] == "spec:C" and
          ai_node["satisfies"] == ["spec:M-002"] and
          ai_node["relatedAdr"] == ["adr:ADR-0015"])
    test = spectree.parse_test("# Test: C\n## Target: t.cs\n\n"
                               "### RequirementCoverage\n- Covers M-001\n")
    test_node = spec_test_node(test, "spectree/specs/x.test")
    check("test/suite", test_node["id"] == "spec:C.tests" and
          test_node["covers"] == ["spec:M-001"])
    ns = spectree.parse_ns("# NFR: X\n## AppliesTo: solution\n\n"
                           "### Performance\n"
                           "- PERF-1 (latency): <= 200 ms adr: ADR-0015\n\n"
                           "### Security\n- SEC-1: classification: internal\n")
    ns_nodes = spec_ns_nodes(ns, "spectree/specs/x.ns")
    check("ns/system", ns_nodes[0]["type"] == "system" and
          ns_nodes[0]["appliesTo"] == ["solution"])
    nfr = ns_nodes[1]
    check("ns/nfr", nfr["id"] == "spec:PERF-1" and
          nfr["relatedAdr"] == ["adr:ADR-0015"] and nfr["kind"] == "latency")
    check("ns/security-nfr", ns_nodes[2]["id"] == "spec:SEC-1" and
          ns_nodes[2]["kind"] == "security-classification")

    # ---- document assembly, schema, determinism (real tree) ---------------
    document = build_document(root)
    errors = validate_document(document, load_schema(root))
    check("doc/schema-valid", errors == [], repr(errors[:2]))
    moscow_count = sum(1 for n in document["nodes"]
                       if n["id"].startswith("moscow:"))
    spec_count = sum(1 for n in document["nodes"]
                     if n["id"].startswith("spec:"))
    adr_count = sum(1 for n in document["nodes"]
                    if n["id"].startswith("adr:"))
    policy_count = sum(1 for n in document["nodes"]
                       if n["id"].startswith("policy:"))
    check("doc/counts-sum",
          moscow_count + spec_count + adr_count + policy_count ==
          len(document["nodes"]))
    check("doc/policy-count", policy_count == 18, repr(policy_count))
    check("doc/no-duplicates", document["integrity"]["duplicateIds"] == [])
    check("doc/deterministic",
          document_to_json(document) == document_to_json(build_document(root)))
    payload = document_to_json(document)
    check("doc/newline", payload.endswith("\n") and "\r" not in payload)
    check("doc/roundtrip", json.loads(payload) == document)
    covered = {e["to"] for e in document["edges"]}
    node_ids = {n["id"] for n in document["nodes"]}
    expected_dangling = sorted(
        ({"from": e["from"], "type": e["type"], "to": e["to"],
          "missing": e["to"]} for e in document["edges"]
         if e["to"] not in node_ids),
        key=lambda d: (d["from"], d["type"], d["to"]))
    check("doc/dangling-exact",
          document["integrity"]["danglingEdges"] == expected_dangling,
          repr(document["integrity"]["danglingEdges"][:3]))
    check("doc/dangling-recorded",
          all(d["missing"].startswith(("moscow:", "spec:", "adr:", "policy:"))
              for d in document["integrity"]["danglingEdges"]))

    print("normalize-traceability-metadata selftest: %d checks passed, %d failed"
          % (passed, len(failures)))
    for failure in failures:
        print("  FAIL %s" % failure, file=sys.stderr)
    return 1 if failures else 0


# ---------------------------------------------------------------------------
# Command-line interface
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Shared traceability metadata normalizer (issue #24)")
    parser.add_argument("--all", action="store_true",
                        help="normalize the sources tree and write "
                             "docs/generated/traceability/metadata-v1.json")
    parser.add_argument("--selftest", action="store_true",
                        help="run the embedded normalizer unit tests")
    parser.add_argument("--stdout", action="store_true",
                        help="with --all, also print the document to stdout")
    args = parser.parse_args(argv)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    if args.selftest:
        return run_selftest(root)

    if args.all:
        document = build_document(root)
        errors = validate_document(document, load_schema(root))
        if errors:
            sys.stderr.write("metadata schema validation failed:\n  %s\n"
                             % "\n  ".join(errors[:5]))
            return 1
        out_dir = os.path.join(root, "docs", "generated", "traceability")
        os.makedirs(out_dir, exist_ok=True)
        payload = document_to_json(document)
        out_path = os.path.join(out_dir, "metadata-v1.json")
        with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(payload)
        if args.stdout:
            sys.stdout.write(payload)
        print("normalize-traceability-metadata: %d nodes, %d edges, "
              "%d dangling -> %s"
              % (len(document["nodes"]), len(document["edges"]),
                 len(document["integrity"]["danglingEdges"]), out_path))
        return 0

    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
