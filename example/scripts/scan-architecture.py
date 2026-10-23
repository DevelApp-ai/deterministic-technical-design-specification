#!/usr/bin/env python3
"""scan-architecture.py — machine-readable architecture catalog scanner.

Extracts the repository's architecture traceability substrate into a single
JSON catalog (docs/generated/architecture-catalog.json):

  * ADRs           — YAML front-matter of docs/adrs/*.md
                     (id, title, status, date, author, tags, supersedes,
                      related_requirements, governs)
  * Policies       — __rego__metadoc__ blocks of policies/**/*.rego
                     (id, title, severity, related_adr, related_requirements)
  * Requirements   — MoSCoW requirement IDs from docs/requirements/moscow.md

The catalog is the single input consumed by the architecture Rego policies
(policies/architecture/): validate (loud findings), chain (supersede-chain
traversal), and gate (boundary gate for pull requests).

Honest scanner status: this is a metadata extraction scan, not a semantic
analysis.  It reads front-matter and metadoc blocks literally, line-based for
front-matter and token-based for the Rego metadoc literal.  Prose is ignored.

Determinism: output is byte-identical across runs on the same tree (sorted
keys, sorted collections, no timestamps).

Usage:
    python3 scripts/scan-architecture.py [--root <example-dir>] [--output <file>]
"""

import argparse
import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Minimal YAML front-matter subset parser (stdlib only, honest scope)
# ---------------------------------------------------------------------------
# Supports exactly the keys the estate's ADRs use:
#   key: scalar            (unquoted or quoted)
#   key: [a, b, c]         (inline list, optionally quoted items)
# Anything else raises ScanError — loud, never silent.

REQUIRED_ADR_KEYS = ("id", "title", "status", "date", "author",
                     "supersedes", "related_requirements")


class ScanError(Exception):
    pass


def _parse_inline_list(text):
    """Parse '[a, b, "c d"]' into a list of strings."""
    text = text.strip()
    if not (text.startswith("[") and text.endswith("]")):
        raise ScanError("not an inline list: %r" % text)
    inner = text[1:-1].strip()
    if inner == "":
        return []
    items, buf, quote = [], "", None
    for ch in inner:
        if quote:
            buf += ch
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            buf += ch
        elif ch == ",":
            items.append(buf.strip())
            buf = ""
        else:
            buf += ch
    if buf.strip() != "":
        items.append(buf.strip())
    if quote:
        raise ScanError("unterminated quote in inline list: %r" % text)
    return [re.sub(r"^[\"']|[\"']$", "", i) for i in items]


