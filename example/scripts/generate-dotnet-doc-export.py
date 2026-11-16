#!/usr/bin/env python3
"""scripts/generate-dotnet-doc-export.py — filtered XML-doc→Markdown export (ADR-0022)

Renders the public API surface of the .NET solution from the build-time
XML documentation files (``GenerateDocumentationFile``, ADR-0016 build
gate) into deterministic Markdown pages for TDS composition, and emits
the code→spec mapping artefact with ``<spec>`` traceability tags verified
against the shared metadata contract (ADR-0019).

Filtering policy (the ``detail public api`` / ``exclude test projects``
rules of the TDS composition manifest, ADR-0021):

- **Public API surface only** — the compiler emits XML doc entries exactly
  for members visible outside their assembly (CS1591 + warnings-as-errors
  already force documentation for every one of them); internal helpers
  (``MyApp.Api.Infrastructure``) never appear in the doc files.
- **Test projects excluded** — only ``dotnet/src/`` is scanned; anything
  under ``dotnet/tests/`` is never considered, and any assembly whose name
  contains ``Tests`` is rejected defensively.
- **Selective element inclusion** — ``summary``, ``remarks``, ``param``,
  ``returns``, ``exception``, ``response`` and ``spec`` are rendered;
  everything else (``inheritdoc`` etc.) is skipped.

Traceability: a ``<spec>ns:ID</spec>`` XML doc tag on a type or member
declares the requirement it traces to (namespace-qualified id per
``spectree/id-namespaces.json``).  Every tag is verified against the
node ids of ``docs/generated/traceability/metadata-v1.json``; an unknown
id fails the export.

Determinism bar (ADR-0018): standard library only, no timestamps, no
network, byte-identical output for identical inputs.

Usage:
    generate-dotnet-doc-export.py --selftest   run the embedded test suite
    generate-dotnet-doc-export.py --all         scan dotnet/src/*/bin/Release
                                               and write
                                               docs/generated/tds/dotnet-api/
                                               + docs/generated/tds/dotnet-spec-mapping.json
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

SCHEMA = "dotnet-spec-mapping-v1"

# Namespaces whose members are infrastructure plumbing, not API surface.
EXCLUDED_NAMESPACES = ("MyApp.Api.Infrastructure",)

# Common BCL type shortenings for signature rendering.
BCL_SHORT = {
    "System.String": "string",
    "System.Int32": "int",
    "System.Int64": "long",
    "System.Boolean": "bool",
    "System.Guid": "Guid",
    "System.Void": "void",
    "System.Object": "object",
}

MEMBER_KIND = {"T": "type", "M": "method", "P": "property",
               "F": "field", "E": "event"}

# XML doc elements that are rendered, in this fixed order.
INCLUDED_ELEMENTS = ["summary", "remarks", "param", "returns",
                     "exception", "response", "spec"]


# ---------------------------------------------------------------------------
# XML doc-file discovery
# ---------------------------------------------------------------------------

def discover_doc_files(dotnet_dir):
    """Find the Release XML doc file per project under dotnet/src/."""
    projects = sorted(
        os.path.basename(p)
        for p in glob.glob(os.path.join(dotnet_dir, "src", "*"))
        if os.path.isdir(p)
    )
    found = {}
    for project in projects:
        candidates = sorted(
            glob.glob(os.path.join(dotnet_dir, "src", project,
                                   "bin", "Release", "*", project + ".xml")))
        if len(candidates) > 1:
            # Deterministic tie-break: shortest tfm path, then name.
            candidates = sorted(candidates, key=lambda p: (len(p), p))[:1]
        if candidates:
            found[project] = candidates[0]
    return found


# ---------------------------------------------------------------------------
# Member-name decoding
# ---------------------------------------------------------------------------

def split_params(param_blob):
    """Split an XML doc parameter list at top level (commas not in generics)."""
    parts, depth, current = [], 0, []
    for ch in param_blob:
        if ch in "<{[":
            depth += 1
        elif ch in ">}]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    if current:
        parts.append("".join(current))
    return [p.strip() for p in parts if p.strip()]


def shorten_type(type_name):
    type_name = type_name.strip()
    if type_name in BCL_SHORT:
        return BCL_SHORT[type_name]
    if "``" in type_name:  # method generic parameters: ``0
        return re.sub(r"``\d+", "T", type_name)
    if "`" in type_name:  # closed generic: IReadOnlyList`1{MyApp.Domain.TodoItem}
        base, _, args = type_name.partition("`")
        inner = args.partition("{")[2].rpartition("}")[0]
        rendered = "<" + ", ".join(shorten_type(a) for a in split_params(inner)) + ">" \
            if inner else ""
        return base.rpartition(".")[2] + rendered
    return type_name.rpartition(".")[2] or type_name


def pretty_member(member_name):
    """Decode an XML doc member name into a display signature.

    ``M:MyApp.Domain.TodoItem.Create(System.String)`` →
    ``("method", "Create(string)", "MyApp.Domain.TodoItem", "Create")``
    """
    kind_code, _, name = member_name.partition(":")
    kind = MEMBER_KIND.get(kind_code)
    if kind is None:
        return (None, name, name, name)
    if kind == "type":
        return (kind, name.rpartition(".")[2], name, name.rpartition(".")[2])
    # method / property / field / event
    base, _, param_blob = name.partition("(")
    parent, _, member = base.rpartition(".")
    if member.startswith("#ctor"):
        member = "constructor"
    params = ""
    if param_blob:
        params = "(" + ", ".join(
            shorten_type(p) for p in split_params(param_blob.rstrip(")"))) + ")"
    elif member.startswith("``"):  # e.g. ``get_Item
        member = member.lstrip("`")
    return (kind, member + params, parent, member)


# ---------------------------------------------------------------------------
# Parsing + rendering
# ---------------------------------------------------------------------------

def parse_doc_file(path):
    """Parse one XML doc file into {member_name: {element: [values]}}."""
    tree = ET.parse(path)
    members = {}
    for member in tree.getroot().iter("member"):
        name = member.get("name", "")
        if not name:
            continue
        entry = members.setdefault(name, {})
        for child in member:
            if child.tag not in INCLUDED_ELEMENTS:
                continue
            text = render_text(inline_text(child))
            if child.tag == "param":
                pname = child.get("name", "")
                entry.setdefault("param", []).append((pname, text))
            elif child.tag == "exception":
                entry.setdefault("exception", []).append(
                    (shorten_type(child.get("cref", "")), text))
            elif child.tag == "response":
                entry.setdefault("response", []).append(
                    (child.get("code", ""), text))
            else:
                entry.setdefault(child.tag, []).append(text)
    return members


def inline_text(elem):
    """Render an XML doc element to text, keeping inline references.

    ``<see cref="T:X.Y"/>`` → ``X.Y`` short form, ``<see langword="null"/>``
    → ``null``, ``<paramref name="title"/>`` → ``title``; text around
    nested elements is preserved (not truncated at the first child).
    """
    out = [elem.text or ""]

    def walk(parent):
        for child in parent:
            tag = child.tag
            if tag == "see":
                langword = child.get("langword")
                cref = child.get("cref")
                if langword:
                    out.append(f"`{langword}`")
                elif cref:
                    target = cref.split(":", 1)[1] if ":" in cref else cref
                    out.append(f"`{shorten_type(target)}`")
                else:
                    out.append("")
            elif tag in ("paramref", "typeparamref"):
                out.append(f"`{child.get('name', '')}`")
            elif tag == "c":
                out.append(f"`{(child.text or '').strip()}`")
            else:
                out.append(child.text or "")
                walk(child)
            out.append(child.tail or "")

    walk(elem)
    return "".join(out)


def render_text(text):
    """Normalise doc text to a single Markdown line (collapsed whitespace)."""
    return re.sub(r"\s+", " ", text).strip()


def member_included(member_name):
    """Filtering policy: excluded namespaces and test assemblies never ship."""
    _, _, parent, _ = pretty_member(member_name)
    full = parent if pretty_member(member_name)[0] == "type" else member_name
    target = parent or full
    return not any(target == ns or target.startswith(ns + ".")
                   for ns in EXCLUDED_NAMESPACES)


def render_markdown(assembly, members):
    """Render one deterministic Markdown page for an assembly."""
    lines = [
        f"# {assembly} — filtered API export",
        "",
        "> Public API surface rendered deterministically from build-time XML",
        "> doc comments (ADR-0022). Test projects and infrastructure namespaces",
        "> are excluded; `<spec>` tags trace members to requirements and are",
        "> verified against the traceability metadata contract (ADR-0019).",
        "> Regenerate with `scripts/generate-dotnet-doc-export.py` — do not edit.",
        "",
    ]
    for name in sorted(members):
        kind, display, parent, _ = pretty_member(name)
        if kind != "type":
            continue
        entry = members[name]
        lines.append(f"## {display}")
        lines.append("")
        lines.append(f"`{parent}`")
        lines.append("")
        if entry.get("summary"):
            lines.append(render_text(" ".join(entry["summary"])))
            lines.append("")
        for pname, ptext in entry.get("param", []):
            lines.append(f"- **{pname}** — {render_text(ptext)}")
        if entry.get("param"):
            lines.append("")
        specs = entry.get("spec", [])
        if specs:
            lines.append("Traces to: " + ", ".join(
                f"`{s}`" for s in specs))
            lines.append("")
        for mname in sorted(members):
            mkind, mdisplay, mparent, _ = pretty_member(mname)
            if mkind in (None, "type") or mparent != parent:
                continue
            mentry = members[mname]
            lines.append(f"### {mdisplay}")
            lines.append("")
            lines.append(f"`{mname}`")
            lines.append("")
            if mentry.get("summary"):
                lines.append(render_text(" ".join(mentry["summary"])))
                lines.append("")
            for pname, ptext in mentry.get("param", []):
                lines.append(f"- **{pname}** — {render_text(ptext)}")
            if mentry.get("returns"):
                lines.append(f"- **Returns** — "
                             + render_text(" ".join(mentry["returns"])))
            for cref, ctext in mentry.get("exception", []):
                lines.append(f"- **Throws** `{cref}` — {render_text(ctext)}")
            for code, ctext in mentry.get("response", []):
                lines.append(f"- **{code}** — {render_text(ctext)}")
            mspecs = mentry.get("spec", [])
            if mspecs:
                lines.append(f"- **Traces to** — {', '.join(mspecs)}")
            lines.append("")
    # Members whose declaring type has no type entry (defensive; none today)
    lines.append("")
    return "\n".join(lines)


def extract_mapping(assembly, members):
    """Collect the code→spec mapping entries for one assembly."""
    entries = []
    for name in sorted(members):
        specs = members[name].get("spec", [])
        if specs:
            entries.append({"member": name, "specs": sorted(specs)})
    return entries


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def run_all(root):
    dotnet_dir = os.path.join(root, "dotnet")
    doc_files = discover_doc_files(dotnet_dir)
    if not doc_files:
        print("generate-dotnet-doc-export: no XML doc files found — "
              "run `dotnet build MyApp.slnx -c Release` first")
        return 1

    # Traceability verification source: the committed metadata artefact.
    metadata_path = os.path.join(
        root, "docs", "generated", "traceability", "metadata-v1.json")
    if not os.path.isfile(metadata_path):
        print("generate-dotnet-doc-export: missing "
              "docs/generated/traceability/metadata-v1.json — run "
              "scripts/normalize-traceability-metadata.py --all first")
        return 1
    with open(metadata_path, "r", encoding="utf-8") as fh:
        known_ids = {n["id"] for n in json.load(fh)["nodes"]}

    out_dir = os.path.join(root, "docs", "generated", "tds", "dotnet-api")
    os.makedirs(out_dir, exist_ok=True)

    failed = False
    assemblies = []
    totals = {"assemblies": 0, "exportedTypes": 0,
              "mappedMembers": 0, "specReferences": 0}
    for project, doc_path in sorted(doc_files.items()):
        if "Tests" in project:
            print(f"  ERROR {project}: test assemblies are excluded by policy")
            failed = True
            continue
        members = parse_doc_file(doc_path)
        members = {n: e for n, e in members.items() if member_included(n)}
        # Verify every <spec> reference resolves in the metadata contract.
        mapping = extract_mapping(project, members)
        for entry in mapping:
            for spec in entry["specs"]:
                if spec not in known_ids:
                    print(f"  ERROR {project}: <spec>{spec}</spec> on "
                          f"{entry['member']} does not resolve in the "
                          "traceability metadata contract")
                    failed = True
        md = render_markdown(project, members)
        out_path = os.path.join(out_dir, project + ".md")
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(md)
        type_count = sum(1 for n in members
                         if pretty_member(n)[0] == "type")
        totals["assemblies"] += 1
        totals["exportedTypes"] += type_count
        totals["mappedMembers"] += len(mapping)
        totals["specReferences"] += sum(len(e["specs"]) for e in mapping)
        assemblies.append({"assembly": project, "members": mapping})
        print(f"  {project}: {type_count} types exported -> "
              f"docs/generated/tds/dotnet-api/{project}.md "
              f"({len(mapping)} spec-tagged members)")

    report = {"schema": SCHEMA, "assemblies": assemblies, "totals": totals}
    mapping_path = os.path.join(
        root, "docs", "generated", "tds", "dotnet-spec-mapping.json")
    with open(mapping_path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"  mapping -> docs/generated/tds/dotnet-spec-mapping.json "
          f"({totals['specReferences']} spec references)")
    if failed:
        print("generate-dotnet-doc-export: FAILED — see ERROR findings above")
        return 1
    print("generate-dotnet-doc-export: export complete")
    return 0


# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------

FIXTURE_XML = """\
<?xml version="1.0"?>
<doc>
    <assembly><name>MyApp.Fixture</name></assembly>
    <members>
        <member name="T:MyApp.Fixture.Widget">
            <summary>A widget.</summary>
            <spec>moscow:M-001</spec>
        </member>
        <member name="M:MyApp.Fixture.Widget.Create(System.String)">
            <summary>Creates a widget.</summary>
            <param name="title">The widget title.</param>
            <returns>A new widget.</returns>
            <exception cref="T:System.ArgumentException">When title is empty.</exception>
            <spec>moscow:M-001</spec>
            <spec>moscow:S-002</spec>
        </member>
        <member name="M:MyApp.Fixture.Widget.#ctor(MyApp.Fixture.Widget)">
            <summary>Initializes the widget.</summary>
            <param name="other">Another widget.</param>
        </member>
        <member name="P:MyApp.Fixture.Widget.Title">
            <summary>Gets the title.</summary>
            <returns>The title.</returns>
        </member>
        <member name="T:MyApp.Api.Infrastructure.InMemoryAdapter">
            <summary>Internal plumbing.</summary>
        </member>
        <member name="M:MyApp.Application.TodoService.GetAll">
            <summary>Returns all todo items.</summary>
            <spec>moscow:M-001</spec>
        </member>
        <member name="M:MyApp.Fixture.Widget.GetResponse">
            <summary>Gets something.</summary>
            <response code="404">Not found.</response>
            <returns>A <see langword="null"/> response for <see cref="T:MyApp.Fixture.Widget"/> and <paramref name="plain"/> text.</returns>
            <example>Skip me.</example>
        </member>
    </members>
