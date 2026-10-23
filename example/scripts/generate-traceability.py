#!/usr/bin/env python3
"""generate-traceability.py — deterministic drawio traceability diagram.

Regenerates docs/generated/traceability.drawio from the machine-readable
architecture catalog (docs/generated/architecture-catalog.json), following
the book's diagram conventions:

  * four columns, left to right:  MoSCoW requirement -> ADR -> policy ->
    implementation (governed path)
  * requirement  nodes: blue   (#dae8fc fill, #6c8ebf stroke)
  * ADR          nodes: yellow (#fff2cc fill, #d6b656 stroke)
  * policy       nodes: purple (#e1d5e7 fill, #9673a6 stroke)
  * implementation nodes: green (#d5e8d4 fill, #82b366 stroke)
  * superseded ADRs: grey fill (#f5f5f5), red stroke (#b85450)
  * supersede edges: red (#b85450), dashed; trace edges: grey (#666666)

Determinism: node order, edge order, and geometry are derived only from the
(sorted) catalog; the output carries no timestamps and regenerates
byte-identically (the CI gate proves this with cmp).

Self-QA: after writing, the diagram is re-parsed with ElementTree and
checked — unique node ids, every edge endpoint resolvable, and every
cataloged ADR/policy/requirement present.

Usage:
    python3 scripts/generate-traceability.py \
        [--root <example-dir>] [--output <file>] [--check]
"""

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# ---------------------------------------------------------------------------
# Geometry (fixed grid — the layout is part of the determinism contract)
# ---------------------------------------------------------------------------

COLUMN_X = {"requirement": 40, "adr": 440, "policy": 840, "implementation": 1240}
NODE_W, NODE_H, NODE_PITCH = 320, 30, 50
PAGE_HEIGHT = 4000  # generous; drawio does not clip

STYLE = {
    "requirement": "rounded=0;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;",
    "adr": "rounded=0;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;",
    "adr-superseded": "rounded=0;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#b85450;",
    "policy": "rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;",
    "implementation": "rounded=0;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;",
}
STYLE_EDGE = "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=block;strokeColor=#666666;"
STYLE_EDGE_SUPERSEDE = ("edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;"
                        "endArrow=block;dashed=1;strokeColor=#b85450;")

# XML escapes in attributes are handled by ElementTree; only the drawing
# template is fixed here.
TEMPLATE = {
    "host": "app.diagrams.net",
    "agent": "generate-traceability.py",
    "diagram_id": "architecture-traceability",
    "diagram_name": "Architecture Traceability",
}


# XML escapes in attribute values are handled by ElementTree itself.


# ---------------------------------------------------------------------------
# Graph extraction
# ---------------------------------------------------------------------------

