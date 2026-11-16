#!/usr/bin/env python3
"""scripts/generate-tds-composition.py — SpecTree TDS composition generator (ADR-0021)

Parses the SpecTree TDS composition manifest grammar (``*.tds``, line-based)
and emits a committed, drift-gated composition report that binds every
composed source to its git blob SHA — the deterministic-rebuild proof for
the assembled Technical Design Specification.

The grammar (see spectree/tds/myapp.tds for the annotated reference)::

    // comment
    # TDS: <title>                      required, exactly one
    ## Solution: <manifest-file-name>    required; spectree/specs/<name>
    ## Version: <semver>                required; TDS document version
    ## Target: <kind> (key: value, ...)  repeatable; mkdocs | techdocs | standalone
    ### Section: <title>                 repeatable, ordered, unique titles
    ("- Source: <glob>                    repeatable, >=1 per section
    - Source: <glob> (generated)          pipeline-generated artefact: not
                                         blob-bound (its integrity derives
                                         from the deterministic build, see
                                         ADR-0013/0015); may be absent until
                                         the pipeline stage that produces it
                                         has run
    - Selector: <artefact>#<node-type>  optional; AST node selector
    - Rule: <phrase>                    optional; fixed vocabulary

The parsed AST is published as
``spectree/schemas/tds-manifest-v1.schema.json``.

Determinism bar (ADR-0018): standard library only, no timestamps, no
network, byte-identical output for identical input trees.  Git blob SHAs
are computed in pure Python (``sha1("blob <len>\\0" + bytes)``), which is
exactly what ``git hash-object`` produces — no git binary required.

Usage:
    generate-tds-composition.py --selftest   run the embedded test suite
    generate-tds-composition.py --all        parse spectree/tds/*.tds and
                                             write docs/generated/tds/*.composition.json
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import sys
import tempfile

SCHEMA = "tds-composition-v1"

# Required parameters per rendering target kind.
TARGET_KINDS = {
    "mkdocs": ["nav"],        # nav anchor section in mkdocs.yml
    "techdocs": ["publisher"],  # Backstage TechDocs publisher
    "standalone": ["path"],   # export directory (must live under docs/generated/)
}

# Fixed inclusion/exclusion rule vocabulary.
RULES = [
    "summarize wont requirements",
    "appendix superseded adrs",
    "exclude deprecated adrs",
    "detail public api",
    "exclude test projects",
]

SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SELECTOR_RE = re.compile(r"^(?P<artifact>[^#\s][^#]*)#(?P<node_type>[A-Za-z][A-Za-z0-9_-]*)$")
TARGET_RE = re.compile(
    r"^(?P<kind>[A-Za-z][A-Za-z0-9_-]*)(?:\s*\((?P<params>[^)]*)\))?$"
)
PARAM_RE = re.compile(r"^\s*([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(\S+)\s*$")

DIRECTIVE_RES = [
    ("tds", re.compile(r"^#\s+TDS:\s*(?P<value>.+?)\s*$")),
    ("solution", re.compile(r"^##\s+Solution:\s*(?P<value>.+?)\s*$")),
    ("version", re.compile(r"^##\s+Version:\s*(?P<value>.+?)\s*$")),
    ("target", re.compile(r"^##\s+Target:\s*(?P<value>.+?)\s*$")),
    ("section", re.compile(r"^###\s+Section:\s*(?P<value>.+?)\s*$")),
    ("source", re.compile(r"^-\s+Source:\s*(?P<value>.+?)\s*$")),
    ("selector", re.compile(r"^-\s+Selector:\s*(?P<value>.+?)\s*$")),
    ("rule", re.compile(r"^-\s+Rule:\s*(?P<value>.+?)\s*$")),
]

SINGLETON_DIRECTIVES = {"tds", "solution", "version"}


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_tds(text, origin):
    """Parse .tds manifest text into an AST.

    Returns ``(ast, errors)`` where errors is a list of
    ``(line_number, message)`` tuples.  The AST is only meaningful when
    errors is empty.
    """
    ast = {"title": None, "solution": None, "version": None,
           "targets": [], "sections": []}
    errors = []
    current = None  # section being populated

    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        for name, rx in DIRECTIVE_RES:
            match = rx.match(line)
            if not match:
                continue
            value = match.group("value")
            if name == "tds":
                if ast["title"] is not None:
                    errors.append((lineno, "duplicate '# TDS:' header"))
                ast["title"] = value
            elif name in SINGLETON_DIRECTIVES:
                key = name if name != "tds" else "title"
                field = {"solution": "solution", "version": "version"}[name]
                if ast[field] is not None:
                    errors.append((lineno, f"duplicate '## {name.title()}:' directive"))
                else:
                    ast[field] = value
            elif name == "target":
                ast["targets"].append(_parse_target(lineno, value, errors))
            elif name == "section":
                current = {"title": value, "sources": [],
                           "selectors": [], "rules": []}
                ast["sections"].append(current)
            elif name in ("source", "selector", "rule"):
                if current is None:
                    errors.append(
                        (lineno, f"'- {name.title()}:' before any '### Section:'"))
                elif name == "source":
                    sm = re.match(r"^(?P<pattern>.+?)\s*\(generated\)$", value)
                    if sm:
                        current["sources"].append(
                            {"pattern": sm.group("pattern"), "generated": True})
                    else:
                        current["sources"].append(
                            {"pattern": value, "generated": False})
                elif name == "selector":
                    current["selectors"].append(value)
                else:
                    current["rules"].append(value)
            break
        else:
            errors.append((lineno, f"unrecognized grammar line: {line!r}"))
            _ = origin  # kept for error reporting by callers
    return ast, errors


def _parse_target(lineno, value, errors):
    match = TARGET_RE.match(value)
    if not match:
        errors.append((lineno, f"malformed '## Target:' directive: {value!r}"))
        return {"kind": None, "params": {}}
    kind = match.group("kind")
    params = {}
    if match.group("params") is not None:
        for chunk in match.group("params").split(","):
            pm = PARAM_RE.match(chunk)
            if not pm:
                errors.append(
                    (lineno, f"malformed target parameter: {chunk.strip()!r}"))
            else:
                params[pm.group(1)] = pm.group(2)
    return {"kind": kind, "params": params}


def validate_ast(ast, errors_out, origin):
    """Semantic validation of a parsed manifest; appends to errors_out."""
    def err(msg):
        errors_out.append((origin, msg))

    if ast["title"] is None:
        err("missing '# TDS:' header")
    if ast["solution"] is None:
        err("missing '## Solution:' directive")
    if ast["version"] is None:
        err("missing '## Version:' directive")
    elif not SEMVER_RE.match(ast["version"]):
        err(f"version {ast['version']!r} is not a semantic version (X.Y.Z)")

    if not ast["targets"]:
        err("at least one '## Target:' directive is required")
    for target in ast["targets"]:
        kind = target["kind"]
        if kind not in TARGET_KINDS:
            err(f"unknown target kind {kind!r} "
                f"(expected one of: {', '.join(sorted(TARGET_KINDS))})")
            continue
        required = TARGET_KINDS[kind]
        for key in required:
            if key not in target["params"]:
                err(f"target {kind!r} is missing required parameter {key!r}")
        extra = sorted(set(target["params"]) - set(required))
        for key in extra:
            err(f"target {kind!r} does not take parameter {key!r}")

    if not ast["sections"]:
        err("at least one '### Section:' directive is required")
    titles = [s["title"] for s in ast["sections"]]
    for title in sorted(set(titles)):
        if titles.count(title) > 1:
            err(f"duplicate section title {title!r}")
    for section in ast["sections"]:
        if not section["sources"]:
            err(f"section {section['title']!r} has no '- Source:' entries")
        for selector in section["selectors"]:
            if not SELECTOR_RE.match(selector):
                err(f"malformed selector {selector!r} "
                    "(expected '<artefact>#<node-type>')")
        for rule in section["rules"]:
            if rule not in RULES:
                err(f"unknown rule {rule!r} "
                    f"(vocabulary: {'; '.join(RULES)})")
    return errors_out


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

def git_blob_sha(data):
    """Git blob SHA-1 in pure Python — identical to `git hash-object`."""
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def resolve_manifest(root, ast, errors_out, origin):
    """Resolve sources, selectors, and targets against the tree at root.

    Returns the composition report dict; resolution failures are appended
    to errors_out as (origin, message).
    """
    def err(msg):
        errors_out.append((origin, msg))

    # -- Solution binding ----------------------------------------------------
    solution_path = os.path.join("spectree", "specs", ast["solution"])
    if not os.path.isfile(os.path.join(root, solution_path)):
        err(f"solution manifest {solution_path!r} does not exist")

    # -- Targets -------------------------------------------------------------
    for target in ast["targets"]:
        kind = target["kind"]
        if kind not in TARGET_KINDS:
            continue  # already reported by validate_ast
        if kind == "mkdocs":
            nav = target["params"].get("nav")
            mkdocs_file = os.path.join(root, "mkdocs.yml")
            if os.path.isfile(mkdocs_file):
                with open(mkdocs_file, "r", encoding="utf-8") as fh:
                    mkdocs_text = fh.read()
                if nav and not re.search(
                        r"^\s*-\s" + re.escape(nav) + r":", mkdocs_text, re.M):
                    err(f"mkdocs target nav anchor {nav!r} not found in mkdocs.yml")
            else:
                err("mkdocs.yml not found — cannot verify mkdocs target")
        elif kind == "techdocs":
            if not os.path.isfile(os.path.join(root, "catalog-info.yaml")):
                err("techdocs target requires catalog-info.yaml")
        elif kind == "standalone":
            path = target["params"].get("path", "")
            if not path.startswith("docs/generated/"):
                err(f"standalone export path {path!r} must live under docs/generated/")

    # -- Sections ------------------------------------------------------------
    sections = []
    totals = {"sources": 0, "files": 0, "generated": 0, "selectors": 0, "rules": 0}
    for order, section in enumerate(ast["sections"], start=1):
        resolved_sources = []
        for source in section["sources"]:
            pattern = source["pattern"]
            if source["generated"]:
                # Pipeline-generated artefact: declared, never blob-bound.
                # Its integrity derives from the deterministic build that
                # produces it from blob-bound sources (ADR-0013/0015).
                resolved_sources.append(
                    {"pattern": pattern, "generated": True, "files": []})
                totals["generated"] += 1
                continue
            matches = sorted(glob.glob(os.path.join(root, pattern)))
            rel_matches = [os.path.relpath(p, root).replace(os.sep, "/")
                           for p in matches]
            if not rel_matches:
                err(f"source pattern {pattern!r} in section "
                    f"{section['title']!r} matches no files")
                resolved_sources.append(
                    {"pattern": pattern, "generated": False, "files": []})
                continue
            files = []
            for rel in rel_matches:
                with open(os.path.join(root, rel), "rb") as fh:
                    files.append({"path": rel, "blob": git_blob_sha(fh.read())})
            resolved_sources.append(
                {"pattern": pattern, "generated": False, "files": files})
            totals["files"] += len(files)
            totals["sources"] += 1
        totals["sources"] += sum(1 for s in resolved_sources
                                 if not s["files"] and not s["generated"])

        resolved_selectors = []
        for selector in section["selectors"]:
            match = SELECTOR_RE.match(selector)
            if not match:
                continue  # already reported by validate_ast
            artifact = match.group("artifact")
            node_type = match.group("node_type")
            artifact_path = os.path.join(root, artifact)
            if not os.path.isfile(artifact_path):
                err(f"selector artefact {artifact!r} does not exist")
                continue
            with open(artifact_path, "r", encoding="utf-8") as fh:
                try:
                    payload = json.load(fh)
                except json.JSONDecodeError as exc:
                    err(f"selector artefact {artifact!r} is not valid JSON: {exc}")
                    continue
            nodes = payload.get("nodes") if isinstance(payload, dict) else None
            if not isinstance(nodes, list):
                err(f"selector artefact {artifact!r} has no 'nodes' array")
                continue
            count = sum(1 for n in nodes
                         if isinstance(n, dict) and n.get("type") == node_type)
            resolved_selectors.append(
                {"artifact": artifact, "nodeType": node_type, "count": count})
            totals["selectors"] += 1
        totals["rules"] += len(section["rules"])

        sections.append({
            "title": section["title"],
            "order": order,
            "sources": resolved_sources,
            "selectors": resolved_selectors,
            "rules": list(section["rules"]),
        })

    return {
        "schema": SCHEMA,
        "manifest": origin,
        "solution": ast["solution"],
        "version": ast["version"],
        "targets": ast["targets"],
        "sections": sections,
        "totals": totals,
        "integrity": {"missingSources": [], "invalidTargets": []},
    }


def build_report(root, manifest_rel):
    """Parse + validate + resolve one manifest; returns (report, errors)."""
    manifest_path = os.path.join(root, manifest_rel)
    with open(manifest_path, "r", encoding="utf-8") as fh:
        text = fh.read()
    ast, errors = parse_tds(text, manifest_rel)
    validate_ast(ast, errors, manifest_rel)
    if errors:
        return None, errors
    report = resolve_manifest(root, ast, errors, manifest_rel)
    return report, errors


def write_report(root, report):
    out_dir = os.path.join(root, "docs", "generated", "tds")
    os.makedirs(out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(report["manifest"]))[0]
    out_path = os.path.join(out_dir, stem + ".composition.json")
    payload = json.dumps(report, indent=2, sort_keys=False,
                         ensure_ascii=False) + "\n"
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(payload)
    return os.path.relpath(out_path, root).replace(os.sep, "/")


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def run_all(root):
    manifests = sorted(glob.glob(os.path.join(root, "spectree", "tds", "*.tds")))
    if not manifests:
        print("generate-tds-composition: no manifests found under spectree/tds/")
        return 1
    failed = False
    for manifest_path in manifests:
        manifest_rel = os.path.relpath(manifest_path, root).replace(os.sep, "/")
        report, errors = build_report(root, manifest_rel)
        if errors:
            failed = True
            for at, message in errors:
                lineno = at if isinstance(at, int) else None
                if lineno:
                    print(f"  ERROR {manifest_rel}:{lineno}: {message}")
                else:
                    print(f"  ERROR {manifest_rel}: {message}")
            continue
        out_rel = write_report(root, report)
        totals = report["totals"]
        print(f"  {manifest_rel} -> {out_rel}: "
              f"{len(report['sections'])} sections, "
              f"{totals['sources']} source patterns, "
              f"{totals['files']} files bound to git blob SHAs, "
              f"{totals['selectors']} selectors resolved, "
              f"{totals['rules']} rules")
    if failed:
        print("generate-tds-composition: FAILED — see ERROR findings above")
        return 1
    print("generate-tds-composition: all manifests composed deterministically")
    return 0


# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------

def _selftest():
    checks = []

    def check(name, condition):
        checks.append((name, bool(condition)))

    valid = """\