</doc>
"""


def _selftest():
    checks = []

    def check(name, condition):
        checks.append((name, bool(condition)))

    # Member-name decoding ---------------------------------------------
    check("type name decoded",
          pretty_member("T:MyApp.Domain.TodoItem") ==
          ("type", "TodoItem", "MyApp.Domain.TodoItem", "TodoItem"))
    kind, display, parent, member = pretty_member(
        "M:MyApp.Domain.TodoItem.Create(System.String)")
    check("method decoded", kind == "method")
    check("bcl type shortened", display == "Create(string)")
    check("method parent decoded", parent == "MyApp.Domain.TodoItem")
    check("constructor decoded",
          pretty_member("M:MyApp.Application.TodoService.#ctor"
                        "(MyApp.Domain.ITodoRepository)")[1] ==
          "constructor(ITodoRepository)")
    check("multi-param decoded",
          pretty_member("M:X.Y.Z(System.String,System.Guid)")[1] ==
          "Z(string, Guid)")
    check("property decoded",
          pretty_member("P:MyApp.Fixture.Widget.Title")[0] == "property")
    check("generic type shortened",
          shorten_type("System.Collections.Generic.IReadOnlyList`1"
                       "{MyApp.Domain.TodoItem}") == "IReadOnlyList<TodoItem>")
    check("split_params respects generic nesting",
          split_params("Sys.IList`1{A.B},Sys.Guid") ==
          ["Sys.IList`1{A.B}", "Sys.Guid"])

    # Parsing + filtering -----------------------------------------------
    with tempfile.TemporaryDirectory() as tmp:
        doc_path = os.path.join(tmp, "MyApp.Fixture.xml")
        with open(doc_path, "w", encoding="utf-8") as fh:
            fh.write(FIXTURE_XML)
        members = parse_doc_file(doc_path)
        check("members parsed", len(members) == 7)
        check("spec tags extracted",
              members["T:MyApp.Fixture.Widget"]["spec"] == ["moscow:M-001"])
        check("param extracted",
              members["M:MyApp.Fixture.Widget.Create(System.String)"]["param"]
              == [("title", "The widget title.")])
        check("exception extracted",
              members["M:MyApp.Fixture.Widget.Create(System.String)"]
              ["exception"] == [("ArgumentException", "When title is empty.")])
        check("response extracted",
              members["M:MyApp.Fixture.Widget.GetResponse"]["response"]
              == [("404", "Not found.")])
        check("nested inline references rendered, text not truncated",
              members["M:MyApp.Fixture.Widget.GetResponse"]["returns"]
              == ["A `null` response for `Widget` and `plain` text."])
        check("excluded element skipped",
              "example" not in members["M:MyApp.Fixture.Widget.GetResponse"])
        check("infrastructure namespace filtered",
              not member_included("T:MyApp.Api.Infrastructure.InMemoryAdapter"))
        check("application namespace kept",
              member_included("M:MyApp.Application.TodoService.GetAll"))

        # Mapping extraction
        mapping = extract_mapping("MyApp.Fixture", members)
        check("mapping lists spec-tagged members", len(mapping) == 3)
        create_entry = [e for e in mapping
                        if e["member"].startswith("M:...") or
                        "Create" in e["member"]]
        check("mapping member carries sorted specs",
              any(e["specs"] == ["moscow:M-001", "moscow:S-002"]
                  for e in mapping))

        # Rendering determinism (same filtering as run_all)
        members = {n: e for n, e in members.items() if member_included(n)}
        md1 = render_markdown("MyApp.Fixture", members)
        md2 = render_markdown("MyApp.Fixture", members)
        check("markdown rendering deterministic", md1 == md2)
        check("markdown contains type header", "## Widget" in md1)
        check("markdown contains method signature",
              "### Create(string)" in md1)
        check("markdown contains type spec trace line",
              "Traces to: `moscow:M-001`" in md1)
        check("markdown contains member spec trace",
              "- **Traces to** — moscow:M-001, moscow:S-002" in md1)
        check("markdown contains response code",
              "- **404** — Not found." in md1)
        check("excluded namespace not rendered",
              "InMemoryAdapter" not in md1)

        # Unknown <spec> ids are rejected against the metadata contract
        bad = FIXTURE_XML.replace("moscow:M-001\"</spec>",
                                  "moscow:NOPE</spec>")
        bad = bad.replace("<spec>moscow:M-001</spec>",
                          "<spec>moscow:NOPE</spec>")
        bad_members = parse_doc_file(doc_path)
        with open(doc_path, "w", encoding="utf-8") as fh:
            fh.write(bad)
        bad_members = parse_doc_file(doc_path)
        bad_mapping = extract_mapping("MyApp.Fixture", bad_members)
        known = {"moscow:M-001", "moscow:S-002"}
        check("unknown spec id detected by verification",
              any(s not in known for e in bad_mapping for s in e["specs"]))

        # Full output path: discovery finds Release builds only
        src = os.path.join(tmp, "src", "MyApp.Fixture")
        os.makedirs(os.path.join(src, "bin", "Release", "net10.0"), exist_ok=True)
        with open(os.path.join(src, "bin", "Release", "net10.0",
                               "MyApp.Fixture.xml"), "w", encoding="utf-8") as fh:
            fh.write(FIXTURE_XML)
        found = discover_doc_files(tmp)
        check("discovery finds release doc file",
              list(found) == ["MyApp.Fixture"])

    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        if not ok:
            print(f"  FAIL {name}")
    print(f"generate-dotnet-doc-export selftest: "
          f"{len(checks) - len(failed)}/{len(checks)} checks passed")
    return 1 if failed else 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Filtered XML-doc→Markdown export (ADR-0022)")
    parser.add_argument("--selftest", action="store_true",
                        help="run the embedded test suite and exit")
    parser.add_argument("--all", action="store_true",
                        help="scan dotnet/src/*/bin/Release and write the "
                             "export + mapping artefacts")
    parser.add_argument("--root", default=None,
                        help="pipeline root (default: auto-detect)")
    args = parser.parse_args(argv)

    if args.selftest:
        return _selftest()
    if args.all:
        root = args.root or os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..")
        return run_all(os.path.abspath(root))
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