def build_graph(catalog):
    """Extract the node/edge lists from the catalog, all deterministically sorted.

    Returns (nodes, edges) where nodes is a list of (id, kind, label, style)
    and edges is a list of (id, source, target, style).
    """
    adrs = catalog["adrs"]
    policies = catalog["policies"]
    requirements = catalog["requirements"]

    nodes = []
    edges = []

    def add_node(node_id, kind, label, superseded=False):
        style = STYLE["adr-superseded"] if (kind == "adr" and superseded) else STYLE[kind]
        nodes.append((node_id, kind, label, style))

    # -- requirements -------------------------------------------------------
    for req in requirements:
        add_node("req-%s" % req["id"], "requirement", req["id"])

    # -- ADRs ---------------------------------------------------------------
    superseded_ids = {s for a in adrs for s in a["supersedes"]}
    for adr in adrs:
        add_node("adr-%s" % adr["id"], "adr", "%s — %s" % (adr["id"], adr["title"]),
                 superseded=adr["id"] in superseded_ids)

    # -- policies -----------------------------------------------------------
    for pol in policies:
        add_node("pol-%s" % pol["id"], "policy", "%s — %s" % (pol["id"], pol["title"]))

    # -- implementation (governed paths, deduplicated) ----------------------
    impl_patterns = sorted({p for a in adrs for p in a["governs"]})
    for pattern in impl_patterns:
        add_node("impl-%s" % pattern, "implementation", pattern)

    # -- edges: requirement -> ADR -------------------------------------------
    for adr in adrs:
        for req in adr["related_requirements"]:
            edges.append(("e-req-%s-adr-%s" % (req, adr["id"]),
                          "req-%s" % req, "adr-%s" % adr["id"], STYLE_EDGE))

    # -- edges: ADR -> policy -------------------------------------------------
    for pol in policies:
        for adr_id in pol["related_adr"]:
            edges.append(("e-adr-%s-pol-%s" % (adr_id, pol["id"]),
                          "adr-%s" % adr_id, "pol-%s" % pol["id"], STYLE_EDGE))

    # -- edges: ADR -> implementation -----------------------------------------
    for adr in adrs:
        for pattern in adr["governs"]:
            edges.append(("e-adr-%s-impl-%s" % (adr["id"], pattern),
                          "adr-%s" % adr["id"], "impl-%s" % pattern, STYLE_EDGE))

    # -- edges: supersede chains ----------------------------------------------
    for adr in adrs:
        for old in adr["supersedes"]:
            edges.append(("e-supersede-%s-%s" % (adr["id"], old),
                          "adr-%s" % adr["id"], "adr-%s" % old,
                          STYLE_EDGE_SUPERSEDE))

    nodes.sort(key=lambda n: n[0])
    edges.sort(key=lambda e: e[0])
    return nodes, edges


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def render(nodes, edges):
    """Render the drawio document as a deterministic string."""
    mxfile = ET.Element("mxfile", {
        "host": TEMPLATE["host"], "agent": TEMPLATE["agent"], "version": "24.7.8"})
    diagram = ET.SubElement(mxfile, "diagram",
                            {"id": TEMPLATE["diagram_id"], "name": TEMPLATE["diagram_name"]})
    model = ET.SubElement(diagram, "mxGraphModel", {
        "dx": "800", "dy": "600", "grid": "1", "gridSize": "10", "guides": "1",
        "tooltips": "1", "connect": "1", "arrows": "1", "fold": "1", "page": "1",
        "pageScale": "1", "pageWidth": "1650", "pageHeight": str(PAGE_HEIGHT),
        "math": "0", "shadow": "0"})
    root = ET.SubElement(model, "root")
    ET.SubElement(root, "mxCell", {"id": "0"})
    ET.SubElement(root, "mxCell", {"id": "1", "parent": "0"})

    # rows within each column, ordered by node id (deterministic)
    row_of = {}
    counters = {}
    for node_id, kind, _label, _style in nodes:
        counters[kind] = counters.get(kind, 0)
        row_of[node_id] = counters[kind]
        counters[kind] += 1

    for node_id, kind, label, style in nodes:
        x = COLUMN_X[kind]
        y = 40 + row_of[node_id] * NODE_PITCH
        cell = ET.SubElement(root, "mxCell", {
            "id": node_id, "value": label, "style": style,
            "vertex": "1", "parent": "1"})
        ET.SubElement(cell, "mxGeometry", {
            "x": str(x), "y": str(y), "width": str(NODE_W), "height": str(NODE_H),
            "as": "geometry"})

    for edge_id, source, target, style in edges:
        cell = ET.SubElement(root, "mxCell", {
            "id": edge_id, "value": "", "style": style,
            "edge": "1", "parent": "1", "source": source, "target": target})
        ET.SubElement(cell, "mxGeometry", {
            "relative": "1", "as": "geometry"})

    ET.indent(mxfile, space="  ")
    return ET.tostring(mxfile, encoding="unicode") + "\n"


# ---------------------------------------------------------------------------
# Self-QA — the diagram is re-parsed and checked before leaving the tool
# ---------------------------------------------------------------------------

def self_qa(xml_text, nodes, edges):
    root = ET.fromstring(xml_text)
    ids = [cell.get("id") for cell in root.iter("mxCell")]
    if len(ids) != len(set(ids)):
        raise SystemExit("self-QA failed: duplicate mxCell ids")
    id_set = set(ids)
    for cell in root.iter("mxCell"):
        if cell.get("edge") == "1":
            if cell.get("source") not in id_set or cell.get("target") not in id_set:
                raise SystemExit("self-QA failed: edge %s has a dangling endpoint"
                                 % cell.get("id"))
    vertex_ids = {c.get("id") for c in root.iter("mxCell") if c.get("vertex") == "1"}
    for node_id, _kind, _label, _style in nodes:
        if node_id not in vertex_ids:
            raise SystemExit("self-QA failed: node %s missing from the diagram" % node_id)
    for edge in edges:
        if edge[0] not in id_set:
            raise SystemExit("self-QA failed: edge %s missing from the diagram" % edge[0])


def main():
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=str(script_dir.parent),
                        help="example/ directory (default: auto-detected)")
    parser.add_argument("--output", default="docs/generated/traceability.drawio",
                        help="output path, relative to --root")
    parser.add_argument("--check", action="store_true",
                        help="fail instead of write when the output would differ")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    with (root / "docs/generated/architecture-catalog.json").open(encoding="utf-8") as fh:
        catalog = json.load(fh)

    nodes, edges = build_graph(catalog)
    xml_text = render(nodes, edges)
    self_qa(xml_text, nodes, edges)

    out = root / args.output
    if args.check:
        current = out.read_text(encoding="utf-8") if out.is_file() else ""
        if current != xml_text:
            sys.stderr.write("traceability.drawio is stale — regenerate it with "
                             "scripts/generate-traceability.py and commit the result\n")
            return 1
        print("traceability.drawio is up to date (%d nodes, %d edges)"
              % (len(nodes), len(edges)))
        return 0

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(xml_text, encoding="utf-8")
    print("generated %s (%d nodes, %d edges)"
          % (out, len(nodes), len(edges)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