def parse_frontmatter(text):
    """Parse the leading '---' YAML front-matter block of a markdown file.

    Returns a dict of key -> (string | list).  Raises ScanError on malformed
    input.  Only the flat subset documented above is supported.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ScanError("file does not start with a '---' front-matter fence")
    meta = {}
    for idx in range(1, len(lines)):
        line = lines[idx]
        if line.strip() == "---":
            return meta
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue
        if line[:1].isspace():
            raise ScanError("indented line not supported: %r" % line)
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$", line)
        if not m:
            raise ScanError("unparseable front-matter line: %r" % line)
        key, value = m.group(1), m.group(2).strip()
        if value.startswith("["):
            meta[key] = _parse_inline_list(value)
        elif value.startswith(("\"", "'")):
            meta[key] = value[1:-1] if value.endswith(value[0]) else value
        else:
            meta[key] = value
    raise ScanError("front-matter block not closed with '---'")


# ---------------------------------------------------------------------------
# Minimal Rego object-literal parser (for __rego__metadoc__)
# ---------------------------------------------------------------------------

def parse_rego_object(src, start):
    """Parse a Rego object literal '{ ... }' beginning at src[start].

    Supports the metadoc subset: strings (double-quoted, backslash escapes),
    booleans, null, arrays, and nested objects.  Comments ('# ...') inside the
    literal are skipped.  Returns (python_value, end_index).
    """

    def skip_ws_comments(s, j):
        while j < len(s):
            if s[j].isspace():
                j += 1
            elif s[j] == "#":
                while j < len(s) and s[j] != "\n":
                    j += 1
            else:
                break
        return j

    def parse_value(s, j):
        j = skip_ws_comments(s, j)
        if j >= len(s):
            raise ScanError("metadoc literal ended unexpectedly")
        ch = s[j]
        if ch == "{":
            return parse_object(s, j)
        if ch == "[":
            return parse_array(s, j)
        if ch == '"':
            return parse_string(s, j)
        for literal, value in (("true", True), ("false", False), ("null", None)):
            if s.startswith(literal, j):
                return value, j + len(literal)
        raise ScanError("unsupported metadoc value at: %r" % s[j:j + 30])

    def parse_string(s, j):
        # s[j] == '"'
        out = []
        j += 1
        while j < len(s):
            ch = s[j]
            if ch == "\\":
                if j + 1 >= len(s):
                    raise ScanError("dangling escape in metadoc string")
                esc = s[j + 1]
                out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(esc, esc))
                j += 2
            elif ch == '"':
                return "".join(out), j + 1
            else:
                out.append(ch)
                j += 1
        raise ScanError("unterminated metadoc string")

    def parse_array(s, j):
        items = []
        j = skip_ws_comments(s, j + 1)  # consume '['
        if j < len(s) and s[j] == "]":
            return items, j + 1
        while True:
            value, j = parse_value(s, j)
            items.append(value)
            j = skip_ws_comments(s, j)
            if j < len(s) and s[j] == ",":
                j = skip_ws_comments(s, j + 1)
                if j < len(s) and s[j] == "]":
                    return items, j + 1
                continue
            if j < len(s) and s[j] == "]":
                return items, j + 1
            raise ScanError("expected ',' or ']' in metadoc array at: %r"
                            % s[j:j + 30])

    def parse_object(s, j):
        obj = {}
        j = skip_ws_comments(s, j + 1)  # consume '{'
        j = skip_ws_comments(s, j)
        if j < len(s) and s[j] == "}":
            return obj, j + 1
        while True:
            if j >= len(s) or s[j] not in "\"'":
                raise ScanError("expected quoted metadoc key at: %r"
                                % s[j:j + 30])
            quote = s[j]
            kend = s.index(quote, j + 1)
            key = s[j + 1:kend]
            j = skip_ws_comments(s, kend + 1)
            if j >= len(s) or s[j] != ":":
                raise ScanError("expected ':' after metadoc key %r" % key)
            value, j = parse_value(s, j + 1)
            obj[key] = value
            j = skip_ws_comments(s, j)
            if j < len(s) and s[j] == ",":
                j = skip_ws_comments(s, j + 1)
                if j < len(s) and s[j] == "}":
                    return obj, j + 1
                continue
            if j < len(s) and s[j] == "}":
                return obj, j + 1
            raise ScanError("expected ',' or '}' in metadoc object at: %r"
                            % s[j:j + 30])

    value, end = parse_value(src, start)
    return value, end


# ---------------------------------------------------------------------------
# Scanners
# ---------------------------------------------------------------------------

def scan_adrs(root):
    """Scan docs/adrs/*.md front-matter into catalog entries."""
    adr_dir = root / "docs" / "adrs"
    adrs = []
    if not adr_dir.is_dir():
        raise ScanError("missing docs/adrs/ directory under %s" % root)
    for path in sorted(adr_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        try:
            meta = parse_frontmatter(text)
        except ScanError as exc:
            raise ScanError("%s: %s" % (path, exc))
        for key in REQUIRED_ADR_KEYS:
            if key not in meta:
                raise ScanError("%s: missing required front-matter key %r"
                                % (path, key))
        adr = {
            "id": meta["id"],
            "title": meta["title"],
            "status": meta["status"],
            "date": meta["date"],
            "author": meta["author"],
            "tags": meta.get("tags", []),
            "supersedes": meta["supersedes"] if isinstance(meta["supersedes"], list) else [],
            "related_requirements": meta["related_requirements"] if isinstance(meta["related_requirements"], list) else [],
            "governs": meta.get("governs", []) if isinstance(meta.get("governs", []), list) else [],
            "file": "docs/adrs/" + path.name,
        }
        adrs.append(adr)
    adrs.sort(key=lambda a: a["id"])
    return adrs


def scan_policies(root):
    """Scan __rego__metadoc__ blocks of policies/**/*.rego (non-test files)."""
    policies = []
    pol_dir = root / "policies"
    if not pol_dir.is_dir():
        raise ScanError("missing policies/ directory under %s" % root)
    for path in sorted(pol_dir.rglob("*.rego")):
        if path.name.endswith("_test.rego"):
            continue
        src = path.read_text(encoding="utf-8")
        marker = re.search(r"__rego__metadoc__\s*:=\s*", src)
        if not marker:
            raise ScanError("%s: no __rego__metadoc__ block" % path)
        brace = src.find("{", marker.end())
        if brace == -1:
            raise ScanError("%s: metadoc marker not followed by '{'" % path)
        try:
            metadoc, _ = parse_rego_object(src, brace)
        except ScanError as exc:
            raise ScanError("%s: %s" % (path, exc))
        pkg = re.search(r"^\s*package\s+([\w.]+)", src, re.MULTILINE)
        if not pkg:
            raise ScanError("%s: no package declaration" % path)
        if "id" not in metadoc:
            raise ScanError("%s: metadoc missing 'id'" % path)
        policies.append({
            "id": metadoc.get("id", ""),
            "title": metadoc.get("title", ""),
            "severity": metadoc.get("severity", ""),
            "package": pkg.group(1),
            "related_adr": metadoc.get("related_adr", []),
            "related_requirements": metadoc.get("related_requirements", []),
            "file": "policies/" + str(path.relative_to(pol_dir)),
        })
    policies.sort(key=lambda p: (p["id"], p["file"]))
    return policies


def scan_requirements(root):
    """Scan MoSCoW requirement IDs from the requirements table."""
    moscow = root / "docs" / "requirements" / "moscow.md"
    if not moscow.is_file():
        raise ScanError("missing docs/requirements/moscow.md under %s" % root)
    ids = set()
    for line in moscow.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\|\s*([A-Z]{1,6}[0-9]?-\d{3})\s*\|", line)
        if m:
            ids.add(m.group(1))
    return [{"id": rid} for rid in sorted(ids)]


def main():
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=str(script_dir.parent),
                        help="example/ directory (default: auto-detected)")
    parser.add_argument("--output", default="docs/generated/architecture-catalog.json",
                        help="output path, relative to --root")
    parser.add_argument("--stdout", action="store_true",
                        help="also print the catalog to stdout")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    adrs = scan_adrs(root)
    policies = scan_policies(root)
    requirements = scan_requirements(root)

    catalog = {
        "adrs": adrs,
        "policies": policies,
        "requirements": requirements,
        "scan": {
            "scanner": "scan-architecture.py",
            "status": "metadata-scan (front-matter and metadoc literals only, "
                      "no semantic analysis)",
            "adr_count": len(adrs),
            "policy_count": len(policies),
            "requirement_count": len(requirements),
        },
    }

    out = root / args.output
    out.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(catalog, indent=2, sort_keys=False, ensure_ascii=False) + "\n"
    out.write_text(text, encoding="utf-8")
    if args.stdout:
        sys.stdout.write(text)
    print("scanned %d ADRs, %d policies, %d requirements -> %s"
          % (len(adrs), len(policies), len(requirements), out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