# TDS: Demo
## Solution: demo.manifest
## Version: 1.2.3
## Target: mkdocs (nav: Traceability)
## Target: techdocs (publisher: docs)
## Target: standalone (path: docs/generated/tds)
### Section: One
- Source: docs/*.md
- Selector: docs/generated/traceability/metadata-v1.json#requirement
- Rule: summarize wont requirements
### Section: Two
- Source: docs/adrs/*.md
- Source: docs/gen/*.md (generated)
- Selector: docs/generated/traceability/metadata-v1.json#adr
- Rule: appendix superseded adrs
"""
    ast, errors = parse_tds(valid, "fixture")
    check("valid manifest parses without errors", not errors)
    check("title parsed", ast["title"] == "Demo")
    check("solution parsed", ast["solution"] == "demo.manifest")
    check("version parsed", ast["version"] == "1.2.3")
    check("three targets parsed", len(ast["targets"]) == 3)
    check("target params parsed",
          ast["targets"][0]["params"] == {"nav": "Traceability"})
    check("two sections parsed", len(ast["sections"]) == 2)
    check("source parsed",
          ast["sections"][0]["sources"] ==
          [{"pattern": "docs/*.md", "generated": False}])
    check("generated source qualifier parsed",
          ast["sections"][1]["sources"][-1] ==
          {"pattern": "docs/gen/*.md", "generated": True})
    check("selector parsed",
          ast["sections"][0]["selectors"] ==
          ["docs/generated/traceability/metadata-v1.json#requirement"])
    check("rule parsed",
          ast["sections"][0]["rules"] == ["summarize wont requirements"])
    check("validate accepts valid manifest",
          not validate_ast(ast, [], "fixture"))

    # Comment and blank lines are ignored.
    ast_c, errors_c = parse_tds("// comment\n\n" + valid, "fixture")
    check("comments and blanks ignored", not errors_c and ast_c == ast)

    def expect_errors(name, text, count=1):
        _, errs = parse_tds(text, "fixture")
        validate_ast(_, errs, "fixture")
        check(name, len(errs) == count)

    expect_errors("missing TDS header rejected", valid.replace(
        "# TDS: Demo\n", ""), 1)
    expect_errors("duplicate Solution rejected", valid.replace(
        "## Version:", "## Solution: other.manifest\n## Version:"), 1)
    expect_errors("non-semver version rejected", valid.replace(
        "1.2.3", "one.two.three"), 1)
    expect_errors("unknown target kind rejected", valid.replace(
        "mkdocs", "publisherd"), 1)
    expect_errors("mkdocs target without nav rejected", valid.replace(
        "(nav: Traceability)", ""), 1)
    expect_errors("extra target parameter rejected", valid.replace(
        "(nav: Traceability)", "(nav: Traceability, extra: 1)"), 1)
    expect_errors("no sections rejected", valid.split("### Section")[0], 1)
    expect_errors("duplicate section titles rejected", valid.replace(
        "### Section: Two", "### Section: One"), 1)
    expect_errors("unknown rule rejected", valid.replace(
        "summarize wont requirements", "hide everything"), 1)
    expect_errors("malformed selector rejected", valid.replace(
        "metadata-v1.json#requirement", "metadata-v1.json"), 1)
    expect_errors("unknown grammar line rejected",
                  valid + "?? nonsense\n", 1)
    expect_errors("source before section rejected", "- Source: docs/x.md\n" + valid, 1)
    expect_errors("section without sources rejected", valid.replace(
        "- Source: docs/adrs/*.md\n"
        "- Source: docs/gen/*.md (generated)\n", ""), 1)

    # Resolution over a synthetic tree --------------------------------------
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "docs"))
        os.makedirs(os.path.join(tmp, "docs", "adrs"))
        os.makedirs(os.path.join(tmp, "docs", "generated", "traceability"))
        os.makedirs(os.path.join(tmp, "spectree", "specs"))
        content_a = b"# Page A\n"
        content_b = b"# Page B\n"
        with open(os.path.join(tmp, "docs", "a.md"), "wb") as fh:
            fh.write(content_a)
        with open(os.path.join(tmp, "docs", "b.md"), "wb") as fh:
            fh.write(content_b)
        with open(os.path.join(tmp, "docs", "adrs", "0001-x.md"), "wb") as fh:
            fh.write(b"---\n---\n")
        with open(os.path.join(tmp, "spectree", "specs", "demo.manifest"), "w") as fh:
            fh.write("# SolutionManifest: Demo\n")
        with open(os.path.join(tmp, "docs", "generated", "traceability",
                               "metadata-v1.json"), "w") as fh:
            json.dump({"nodes": [
                {"id": "r1", "type": "requirement"},
                {"id": "r2", "type": "requirement"},
                {"id": "a1", "type": "adr"},
            ]}, fh)
        with open(os.path.join(tmp, "mkdocs.yml"), "w") as fh:
            fh.write("nav:\n  - Traceability:\n      - x: traceability/x.md\n")
        with open(os.path.join(tmp, "catalog-info.yaml"), "w") as fh:
            fh.write("apiVersion: backstage.io/v1alpha1\n")

        report, errors = build_report(tmp, "spectree/tds/demo.tds") \
            if os.path.isfile(os.path.join(tmp, "spectree", "tds", "demo.tds")) \
            else (None, [("fixture", "unreachable")])
        # Write manifest fixture into the tree so build_report can read it.
        os.makedirs(os.path.join(tmp, "spectree", "tds"), exist_ok=True)
        with open(os.path.join(tmp, "spectree", "tds", "demo.tds"), "w") as fh:
            fh.write(valid.replace("docs/*.md", "docs/*.md"))
        report, errors = build_report(tmp, "spectree/tds/demo.tds")
        check("resolution over synthetic tree succeeds", not errors and report is not None)
        if report:
            files = report["sections"][0]["sources"][0]["files"]
            check("glob sorted deterministically",
                  [f["path"] for f in files] == ["docs/a.md", "docs/b.md"])
            check("git blob SHA matches git hash-object semantics",
                  files[0]["blob"] == hashlib.sha1(
                      b"blob %d\0" % len(content_a) + content_a).hexdigest())
            sel = report["sections"][0]["selectors"][0]
            check("selector counts requirement nodes", sel["count"] == 2)
            check("adr selector counts adr nodes",
                  report["sections"][1]["selectors"] ==
                  [{"artifact": "docs/generated/traceability/metadata-v1.json",
                    "nodeType": "adr", "count": 1}])
            gen_src = report["sections"][1]["sources"][-1]
            check("generated source resolved without blob binding",
                  gen_src == {"pattern": "docs/gen/*.md",
                               "generated": True, "files": []})
            check("mkdocs nav anchor verified",
                  not any("nav" in m for _, m in errors))

        # Missing source and missing nav anchor are resolution errors.
        bad = valid.replace("docs/adrs/*.md", "docs/missing/*.md")
        with open(os.path.join(tmp, "spectree", "tds", "demo.tds"), "w") as fh:
            fh.write(bad)
        _, errors = build_report(tmp, "spectree/tds/demo.tds")
        check("missing source pattern rejected",
              any("matches no files" in m for _, m in errors))
        bad_nav = valid.replace("nav: Traceability", "nav: Nowhere")
        with open(os.path.join(tmp, "spectree", "tds", "demo.tds"), "w") as fh:
            fh.write(bad_nav)
        _, errors = build_report(tmp, "spectree/tds/demo.tds")
        check("missing mkdocs nav anchor rejected",
              any("not found in mkdocs.yml" in m for _, m in errors))
        bad_sol = valid.replace("demo.manifest", "absent.manifest")
        with open(os.path.join(tmp, "spectree", "tds", "demo.tds"), "w") as fh:
            fh.write(bad_sol)
        _, errors = build_report(tmp, "spectree/tds/demo.tds")
        check("missing solution manifest rejected",
              any("does not exist" in m for _, m in errors))
        bad_export = valid.replace(
            "standalone (path: docs/generated/tds)",
            "standalone (path: docs/export)")
        with open(os.path.join(tmp, "spectree", "tds", "demo.tds"), "w") as fh:
            fh.write(bad_export)
        _, errors = build_report(tmp, "spectree/tds/demo.tds")
        check("standalone export outside docs/generated rejected",
              any("must live under docs/generated" in m for _, m in errors))

        # Determinism: identical tree -> identical report bytes.
        with open(os.path.join(tmp, "spectree", "tds", "demo.tds"), "w") as fh:
            fh.write(valid)
        r1, _ = build_report(tmp, "spectree/tds/demo.tds")
        out1 = json.dumps(r1, indent=2, ensure_ascii=False) + "\n"
        r2, _ = build_report(tmp, "spectree/tds/demo.tds")
        out2 = json.dumps(r2, indent=2, ensure_ascii=False) + "\n"
        check("report generation is deterministic", out1 == out2)

    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        if not ok:
            print(f"  FAIL {name}")
    print(f"generate-tds-composition selftest: {len(checks) - len(failed)}/{len(checks)} checks passed")
    return 1 if failed else 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="SpecTree TDS composition generator (ADR-0021)")
    parser.add_argument("--selftest", action="store_true",
                        help="run the embedded test suite and exit")
    parser.add_argument("--all", action="store_true",
                        help="parse spectree/tds/*.tds and emit the "
                             "composition report(s)")
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
