#!/usr/bin/env python3
"""
spectree-parse.py — deterministic SpecTree parser for the example pipeline.

Implements issue #23: hand-written, stdlib-only parsers for the eight
SpecTree specification formats defined by the vendored grammar files in
spectree/grammars/ (pinned copies of DevelApp-ai/Minotaur-Grammars
'specification-first/', commit de45cd55169d):

    SrsSpec (.srs)          AiSpec (.ai)            TestSpec (.test)
    ApiSpec (.api)          ModelSpec (.model)      NsSpec (.ns)
    AdrSpec (.adr)          SolutionManifest (.manifest)

Each parser consumes one specification file and emits a stable JSON AST
conforming to the committed schema
spectree/schemas/spectree-ast-v1.schema.json (versioned independently of
the grammars). Output is byte-for-byte deterministic: the same input file
always produces the same AST bytes (json.dump, indent 2, LF newline, no
key sorting — construction order is fixed by the parser).

Blank lines are ignored in every format (readability whitespace, not part
of the grammars). Any line that does not match the grammar produces a
ParseError with a line number and exits non-zero — the parser is a gate,
not a best-effort converter.

Usage (from the example/ root, i.e. the parent of this scripts/ dir):

    python3 scripts/spectree-parse.py --all              # parse spectree/specs/
    python3 scripts/spectree-parse.py --spec <file>      # parse one file (stdout)
    python3 scripts/spectree-parse.py --selftest         # embedded unit tests

--all and --spec validate every emitted AST against the committed JSON
Schema before writing; --all writes docs/generated/spectree/<name>.ast.json
(git-ignored generated artefacts).
"""

import argparse
import json
import os
import re
import sys
import tempfile

SCHEMA_NAME = "spectree-ast"
SCHEMA_VERSION = 1
GRAMMAR_COMMIT = "de45cd55169d"

# ---------------------------------------------------------------------------
# Grammar token definitions (mirrored from the vendored .grammar files)
# ---------------------------------------------------------------------------

IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
QUALIFIED_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$")
MANIFEST_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_.]*$")
REQ_ID_RE = re.compile(r"^(?:REQ|M|S|C|W)-[0-9]+$")
ADR_ID_RE = re.compile(r"^ADR-[0-9]+$")
VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*$")
ISO_DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
ROUTE_RE = re.compile(r"^/(?:[A-Za-z_][A-Za-z0-9_]*|\{[A-Za-z_][A-Za-z0-9_]*\})"
                      r"(?:/(?:[A-Za-z_][A-Za-z0-9_]*|\{[A-Za-z_][A-Za-z0-9_]*\}))*$")
NUMBER_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)?$")
STATUS_CODE_RE = re.compile(r"^[1-5][0-9][0-9]$")
ERROR_CODE_RE = re.compile(r"^[A-Z][A-Z0-9_]+$")

HTTP_METHODS = ("GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS")
AUTH_SCHEMES = ("none", "bearer", "apikey", "oauth2", "mtls")
ADR_STATUSES = ("proposed", "accepted", "deprecated", "superseded")
NS_UNITS = ("ms", "s", "min", "rps", "ops", "MB", "GB", "%", "cores")
NS_KINDS = ("latency", "throughput", "rps", "memory", "cpu", "uptime",
            "error-rate", "recovery")
CLASSIFICATIONS = ("public", "internal", "confidential", "restricted")
CIPHERS = ("AES-256-GCM", "TLS1.3", "TLS1.2")
CARDINALITIES = ("1-1", "1-*", "*-1", "*-*")
PRIMITIVES = ("string", "int", "long", "decimal", "bool", "DateTime",
              "DateTimeOffset", "Guid", "UUID", "byte[]")
TIME_UNITS = ("ms", "s", "min")
RATE_UNITS = ("rps", "ops")
SPEC_TYPES = ("ai", "test", "api", "model", "srs", "ns", "adr")
FRAMEWORK_RE = re.compile(r"^(?:NIS2|DORA|GDPR|SOC2)[A-Za-z0-9().]*$")

GRAMMAR_BY_EXT = {
    ".srs": "SrsSpec",
    ".ai": "AiSpec",
    ".test": "TestSpec",
    ".api": "ApiSpec",
    ".model": "ModelSpec",
    ".ns": "NsSpec",
    ".adr": "AdrSpec",
    ".manifest": "SolutionManifest",
}

AST_TYPE_BY_EXT = {
    ".srs": "srs",
    ".ai": "ai",
    ".test": "test",
    ".api": "api",
    ".model": "model",
    ".ns": "ns",
    ".adr": "adr",
    ".manifest": "manifest",
}


class ParseError(Exception):
    """Raised when a specification file violates its grammar."""

    def __init__(self, message, lineno):
        super().__init__("line %d: %s" % (lineno, message))
        self.lineno = lineno


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def _number(text, lineno):
    if not NUMBER_RE.match(text):
        raise ParseError("invalid number: %r" % text, lineno)
    return float(text) if "." in text else int(text)


def _identifier(text, lineno, what="identifier"):
    if not IDENT_RE.match(text):
        raise ParseError("invalid %s: %r" % (what, text), lineno)
    return text


def _requirement_id(text, lineno):
    if not REQ_ID_RE.match(text):
        raise ParseError("invalid requirement id: %r" % text, lineno)
    return text


def _route(text, lineno):
    if not ROUTE_RE.match(text):
        raise ParseError("invalid route path: %r" % text, lineno)
    return text


def _version(text, lineno):
    if not VERSION_RE.match(text):
        raise ParseError("invalid version number: %r" % text, lineno)
    return text


def _split_list(text, lineno, what):
    """Split a comma-separated list, rejecting empty items."""
    items = [item.strip() for item in text.split(",")]
    if not items or any(not item for item in items):
        raise ParseError("invalid %s list: %r" % (what, text), lineno)
    return items


def _read_lines(text):
    """Yield (lineno, stripped_line) for non-blank lines."""
    for lineno, raw in enumerate(text.split("\n"), start=1):
        line = raw.rstrip("\r")
        if line.strip():
            yield lineno, line


# ---------------------------------------------------------------------------
# SrsSpec (.srs)
# ---------------------------------------------------------------------------

MOSCOW_CATEGORIES = ("Must Have", "Should Have", "Could Have", "Won't Have")


def parse_srs(text):
    doc = {"project": None, "version": None, "stakeholders": [],
           "scope": None, "moscow": [], "traceability": []}
    section = None  # None | ("moscow", category) | "traceability"

    for lineno, line in _read_lines(text):
        if lineno == 1 or (doc["project"] is None and line.startswith("# SRS: ")):
            if line.startswith("# SRS: "):
                if doc["project"] is not None:
                    raise ParseError("duplicate SRS header", lineno)
                doc["project"] = _identifier(line[len("# SRS: "):].strip(), lineno,
                                             "project name")
                continue
            raise ParseError("expected '# SRS: <project>' header", lineno)
        elif section is None and line.startswith("## "):
            if line.startswith("## Version: "):
                doc["version"] = _version(line[len("## Version: "):].strip(), lineno)
            elif line.startswith("## Stakeholders: "):
                raw = line[len("## Stakeholders: "):].strip()
                doc["stakeholders"] = [
                    _identifier(item, lineno, "stakeholder")
                    for item in _split_list(raw, lineno, "stakeholder")]
            elif line.startswith("## Scope: "):
                doc["scope"] = line[len("## Scope: "):].strip()
            else:
                raise ParseError("unknown metadata line: %r" % line, lineno)
        elif line.startswith("### "):
            heading = line[len("### "):].strip()
            if heading in MOSCOW_CATEGORIES:
                section = ("moscow", heading)
                doc["moscow"].append({"category": heading, "requirements": []})
            elif heading == "Traceability":
                section = "traceability"
            else:
                raise ParseError("unknown section: %r" % heading, lineno)
        elif line.startswith("- "):
            entry = line[2:].strip()
            if section is None:
                raise ParseError("entry outside a section: %r" % line, lineno)
            if section == "traceability":
                if " -> " not in entry:
                    raise ParseError("invalid trace link: %r" % line, lineno)
                src, dst = entry.split(" -> ", 1)
                doc["traceability"].append(
                    {"from": src.strip(), "to": dst.strip()})
            else:
                doc["moscow"][-1]["requirements"].append(
                    _srs_requirement(entry, lineno))
        else:
            raise ParseError("unparsable line: %r" % line, lineno)

    if doc["project"] is None:
        raise ParseError("missing '# SRS:' header", 1)
    return doc


def _srs_requirement(entry, lineno):
    if ":" not in entry:
        raise ParseError("invalid requirement (missing id or text): %r" % entry,
                         lineno)
    req_id, rest = entry.split(":", 1)
    req_id = req_id.strip()
    if not REQ_ID_RE.match(req_id):
        raise ParseError("invalid requirement id: %r" % req_id, lineno)
    rest = rest.strip()
    acceptance = None
    satisfied_by = []
    if " accept: " in rest:
        rest, acceptance = rest.split(" accept: ", 1)
        if " => " in acceptance:
            acceptance, refs = acceptance.split(" => ", 1)
            satisfied_by = [r.strip() for r in refs.split(",")]
            if not all(satisfied_by):
                raise ParseError("empty artifact reference: %r" % entry, lineno)
            acceptance = acceptance.strip()
    elif " => " in rest:
        rest, refs = rest.split(" => ", 1)
        satisfied_by = [r.strip() for r in refs.split(",")]
        if not all(satisfied_by):
            raise ParseError("empty artifact reference: %r" % entry, lineno)
    if not rest:
        raise ParseError("empty requirement text: %r" % entry, lineno)
    return {"id": req_id, "text": rest, "acceptance": acceptance,
            "satisfiedBy": satisfied_by}


# ---------------------------------------------------------------------------
# AiSpec (.ai)
# ---------------------------------------------------------------------------

def parse_ai(text):
    doc = {"component": None, "description": None, "dependencies": [],
           "namespace": None, "version": None, "requirements": [],
           "endpoints": [], "dataModel": [], "compliance": None}
    compliance = {"adrReferences": [], "requirementLinks": []}
    section = None
    entity = None

    for lineno, line in _read_lines(text):
        if doc["component"] is None:
            if line.startswith("# Component: "):
                doc["component"] = _identifier(
                    line[len("# Component: "):].strip(), lineno, "component name")
                continue
            raise ParseError("expected '# Component: <name>' header", lineno)
        elif section is None and line.startswith("## "):
            if line.startswith("## Description: "):
                doc["description"] = line[len("## Description: "):].strip()
            elif line.startswith("## Dependencies: "):
                raw = line[len("## Dependencies: "):].strip()
                doc["dependencies"] = [
                    _identifier(item, lineno, "component name")
                    for item in _split_list(raw, lineno, "dependency")]
            elif line.startswith("## Namespace: "):
                ns = line[len("## Namespace: "):].strip()
                if not QUALIFIED_RE.match(ns):
                    raise ParseError("invalid namespace: %r" % ns, lineno)
                doc["namespace"] = ns
            elif line.startswith("## Version: "):
                doc["version"] = _version(line[len("## Version: "):].strip(), lineno)
            else:
                raise ParseError("unknown metadata line: %r" % line, lineno)
        elif line.startswith("### "):
            heading = line[len("### "):].strip()
            if heading == "Requirements":
                section = "requirements"
            elif heading == "API Endpoints":
                section = "endpoints"
            elif heading == "Data Model":
                section = "data-model"
                entity = None
            elif heading == "Compliance":
                section = "compliance"
            else:
                raise ParseError("unknown section: %r" % heading, lineno)
        elif line.startswith("- ") or line.startswith("\t") or line[:1] == " ":
            stripped = line.strip()
            if not stripped.startswith("- "):
                raise ParseError("invalid entry line: %r" % line, lineno)
            entry = stripped[2:].strip()
            if section is None:
                raise ParseError("entry outside a section: %r" % line, lineno)
            if section == "requirements":
                _ai_requirement(doc, entry, lineno)
            elif section == "endpoints":
                _ai_endpoint(doc, entry, lineno)
            elif section == "data-model":
                if line[:1] in (" ", "\t") or line.startswith("\t"):
                    if entity is None:
                        raise ParseError("field without an entity: %r" % line,
                                         lineno)
                    entity["fields"].append(_ai_field(entry, lineno))
                else:
                    entity = {"entity": _identifier(entry, lineno),
                              "fields": []}
                    doc["dataModel"].append(entity)
            elif section == "compliance":
                if entry.startswith("complies-with "):
                    adr = entry[len("complies-with "):].strip()
                    if not ADR_ID_RE.match(adr):
                        raise ParseError("invalid ADR id: %r" % adr, lineno)
                    compliance["adrReferences"].append(adr)
                elif entry.startswith("satisfies "):
                    compliance["requirementLinks"].append(
                        _requirement_id(entry[len("satisfies "):].strip(), lineno))
                else:
                    raise ParseError("invalid compliance entry: %r" % entry, lineno)
            else:
                raise ParseError("unparsable line: %r" % line, lineno)
        else:
            raise ParseError("unparsable line: %r" % line, lineno)

    if doc["component"] is None:
        raise ParseError("missing '# Component:' header", 1)
    doc["compliance"] = compliance
    return doc


def _ai_requirement(doc, entry, lineno):
    match = re.match(r"^((?:REQ|M|S|C|W)-[0-9]+): (.+)$", entry)
    if match:
        doc["requirements"].append(
            {"id": match.group(1), "kind": "declared", "text": match.group(2).strip()})
        return
    match = re.match(r"^Must (.+)$", entry)
    if match:
        doc["requirements"].append(
            {"id": None, "kind": "must", "text": match.group(1).strip()})
        return
    match = re.match(r"^Should (.+)$", entry)
    if match:
        doc["requirements"].append(
            {"id": None, "kind": "should", "text": match.group(1).strip()})
        return
    raise ParseError("invalid requirement entry: %r" % entry, lineno)


def _ai_endpoint(doc, entry, lineno):
    match = re.match(r"^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS) (\S+): (.+)$", entry)
    if not match:
        raise ParseError("invalid endpoint entry: %r" % entry, lineno)
    doc["endpoints"].append({"method": match.group(1),
                             "route": _route(match.group(2), lineno),
                             "description": match.group(3).strip()})


def _ai_field(entry, lineno):
    match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*): (\S+)$", entry)
    if not match:
        raise ParseError("invalid field entry: %r" % entry, lineno)
    return {"name": match.group(1),
            "type": _type_name(match.group(2), lineno)}


def _type_name(text, lineno):
    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*(?:\?|\[\])?$", text):
        raise ParseError("invalid type name: %r" % text, lineno)
    return text


# ---------------------------------------------------------------------------
# TestSpec (.test)
# ---------------------------------------------------------------------------

def parse_test(text):
    doc = {"component": None, "target": None, "coverage": {},
           "scenarios": [], "edgeCases": [], "performance": [],
           "requirementCoverage": []}
    section = None

    for lineno, line in _read_lines(text):
        if doc["component"] is None:
            if line.startswith("# Test: "):
                doc["component"] = _identifier(
                    line[len("# Test: "):].strip(), lineno, "component name")
                continue
            raise ParseError("expected '# Test: <component>' header", lineno)
        elif section is None and line.startswith("## "):
            if line.startswith("## Target: "):
                target = line[len("## Target: "):].strip()
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_.]*\.(cs|fs|ts)$", target):
                    raise ParseError("invalid target file reference: %r" % target,
                                     lineno)
                doc["target"] = target
            elif line.startswith("## Coverage: "):
                raw = line[len("## Coverage: "):].strip()
                for rule in _split_list(raw, lineno, "coverage rule"):
                    _test_coverage_rule(doc, rule, lineno)
            else:
                raise ParseError("unknown metadata line: %r" % line, lineno)
        elif line.startswith("### "):
            heading = line[len("### "):].strip()
            if heading == "Test Scenarios":
                section = "scenarios"
            elif heading == "Edge Cases":
                section = "edge-cases"
            elif heading == "Performance Tests":
                section = "performance"
            elif heading == "RequirementCoverage":
                section = "requirement-coverage"
            else:
                raise ParseError("unknown section: %r" % heading, lineno)
        elif line.startswith("- "):
            entry = line[2:].strip()
            if section is None:
                raise ParseError("entry outside a section: %r" % line, lineno)
            if section in ("scenarios", "edge-cases"):
                scenario = _test_scenario(entry, lineno)
                (doc["scenarios"] if section == "scenarios"
                 else doc["edgeCases"]).append(scenario)
            elif section == "performance":
                doc["performance"].append(_test_performance(entry, lineno))
            else:
                if not entry.startswith("Covers "):
                    raise ParseError("invalid requirement coverage entry: %r"
                                     % entry, lineno)
                doc["requirementCoverage"].append(
                    _requirement_id(entry[len("Covers "):].strip(), lineno))
        else:
            raise ParseError("unparsable line: %r" % line, lineno)

    if doc["component"] is None:
        raise ParseError("missing '# Test:' header", 1)
    return doc


def _test_coverage_rule(doc, rule, lineno):
    match = re.match(r"^([0-9]+(?:\.[0-9]+)?)% (scenario-coverage|requirement-coverage)$",
                     rule)
    if match:
        key = "scenarioCoverage" if match.group(2) == "scenario-coverage" \
            else "requirementCoverage"
        if key in doc["coverage"]:
            raise ParseError("duplicate coverage rule: %r" % rule, lineno)
        doc["coverage"][key] = _number(match.group(1), lineno)
    elif rule == "must-level":
        if "mustLevel" in doc["coverage"]:
            raise ParseError("duplicate coverage rule: %r" % rule, lineno)
        doc["coverage"]["mustLevel"] = True
    else:
        raise ParseError("invalid coverage rule: %r" % rule, lineno)


def _test_scenario(entry, lineno):
    match = re.match(r"^Given (.+) When (.+) Then (.+)$", entry)
    if match:
        return {"kind": "gwt", "given": match.group(1).strip(),
                "when": match.group(2).strip(), "then": match.group(3).strip()}
    match = re.match(r"^Should (.+)$", entry)
    if match:
        return {"kind": "should", "text": match.group(1).strip()}
    raise ParseError("invalid scenario entry: %r" % entry, lineno)


def _test_performance(entry, lineno):
    match = re.match(
        r"^Should (.+?) (under|within) ([0-9]+(?:\.[0-9]+)?) (ms|s|min)$", entry)
    if match:
        return {"text": match.group(1).strip(),
                "threshold": {"comparator": match.group(2),
                              "value": _number(match.group(3), lineno),
                              "unit": match.group(4)}}
    match = re.match(
        r"^Should (.+?) at least ([0-9]+(?:\.[0-9]+)?) (rps|ops)$", entry)
    if match:
        return {"text": match.group(1).strip(),
                "threshold": {"comparator": "at-least",
                              "value": _number(match.group(2), lineno),
                              "unit": match.group(3)}}
    match = re.match(
        r"^Should (.+?) with at most ([0-9]+(?:\.[0-9]+)?) % errors$", entry)
    if match:
        return {"text": match.group(1).strip(),
                "threshold": {"comparator": "at-most",
                              "value": _number(match.group(2), lineno),
                              "unit": "%"}}
    raise ParseError("invalid performance entry: %r" % entry, lineno)


# ---------------------------------------------------------------------------
# ApiSpec (.api)
# ---------------------------------------------------------------------------

def parse_api(text):
    doc = {"interface": None, "version": None, "authentication": None,
           "baseRoute": None, "status": "active", "deprecatedSince": None,
           "endpoints": [], "schemas": [], "errorContracts": []}
    section = None

    for lineno, line in _read_lines(text):
        if doc["interface"] is None:
            if line.startswith("# Interface: "):
                doc["interface"] = _identifier(
                    line[len("# Interface: "):].strip(), lineno, "interface name")
                continue
            raise ParseError("expected '# Interface: <name>' header", lineno)
        elif section is None and line.startswith("## "):
            if line.startswith("## Version: "):
                doc["version"] = _version(line[len("## Version: "):].strip(), lineno)
            elif line.startswith("## Authentication: "):
                scheme = line[len("## Authentication: "):].strip()
                if scheme not in AUTH_SCHEMES:
                    raise ParseError("invalid auth scheme: %r" % scheme, lineno)
                doc["authentication"] = scheme
            elif line.startswith("## BaseRoute: "):
                doc["baseRoute"] = _route(
                    line[len("## BaseRoute: "):].strip(), lineno)
            elif line.startswith("## Status: "):
                rest = line[len("## Status: "):].strip()
                match = re.match(r"^deprecated since ([0-9]+(?:\.[0-9]+)*)$", rest)
                if not match:
                    raise ParseError("invalid status line: %r" % rest, lineno)
                doc["status"] = "deprecated"
                doc["deprecatedSince"] = match.group(1)
            else:
                raise ParseError("unknown metadata line: %r" % line, lineno)
        elif line.startswith("### "):
            heading = line[len("### "):].strip()
            if heading == "Endpoints":
                section = "endpoints"
            elif heading == "Schemas":
                section = "schemas"
            elif heading == "ErrorContracts":
                section = "errors"
            else:
                raise ParseError("unknown section: %r" % heading, lineno)
        elif line.startswith("- "):
            entry = line[2:].strip()
            if section is None:
                raise ParseError("entry outside a section: %r" % line, lineno)
            if section == "endpoints":
                doc["endpoints"].append(_api_endpoint(entry, lineno))
            elif section == "schemas":
                doc["schemas"].append(_api_schema(entry, lineno))
            else:
                doc["errorContracts"].append(_api_error(entry, lineno))
        else:
            raise ParseError("unparsable line: %r" % line, lineno)

    if doc["interface"] is None:
        raise ParseError("missing '# Interface:' header", 1)
    return doc


def _api_endpoint(entry, lineno):
    match = re.match(
        r"^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS) (\S+): (.+?)"
        r"(?: => ([1-5][0-9][0-9]): ([A-Za-z_][A-Za-z0-9_]*))?$", entry)
    if not match:
        raise ParseError("invalid endpoint entry: %r" % entry, lineno)
    return {"method": match.group(1),
            "route": _route(match.group(2), lineno),
            "description": match.group(3).strip(),
            "responses": ([{"statusCode": int(match.group(4)),
                             "schema": match.group(5)}]
                           if match.group(4) else [])}


def _api_schema(entry, lineno):
    name, _, field_list = entry.partition(":")
    name = name.strip()
    if not IDENT_RE.match(name) or not _:
        raise ParseError("invalid schema entry: %r" % entry, lineno)
    fields = []
    for raw_field in field_list.split(";"):
        raw_field = raw_field.strip()
        if not raw_field:
            raise ParseError("empty schema field in: %r" % entry, lineno)
        fields.append(_api_field(raw_field, lineno))
    return {"name": name, "fields": fields}


def _api_field(raw_field, lineno):
    # Split "name: Type <constraints...>" first (the type itself never
    # contains spaces per the grammar), then tokenize the constraint tail,
    # keeping quoted pattern literals together (patterns may contain
    # spaces inside the quotes).
    match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*): (\S+)(?: (.*))?$", raw_field)
    if not match:
        raise ParseError("invalid field: %r" % raw_field, lineno)
    name, type_name, tail = match.group(1), match.group(2), match.group(3) or ""
    constraints = []
    if tail:
        for token in re.findall(r'\S*"[^"]*"\S*|[^\s"]+', tail):
            if token in ("required", "nullable", "readOnly"):
                constraints.append({"kind": token})
            elif token.startswith("min="):
                constraints.append({"kind": "min",
                                   "value": _number(token[len("min="):], lineno)})
            elif token.startswith("max="):
                constraints.append({"kind": "max",
                                   "value": _number(token[len("max="):], lineno)})
            elif token.startswith("pattern="):
                value = token[len("pattern="):]
                if not (value.startswith('"') and value.endswith('"')
                        and len(value) >= 2):
                    raise ParseError("invalid pattern literal: %r" % token, lineno)
                constraints.append({"kind": "pattern", "value": value[1:-1]})
            else:
                raise ParseError("invalid field constraint: %r" % token, lineno)
    return {"name": name, "type": _type_name(type_name, lineno),
            "constraints": constraints}


def _api_error(entry, lineno):
    match = re.match(r"^([1-5][0-9][0-9]): (.+) code=([A-Z][A-Z0-9_]+)$", entry)
    if not match:
        raise ParseError("invalid error contract entry: %r" % entry, lineno)
    return {"statusCode": int(match.group(1)),
            "description": match.group(2).strip(),
            "code": match.group(3)}


# ---------------------------------------------------------------------------
# ModelSpec (.model)
# ---------------------------------------------------------------------------

def parse_model(text):
    doc = {"model": None, "entities": [], "relationships": [], "invariants": []}
    section = None

    for lineno, line in _read_lines(text):
        if doc["model"] is None:
            if line.startswith("# Model: "):
                doc["model"] = _identifier(
                    line[len("# Model: "):].strip(), lineno, "model name")
                continue
            raise ParseError("expected '# Model: <name>' header", lineno)
        elif line.startswith("### "):
            heading = line[len("### "):].strip()
            if heading == "Entities":
                section = "entities"
            elif heading == "Relationships":
                section = "relationships"
            elif heading == "Invariants":
                section = "invariants"
            else:
                raise ParseError("unknown section: %r" % heading, lineno)
        elif line.lstrip().startswith("- "):
            entry = line.strip()[2:].strip()
            if section is None:
                raise ParseError("entry outside a section: %r" % line, lineno)
            if section == "entities":
                if line[:1] in (" ", "\t"):
                    if not doc["entities"]:
                        raise ParseError("field without an entity: %r" % line,
                                         lineno)
                    doc["entities"][-1]["fields"].append(_model_field(entry, lineno))
                else:
                    doc["entities"].append(_model_entity(entry, lineno))
            elif section == "relationships":
                doc["relationships"].append(_model_relationship(entry, lineno))
            else:
                match = re.match(r"^(INV-[0-9]+): (.+)$", entry)
                if not match:
                    raise ParseError("invalid invariant entry: %r" % entry, lineno)
                doc["invariants"].append(
                    {"id": match.group(1), "text": match.group(2).strip()})
        else:
            raise ParseError("unparsable line: %r" % line, lineno)

    if doc["model"] is None:
        raise ParseError("missing '# Model:' header", 1)
    return doc


def _model_entity(entry, lineno):
    match = re.match(r"^(entity|value-object|enum) ([A-Za-z_][A-Za-z0-9_]*)"
                     r"(?: extends ([A-Za-z_][A-Za-z0-9_]*))?$", entry)
    if not match:
        raise ParseError("invalid entity entry: %r" % entry, lineno)
    return {"kind": match.group(1), "name": match.group(2),
            "extends": match.group(3), "fields": []}


def _model_type(text, lineno):
    match = re.match(r"^Array<(.+)>$", text)
    if match:
        _model_type(match.group(1), lineno)  # validate the inner type recursively
        return text
    if text in PRIMITIVES or (text.endswith("?") and text[:-1] in PRIMITIVES):
        return text
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*\??$", text):
        return text
    raise ParseError("invalid type name: %r" % text, lineno)


def _model_field(entry, lineno):
    match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*): (\S+)(?: (.*))?$", entry)
    if not match:
        raise ParseError("invalid field entry: %r" % entry, lineno)
    name, type_name, tail = match.group(1), match.group(2), match.group(3) or ""
    modifiers = []
    default = None
    tokens = tail.split() if tail else []
    if not tokens and tail:
        raise ParseError("invalid field modifiers: %r" % entry, lineno)
    for token in tokens:
        if token in ("key", "required", "unique", "indexed", "immutable"):
            modifiers.append(token)
        elif token.startswith("default="):
            default = _model_literal(token[len("default="):], lineno)
        else:
            raise ParseError("invalid field modifier: %r" % token, lineno)
    return {"name": name, "type": _model_type(type_name, lineno),
            "modifiers": modifiers, "default": default}


def _model_literal(text, lineno):
    if text == "true":
        return True
    if text == "false":
        return False
    if NUMBER_RE.match(text):
        return int(text) if "." not in text else float(text)
    if re.match(r'^"[^"]*"$', text):
        return text[1:-1]
    raise ParseError("invalid default literal: %r" % text, lineno)


def _model_relationship(entry, lineno):
    match = re.match(
        r"^([A-Za-z_][A-Za-z0-9_]*) (1-1|1-\*|\*-1|\*-\*) "
        r"([A-Za-z_][A-Za-z0-9_]*)(?:: (.*))?$", entry)
    if not match:
        raise ParseError("invalid relationship entry: %r" % entry, lineno)
    return {"from": match.group(1), "cardinality": match.group(2),
            "to": match.group(3), "description":
                (match.group(4).strip() if match.group(4) else None)}


# ---------------------------------------------------------------------------
# NsSpec (.ns)
# ---------------------------------------------------------------------------

def parse_ns(text):
    doc = {"system": None, "appliesTo": [], "performance": [], "scalability": [],
           "security": [], "compliance": []}
    section = None

    for lineno, line in _read_lines(text):
        if doc["system"] is None:
            if line.startswith("# NFR: "):
                doc["system"] = _identifier(
                    line[len("# NFR: "):].strip(), lineno, "system name")
                continue
            raise ParseError("expected '# NFR: <system>' header", lineno)
        elif section is None and line.startswith("## AppliesTo: "):
            raw = line[len("## AppliesTo: "):].strip()
            doc["appliesTo"] = _split_list(raw, lineno, "scope")
        elif line.startswith("### "):
            heading = line[len("### "):].strip()
            if heading == "Performance":
                section = "performance"
            elif heading == "Scalability":
                section = "scalability"
            elif heading == "Security":
                section = "security"
            elif heading == "Compliance":
                section = "compliance"
            else:
                raise ParseError("unknown section: %r" % heading, lineno)
        elif line.startswith("- "):
            entry = line[2:].strip()
            if section is None:
                raise ParseError("entry outside a section: %r" % line, lineno)
            if section in ("performance", "scalability"):
                nfr = _ns_nfr(entry, lineno)
                (doc["performance"] if section == "performance"
                 else doc["scalability"]).append(nfr)
            elif section == "security":
                doc["security"].append(_ns_security(entry, lineno))
            else:
                framework, sep, description = entry.partition(": ")
                if not sep or not FRAMEWORK_RE.match(framework):
                    raise ParseError("invalid compliance entry: %r" % entry, lineno)
                doc["compliance"].append(
                    {"framework": framework, "description": description.strip()})
        else:
            raise ParseError("unparsable line: %r" % line, lineno)

    if doc["system"] is None:
        raise ParseError("missing '# NFR:' header", 1)
    return doc


def _ns_bound(text, lineno):
    match = re.match(r"^(<=|>=|==) ([0-9]+(?:\.[0-9]+)?) (\S+)$", text)
    if match:
        unit = match.group(3)
        if unit not in NS_UNITS:
            raise ParseError("invalid unit: %r" % unit, lineno)
        return {"comparator": match.group(1),
                "value": _number(match.group(2), lineno), "unit": unit}
    match = re.match(r"^between ([0-9]+(?:\.[0-9]+)?) and ([0-9]+(?:\.[0-9]+)?) (\S+)$",
                     text)
    if match:
        unit = match.group(3)
        if unit not in NS_UNITS:
            raise ParseError("invalid unit: %r" % unit, lineno)
        return {"comparator": "between", "min": _number(match.group(1), lineno),
                "max": _number(match.group(2), lineno), "unit": unit}
    raise ParseError("invalid bound: %r" % text, lineno)


def _ns_nfr(entry, lineno):
    match = re.match(
        r"^((?:PERF|SCAL|AVAIL)-[0-9]+) \((\w+)\): (.+)$", entry)
    if not match or match.group(2) not in NS_KINDS:
        raise ParseError("invalid NFR entry: %r" % entry, lineno)
    nfr_id, kind = match.group(1), match.group(2)
    rest = match.group(3)

    note = None
    adr = None
    adr_match = re.search(r"\s+adr: (ADR-[0-9]+)$", rest)
    if adr_match:
        adr = adr_match.group(1)
        rest = rest[:adr_match.start()]
    note_match = re.search(r"\s+\(([^)]+)\)", rest)
    if note_match:
        note = note_match.group(1)
        rest = rest[:note_match.start()]
    return {"id": nfr_id, "kind": kind, "bound": _ns_bound(rest.strip(), lineno),
            "note": note, "adr": adr}


def _ns_security(entry, lineno):
    match = re.match(r"^(SEC-[0-9]+): (\w+): (.+)$", entry)
    if not match:
        raise ParseError("invalid security entry: %r" % entry, lineno)
    sec_id, control, value = match.group(1), match.group(2), match.group(3).strip()
    if control == "authn":
        if value not in AUTH_SCHEMES or value == "none":
            raise ParseError("invalid auth scheme: %r" % value, lineno)
        return {"id": sec_id, "control": {"kind": "authn", "value": value}}
    if control == "authz":
        return {"id": sec_id,
                "control": {"kind": "authz", "value": _identifier(value, lineno)}}
    if control == "encrypt":
        if value not in CIPHERS and not IDENT_RE.match(value):
            raise ParseError("invalid cipher: %r" % value, lineno)
        return {"id": sec_id, "control": {"kind": "encrypt", "value": value}}
    if control == "classification":
        if value not in CLASSIFICATIONS:
            raise ParseError("invalid classification: %r" % value, lineno)
        return {"id": sec_id, "control": {"kind": "classification", "value": value}}
    if control == "egress":
        return {"id": sec_id, "control": {"kind": "egress",
                                          "bound": _ns_bound(value, lineno)}}
    raise ParseError("invalid security control: %r" % control, lineno)


# ---------------------------------------------------------------------------
# AdrSpec (.adr)
# ---------------------------------------------------------------------------

def parse_adr(text):
    lines = text.split("\n")
    index = 0
    # skip leading blank lines
    while index < len(lines) and not lines[index].strip():
        index += 1
    if index >= len(lines) or lines[index].strip() != "---":
        raise ParseError("expected '---' front-matter opener", index + 1)
    index += 1
    front = {}
    while index < len(lines) and lines[index].strip() != "---":
        lineno = index + 1
        line = lines[index].strip()
        if line:
            key, sep, value = line.partition(":")
            if not sep:
                raise ParseError("invalid front-matter line: %r" % line, lineno)
            front[key.strip()] = value.strip()
        index += 1
    if index >= len(lines):
        raise ParseError("unterminated front-matter", index + 1)
    index += 1

    doc = {"id": None, "title": None, "status": None, "date": None,
           "author": None, "supersedes": [], "relatedRequirements": [],
           "headerTitle": None, "statusSection": None, "context": [],
           "decision": [], "consequences": [], "alternatives": [],
           "compliance": []}

    if front.get("id", "") and ADR_ID_RE.match(front["id"]):
        doc["id"] = front["id"]
    else:
        raise ParseError("front-matter 'id: ADR-<n>' is required", 1)
    if front.get("title"):
        doc["title"] = front["title"]
    else:
        raise ParseError("front-matter 'title:' is required", 1)
    if front.get("status") in ADR_STATUSES:
        doc["status"] = front["status"]
    else:
        raise ParseError("front-matter 'status:' must be one of %s"
                         % ", ".join(ADR_STATUSES), 1)
    if front.get("date") and ISO_DATE_RE.match(front["date"]):
        doc["date"] = front["date"]
    else:
        raise ParseError("front-matter 'date: YYYY-MM-DD' is required", 1)
    if front.get("author") and IDENT_RE.match(front["author"]):
        doc["author"] = front["author"]
    else:
        raise ParseError("front-matter 'author:' is required", 1)
    if "supersedes" in front:
        doc["supersedes"] = _adr_list(front["supersedes"], ADR_ID_RE, "ADR id")
    if "related_requirements" in front:
        doc["relatedRequirements"] = _adr_list(
            front["related_requirements"], REQ_ID_RE, "requirement id")

    section = None
    while index < len(lines):
        line = lines[index].rstrip("\r")
        lineno = index + 1
        index += 1
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("# ADR-"):
            if doc["headerTitle"] is not None:
                raise ParseError("duplicate ADR header", lineno)
            match = re.match(r"^# (ADR-[0-9]+) (.+)$", stripped)
            if not match:
                raise ParseError("invalid ADR header: %r" % stripped, lineno)
            if match.group(1) != doc["id"]:
                raise ParseError(
                    "ADR header id %s does not match front-matter id %s"
                    % (match.group(1), doc["id"]), lineno)
            doc["headerTitle"] = match.group(2).strip()
        elif stripped.startswith("## "):
            heading = stripped[len("## "):].strip()
            if heading in ("Status", "Context", "Decision", "Consequences",
                           "Alternatives", "Compliance"):
                section = heading
            else:
                raise ParseError("unknown section: %r" % heading, lineno)
        elif stripped.startswith("- "):
            entry = stripped[2:].strip()
            if section == "Consequences":
                match = re.match(r"^\*\*(Positive|Negative|Neutral):\*\* (.+)$", entry)
                if not match:
                    raise ParseError("invalid consequence entry: %r" % entry, lineno)
                doc["consequences"].append(
                    {"kind": match.group(1).lower(), "text": match.group(2).strip()})
            elif section == "Alternatives":
                doc["alternatives"].append(entry)
            elif section == "Compliance":
                match = re.match(r"^component: ([A-Za-z_][A-Za-z0-9_]*) must conform$",
                                 entry)
                if not match:
                    raise ParseError("invalid compliance entry: %r" % entry, lineno)
                doc["compliance"].append(match.group(1))
            else:
                raise ParseError("entry outside a list section: %r" % stripped,
                                 lineno)
        else:
            if section == "Status":
                if stripped not in ADR_STATUSES:
                    raise ParseError("invalid status: %r" % stripped, lineno)
                if stripped != doc["status"]:
                    raise ParseError(
                        "status section %r does not match front-matter status %r"
                        % (stripped, doc["status"]), lineno)
                doc["statusSection"] = stripped
            elif section == "Context":
                doc["context"].append(stripped)
            elif section == "Decision":
                doc["decision"].append(stripped)
            else:
                raise ParseError("unparsable line: %r" % stripped, lineno)

    if doc["headerTitle"] is None:
        raise ParseError("missing '# ADR-<n> <title>' header", 1)
    return doc


def _adr_list(raw, pattern, what):
    raw = raw.strip()
    if not (raw.startswith("[") and raw.endswith("]")):
        raise ParseError("expected bracketed list: %r" % raw, 1)
    inner = raw[1:-1].strip()
    if not inner:
        return []
    items = [item.strip() for item in inner.split(",")]
    for item in items:
        if not pattern.match(item):
            raise ParseError("invalid %s: %r" % (what, item), 1)
    return items


# ---------------------------------------------------------------------------
# SolutionManifest (.manifest)
# ---------------------------------------------------------------------------

def parse_manifest(text):
    doc = {"solution": None, "projects": [], "specs": [], "generations": [],
           "exclusions": []}

    for lineno, line in _read_lines(text):
        if doc["solution"] is None:
            if line.startswith("Solution: "):
                name = line[len("Solution: "):].strip()
                if not MANIFEST_IDENT_RE.match(name):
                    raise ParseError("invalid solution name: %r" % name, lineno)
                doc["solution"] = name
                continue
            raise ParseError("expected 'Solution: <name>' header", lineno)
        if line.startswith("Project: "):
            rest = line[len("Project: "):].strip()
            match = re.match(r"^(\S+) -> (\S+)(?: tfm: (\S+))?$", rest)
            if not match or not MANIFEST_IDENT_RE.match(match.group(1)):
                raise ParseError("invalid project declaration: %r" % line, lineno)
            doc["projects"].append({"name": match.group(1),
                                    "path": match.group(2),
                                    "tfm": match.group(3)})
        elif line.startswith("Spec: "):
            rest = line[len("Spec: "):].strip()
            match = re.match(r"^(\S+) -> (\S+)$", rest)
            if not match:
                raise ParseError("invalid spec declaration: %r" % line, lineno)
            doc["specs"].append({"path": match.group(1), "project": match.group(2)})
        elif line.startswith("Generate: "):
            rest = line[len("Generate: "):].strip()
            match = re.match(r"^(\S+) for (\S+)(?: -> (\S+))?$", rest)
            if not match or not IDENT_RE.match(match.group(1)) \
                    or match.group(2) not in SPEC_TYPES:
                raise ParseError("invalid generation declaration: %r" % line, lineno)
            doc["generations"].append({"generator": match.group(1),
                                       "specType": match.group(2),
                                       "target": match.group(3)})
        elif line.startswith("Exclude: "):
            rest = line[len("Exclude: "):].strip()
            match = re.match(r"^(\S+)(?: reason: (.+))?$", rest)
            if not match:
                raise ParseError("invalid exclusion declaration: %r" % line, lineno)
            doc["exclusions"].append(
                {"path": match.group(1),
                 "reason": (match.group(2).strip() if match.group(2) else None)})
        else:
            raise ParseError("unparsable declaration: %r" % line, lineno)

    if doc["solution"] is None:
        raise ParseError("missing 'Solution:' header", 1)
    return doc


PARSERS = {
    ".srs": parse_srs,
    ".ai": parse_ai,
    ".test": parse_test,
    ".api": parse_api,
    ".model": parse_model,
    ".ns": parse_ns,
    ".adr": parse_adr,
    ".manifest": parse_manifest,
}


# ---------------------------------------------------------------------------
# AST envelope
# ---------------------------------------------------------------------------

def build_ast(spec_path, rel_path, text):
    """Parse one spec file and wrap the AST in the versioned envelope."""
    ext = os.path.splitext(spec_path)[1]
    if ext not in PARSERS:
        raise ParseError("unknown SpecTree extension: %r" % ext, 0)
    ast = PARSERS[ext](text)
    return {
        "schema": SCHEMA_NAME,
        "schemaVersion": SCHEMA_VERSION,
        "astType": AST_TYPE_BY_EXT[ext],
        "source": {
            "path": rel_path.replace(os.sep, "/"),
            "grammar": GRAMMAR_BY_EXT[ext],
            "grammarCommit": GRAMMAR_COMMIT,
        },
        "ast": ast,
    }


def ast_to_json(document):
    """Serialize an AST envelope deterministically (byte-stable)."""
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


# ---------------------------------------------------------------------------
# Minimal JSON Schema validator (subset used by spectree-ast-v1.schema.json)
# ---------------------------------------------------------------------------

def _type_ok(instance, expected):
    if expected == "object":
        return isinstance(instance, dict)
    if expected == "array":
        return isinstance(instance, list)
    if expected == "string":
        return isinstance(instance, str)
    if expected == "integer":
        return isinstance(instance, int) and not isinstance(instance, bool)
    if expected == "number":
        return isinstance(instance, (int, float)) and not isinstance(instance, bool)
    if expected == "boolean":
        return isinstance(instance, bool)
    if expected == "null":
        return instance is None
    return False


def schema_errors(instance, schema, root, path="$"):
    """Validate `instance` against the supported JSON Schema subset.

    Supported keywords: $ref, allOf, oneOf, type (scalar or list),
    enum, pattern, properties, required, additionalProperties, items,
    minLength.
    """
    errors = []
    if "$ref" in schema:
        ref = schema["$ref"]
        if not ref.startswith("#/$defs/"):
            return ["%s: unsupported $ref %r" % (path, ref)]
        target = root.get("$defs", {}).get(ref[len("#/$defs/"):])
        if target is None:
            return ["%s: unresolvable $ref %r" % (path, ref)]
        return schema_errors(instance, target, root, path)

    if "allOf" in schema:
        for subschema in schema["allOf"]:
            errors.extend(schema_errors(instance, subschema, root, path))
        return errors

    if "oneOf" in schema:
        matches = 0
        for subschema in schema["oneOf"]:
            if not schema_errors(instance, subschema, root, path):
                matches += 1
        if matches != 1:
            errors.append("%s: matched %d oneOf branches (expected 1)"
                          % (path, matches))
        return errors

    expected = schema.get("type")
    if expected is not None:
        candidates = expected if isinstance(expected, list) else [expected]
        if not any(_type_ok(instance, candidate) for candidate in candidates):
            errors.append("%s: expected %s, got %r"
                          % (path, expected, type(instance).__name__))

    if "enum" in schema and instance not in schema["enum"]:
        errors.append("%s: %r is not one of %r" % (path, instance, schema["enum"]))

    if "pattern" in schema and isinstance(instance, str):
        if not re.search(schema["pattern"], instance):
            errors.append("%s: %r does not match pattern %r"
                          % (path, instance, schema["pattern"]))

    if "minLength" in schema and isinstance(instance, str):
        if len(instance) < schema["minLength"]:
            errors.append("%s: shorter than minLength %d"
                          % (path, schema["minLength"]))

    if isinstance(instance, dict):
        for key in schema.get("required", []):
            if key not in instance:
                errors.append("%s: missing required property %r" % (path, key))
        properties = schema.get("properties", {})
        for key, value in instance.items():
            child = "%s.%s" % (path, key)
            if key in properties:
                errors.extend(schema_errors(value, properties[key], root, child))
            elif schema.get("additionalProperties") is False:
                errors.append("%s: unexpected property %r" % (path, key))

    if isinstance(instance, list) and "items" in schema:
        for i, value in enumerate(instance):
            errors.extend(schema_errors(value, schema["items"], root,
                                         "%s[%d]" % (path, i)))
    return errors


# ---------------------------------------------------------------------------
# Command-line interface
# ---------------------------------------------------------------------------

def _example_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_schema():
    schema_path = os.path.join(_example_root(), "spectree", "schemas",
                               "spectree-ast-v1.schema.json")
    with open(schema_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_file(path, root):
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    rel_path = os.path.relpath(path, root).replace(os.sep, "/")
    return build_ast(path, rel_path, text)


def parse_all(root, out_dir, stdout=False):
    specs_dir = os.path.join(root, "spectree", "specs")
    schema = load_schema()
    if not stdout:
        os.makedirs(out_dir, exist_ok=True)
    count = 0
    for name in sorted(os.listdir(specs_dir)):
        path = os.path.join(specs_dir, name)
        if not os.path.isfile(path):
            continue
        ext = os.path.splitext(name)[1]
        if ext not in PARSERS:
            continue
        document = parse_file(path, root)
        errors = schema_errors(document, schema, schema)
        if errors:
            raise ParseError("AST fails schema validation: %s" % errors[0], 0)
        payload = ast_to_json(document)
        if stdout:
            sys.stdout.write(payload)
        else:
            out_path = os.path.join(out_dir, name + ".ast.json")
            with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(payload)
        count += 1
    return count


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Deterministic SpecTree parser (issues #22/#23)")
    parser.add_argument("--spec", metavar="FILE",
                        help="parse a single specification file, AST to stdout")
    parser.add_argument("--all", action="store_true",
                        help="parse all specs under spectree/specs/ and write "
                             "ASTs to docs/generated/spectree/")
    parser.add_argument("--selftest", action="store_true",
                        help="run the embedded parser unit tests")
    parser.add_argument("--out-dir", default=None,
                        help="output directory for --all (default: "
                             "docs/generated/spectree under the example root)")
    args = parser.parse_args(argv)

    root = _example_root()

    if args.selftest:
        return run_selftest(root)

    if args.spec:
        document = parse_file(args.spec, root)
        schema = load_schema()
        errors = schema_errors(document, schema, schema)
        if errors:
            sys.stderr.write("AST schema validation failed:\n  %s\n"
                             % "\n  ".join(errors[:5]))
            return 1
        sys.stdout.write(ast_to_json(document))
        return 0

    if args.all:
        out_dir = args.out_dir or os.path.join(root, "docs", "generated",
                                               "spectree")
        count = parse_all(root, out_dir)
        print("spectree-parse: %d AST(s) written to %s" % (count, out_dir))
        return 0

    parser.print_help()
    return 2


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

    def expect_error(name, ext, text):
        try:
            PARSERS[ext](text)
        except ParseError:
            check(name, True)
        except Exception as exc:  # noqa: BLE001 — selftest reports all failures
            check(name, False, "wrong exception: %r" % exc)
        else:
            check(name, False, "expected ParseError")

    specs = {}
    specs_dir = os.path.join(root, "spectree", "specs")
    for name in sorted(os.listdir(specs_dir)):
        with open(os.path.join(specs_dir, name), "r", encoding="utf-8") as handle:
            specs[name] = handle.read()

    # ---- SRS ------------------------------------------------------------
    srs = parse_srs(specs["myapp.srs"])
    check("srs/project", srs["project"] == "MyApp")
    check("srs/version", srs["version"] == "1.0.0")
    check("srs/stakeholders", srs["stakeholders"] == ["platform_team", "product_owner"])
    must = srs["moscow"][0]
    check("srs/moscow-category", must["category"] == "Must Have")
    check("srs/moscow-count", len(must["requirements"]) == 4, repr(len(must["requirements"])))
    m1 = must["requirements"][0]
    check("srs/m1-id", m1["id"] == "M-001")
    check("srs/m1-satisfied", m1["satisfiedBy"] ==
          ["dotnet/src/MyApp.Application/TodoService.cs",
           "dotnet/src/MyApp.Domain/TodoItem.cs"])
    check("srs/wont-have", srs["moscow"][3]["category"] == "Won't Have")
    check("srs/trace", len(srs["traceability"]) == 3)
    expect_error("srs/bad-header", ".srs", "# PRD: MyApp\n")
    expect_error("srs/bad-id", ".srs", "# SRS: MyApp\n\n### Must Have\n- X-1: text\n")
    expect_error("srs/unknown-section", ".srs", "# SRS: MyApp\n\n### Nice to Have\n")

    # ---- AiSpec ----------------------------------------------------------
    ai = parse_ai(specs["todoapi.ai"])
    check("ai/component", ai["component"] == "TodoApi")
    check("ai/deps", ai["dependencies"] == ["TodoService"])
    check("ai/ns", ai["namespace"] == "MyApp.Api.Controllers")
    kinds = [r["kind"] for r in ai["requirements"]]
    check("ai/req-kinds", kinds == ["declared", "must", "should"], repr(kinds))
    check("ai/implicit-id", ai["requirements"][1]["id"] is None)
    put = [e for e in ai["endpoints"] if e["method"] == "PUT"][0]
    check("ai/put-route", put["route"] == "/api/todos/{id}")
    check("ai/entity", ai["dataModel"][0]["entity"] == "TodoDto")
    check("ai/fields", [f["name"] for f in ai["dataModel"][0]["fields"]] ==
          ["Id", "Title", "IsCompleted"])
    check("ai/compliance", ai["compliance"] ==
          {"adrReferences": ["ADR-0015"], "requirementLinks": ["M-002"]})
    expect_error("ai/bad-route", ".ai",
                 "# Component: X\n\n### API Endpoints\n- GET nope: text\n")
    expect_error("ai/bad-compliance", ".ai",
                 "# Component: X\n\n### Compliance\n- satisfies not-an-id\n")
    expect_error("ai/bad-namespace", ".ai",
                 "# Component: X\n## Namespace: 123\n")

    # ---- TestSpec ---------------------------------------------------------
    test = parse_test(specs["todoservice.test"])
    check("test/component", test["component"] == "TodoService")
    check("test/target", test["target"] == "MyApp.Application.TodoService.cs")
    check("test/coverage", test["coverage"] ==
          {"scenarioCoverage": 100, "requirementCoverage": 100, "mustLevel": True})
    check("test/scenario-kinds", [s["kind"] for s in test["scenarios"]] ==
          ["gwt", "should"])
    gwt = test["scenarios"][0]
    check("test/gwt", gwt["given"] == "an empty repository" and
          gwt["when"] == "Create is called with a valid request" and
          gwt["then"] == "the item is stored and returned")
    perf = test["performance"][0]
    check("test/perf-threshold", perf["threshold"] ==
          {"comparator": "under", "value": 50, "unit": "ms"})
    check("test/covers", test["requirementCoverage"] == ["M-001", "REQ-2"])
    # threshold variants
    t2 = parse_test("# Test: X\n\n### Performance Tests\n"
                    "- Should serve reads at least 100 rps\n"
                    "- Should fail with at most 1 % errors\n"
                    "- Should respond within 2 s\n")["performance"]
    check("test/threshold-variants",
          [p["threshold"]["comparator"] for p in t2] ==
          ["at-least", "at-most", "within"], repr(t2))
    expect_error("test/bad-coverage", ".test",
                 "# Test: X\n## Coverage: fast\n")
    expect_error("test/bad-scenario", ".test",
                 "# Test: X\n\n### Test Scenarios\n- Given only\n")

    # ---- ApiSpec ----------------------------------------------------------
    api = parse_api(specs["todoapi.api"])
    check("api/interface", api["interface"] == "TodoApi")
    check("api/auth", api["authentication"] == "none")
    check("api/base-route", api["baseRoute"] == "/api")
    check("api/status", api["status"] == "active" and api["deprecatedSince"] is None)
    post = [e for e in api["endpoints"] if e["method"] == "POST"][0]
    check("api/post-response", post["responses"] ==
          [{"statusCode": 201, "schema": "TodoDto"}])
    delete = [e for e in api["endpoints"] if e["method"] == "DELETE"][0]
    check("api/delete-response", delete["responses"] ==
          [{"statusCode": 204, "schema": "Empty"}])
    schema_dto = api["schemas"][0]
    check("api/schema-name", schema_dto["name"] == "TodoDto")
    check("api/schema-fields", len(schema_dto["fields"]) == 3)
    check("api/constraint-required",
          schema_dto["fields"][0]["constraints"] == [{"kind": "required"}])
    req_schema = api["schemas"][1]
    max_constraint = req_schema["fields"][0]["constraints"]
    check("api/constraint-max", max_constraint ==
          [{"kind": "required"}, {"kind": "max", "value": 200}],
          repr(max_constraint))
    check("api/errors", api["errorContracts"][0] ==
          {"statusCode": 400, "description": "invalid request payload",
           "code": "TODO_VALIDATION_ERROR"})
    expect_error("api/bad-status", ".api",
                 "# Interface: X\n\n### ErrorContracts\n- 999: x code=Y\n")
    expect_error("api/bad-scheme", ".api",
                 "# Interface: X\n## Authentication: basic\n")
    # pattern constraint with spaces inside quotes
    api2 = parse_api('# Interface: X\n\n### Schemas\n'
                     '- S: name: string pattern="^[A-Z][a-z]+ ?$"\n')
    check("api/pattern-spaces",
          api2["schemas"][0]["fields"][0]["constraints"] ==
          [{"kind": "pattern", "value": "^[A-Z][a-z]+ ?$"}])

    # ---- ModelSpec ----------------------------------------------------------
    model = parse_model(specs["todo.model"])
    check("model/name", model["model"] == "Todo")
    todo_item = model["entities"][0]
    check("model/entity", todo_item["kind"] == "entity" and
          todo_item["name"] == "TodoItem")
    check("model/modifiers", todo_item["fields"][0]["modifiers"] ==
          ["key", "required", "immutable"])
    completed = todo_item["fields"][2]
    check("model/default-bool", completed["default"] is False and
          completed["modifiers"] == [])
    check("model/value-object", model["entities"][1]["kind"] == "value-object")
    check("model/enum", model["entities"][2] ==
          {"kind": "enum", "name": "TodoStatus", "extends": None, "fields": []})
    check("model/relationship", model["relationships"][0] ==
          {"from": "TodoItem", "cardinality": "1-1", "to": "TodoDto",
           "description": "projection of the persisted entity"})
    check("model/invariants", model["invariants"][0]["id"] == "INV-1")
    m2 = parse_model("# Model: X\n\n### Entities\n- entity Base\n"
                     "- entity Child extends Base\n")["entities"]
    check("model/extends", m2[1]["extends"] == "Base")
    check("model/array-type", parse_model(
        "# Model: X\n\n### Entities\n- entity E\n  - tags: Array<string>\n"
    )["entities"][0]["fields"][0]["type"] == "Array<string>")
    expect_error("model/bad-cardinality", ".model",
                 "# Model: X\n\n### Relationships\n- A 2-2 B\n")
    expect_error("model/bad-default", ".model",
                 "# Model: X\n\n### Entities\n- entity E\n  - f: bool default=maybe\n")

    # ---- NsSpec ---------------------------------------------------------------
    ns = parse_ns(specs["myapp.ns"])
    check("ns/system", ns["system"] == "MyApp")
    check("ns/applies", ns["appliesTo"] == ["solution"])
    p1 = ns["performance"][0]
    check("ns/bound-simple", p1["bound"] ==
          {"comparator": "<=", "value": 200, "unit": "ms"})
    check("ns/note", p1["note"] == "p95 read latency for GET /api/todos")
    check("ns/bound-ge", ns["scalability"][0]["bound"] ==
          {"comparator": ">=", "value": 100, "unit": "rps"})
    check("ns/bound-float", ns["scalability"][1]["bound"] ==
          {"comparator": ">=", "value": 99.9, "unit": "%"})
    check("ns/sec-ids",
          [s["id"] for s in ns["security"]] == ["SEC-1", "SEC-2"])
    check("ns/classification",
          ns["security"][0]["control"] ==
          {"kind": "classification", "value": "internal"})
    check("ns/authz",
          ns["security"][1]["control"] == {"kind": "authz", "value": "TodoOwner"})
    check("ns/compliance",
          [c["framework"] for c in ns["compliance"]] == ["NIS2", "GDPR"],
          repr(ns["compliance"]))
    ns2 = parse_ns("# NFR: X\n\n### Performance\n"
                   "- PERF-9 (memory): between 1 and 2 GB\n"
                   "- PERF-1 (latency): <= 200 ms adr: ADR-0015\n")
    check("ns/between", ns2["performance"][0]["bound"] ==
          {"comparator": "between", "min": 1, "max": 2, "unit": "GB"})
    check("ns/adr-link",
          ns2["performance"][1]["adr"] == "ADR-0015" and
          ns2["performance"][1]["note"] is None)
    expect_error("ns/bad-unit", ".ns",
                 "# NFR: X\n\n### Performance\n- PERF-1 (latency): <= 200 furlongs\n")
    expect_error("ns/bad-kind", ".ns",
                 "# NFR: X\n\n### Performance\n- PERF-1 (speed): <= 200 ms\n")
    expect_error("ns/bad-classification", ".ns",
                 "# NFR: X\n\n### Security\n- SEC-1: classification: top-secret\n")
    expect_error("ns/unknown-section", ".ns", "# NFR: X\n\n### Reliability\n")
    expect_error("ns/entry-outside-section", ".ns",
                 "# NFR: X\n- PERF-1 (latency): <= 200 ms\n")

    # ---- AdrSpec ---------------------------------------------------------
    adr = parse_adr(specs["spectree-ingestion.adr"])
    check("adr/id", adr["id"] == "ADR-0018")
    check("adr/front-title", adr["title"] == "SpecTree specification-first ingestion")
    check("adr/status", adr["status"] == "accepted")
    check("adr/status-section", adr["statusSection"] == "accepted")
    check("adr/date", adr["date"] == "2026-11-16")
    check("adr/author", adr["author"] == "larsbuch")
    check("adr/supersedes-empty", adr["supersedes"] == [])
    check("adr/related", adr["relatedRequirements"] == ["M-003", "S-001"])
    check("adr/header-title", adr["headerTitle"] == adr["title"])
    check("adr/context",
          len(adr["context"]) == 6 and
          all(isinstance(line, str) and line for line in adr["context"]))
    check("adr/decision", len(adr["decision"]) == 7)
    check("adr/consequence-kinds",
          [c["kind"] for c in adr["consequences"]] ==
          ["positive", "positive", "negative", "neutral"])
    check("adr/consequence-text",
          adr["consequences"][0]["text"] ==
          "requirement, component and NFR data become queryable pipeline inputs")
    check("adr/alternatives",
          adr["alternatives"] ==
          ["ANTLR-generated parsers from the grammar suite",
           "A .NET CLI tool distributed as a NuGet package"])
    check("adr/compliance",
          adr["compliance"] == ["spectree_parse", "generate_docs"])

    adr_base = ("---\nid: ADR-0001\ntitle: T\nstatus: accepted\n"
                "date: 2026-01-01\nauthor: larsbuch\n%s---\n\n"
                "# ADR-%s T\n\n## Status\naccepted\n")
    supersedes_adr = parse_adr(
        adr_base % ("supersedes: [ADR-0009, ADR-0010]\n", "0001"))
    check("adr/supersedes-list",
          supersedes_adr["supersedes"] == ["ADR-0009", "ADR-0010"])
    expect_error("adr/missing-front-matter", ".adr", "not an adr\n")
    expect_error("adr/status-mismatch", ".adr",
                 "---\nid: ADR-0001\ntitle: T\nstatus: accepted\n"
                 "date: 2026-01-01\nauthor: larsbuch\n---\n\n"
                 "# ADR-0001 T\n\n## Status\nproposed\n")
    expect_error("adr/id-mismatch", ".adr",
                 "---\nid: ADR-0001\ntitle: T\nstatus: accepted\n"
                 "date: 2026-01-01\nauthor: larsbuch\n---\n\n"
                 "# ADR-0002 T\n")

    # ---- SolutionManifest ------------------------------------------------
    man = parse_manifest(specs["myapp.manifest"])
    check("man/solution", man["solution"] == "MyApp")
    check("man/projects",
          [p["name"] for p in man["projects"]] ==
          ["MyApp.Domain", "MyApp.Application", "MyApp.Api"])
    check("man/project-tfm",
          man["projects"][0] ==
          {"name": "MyApp.Domain",
           "path": "dotnet/src/MyApp.Domain/MyApp.Domain.csproj",
           "tfm": "net10.0"})
    check("man/specs-count", len(man["specs"]) == 8, repr(len(man["specs"])))
    check("man/spec-entry",
          man["specs"][1] == {"path": "spectree/specs/todoapi.ai",
                              "project": "MyApp.Api"})
    check("man/generations", len(man["generations"]) == 7)
    check("man/gen-spec-types",
          [g["specType"] for g in man["generations"]] ==
          ["srs", "ai", "api", "model", "test", "ns", "adr"])
    check("man/exclusions",
          man["exclusions"] ==
          [{"path": "dotnet/src/MyApp.Api/Program.cs",
            "reason": "composition root with hand-written host bootstrap"}])
    expect_error("man/bad-header", ".manifest", "Solution MyApp\n")
    expect_error("man/bad-generation", ".manifest",
                 "Solution: X\nGenerate: gen for cobra -> out\n")
    expect_error("man/bad-project", ".manifest",
                 "Solution: X\nProject: 1abc -> path\n")

    # ---- AST envelope, schema and determinism -----------------------------
    api_path = os.path.join(specs_dir, "todoapi.api")
    doc = parse_file(api_path, root)
    check("env/head",
          doc["schema"] == "spectree-ast" and doc["schemaVersion"] == 1 and
          doc["astType"] == "api")
    check("env/source",
          doc["source"] ==
          {"path": "spectree/specs/todoapi.api", "grammar": "ApiSpec",
           "grammarCommit": GRAMMAR_COMMIT})
    unknown_ext_ok = False
    try:
        build_ast("x.txt", "x.txt", "irrelevant")
    except ParseError:
        unknown_ext_ok = True
    except Exception:  # noqa: BLE001 — selftest reports all failures
        pass
    check("env/unknown-ext", unknown_ext_ok)

    payload = ast_to_json(doc)
    check("json/deterministic",
          payload == ast_to_json(parse_file(api_path, root)))
    check("json/roundtrip", json.loads(payload) == doc)
    check("json/newline", payload.endswith("\n") and "\r" not in payload)

    schema = load_schema()
    check("schema/valid", schema_errors(doc, schema, schema) == [])
    bad_version = {k: v for k, v in doc.items() if k != "schemaVersion"}
    bad_version["schemaVersion"] = 99
    check("schema/rejects-mutation",
          schema_errors(bad_version, schema, schema) != [])
    bad_missing = {k: v for k, v in doc.items() if k != "astType"}
    check("schema/rejects-missing",
          schema_errors(bad_missing, schema, schema) != [])

    out1 = tempfile.mkdtemp(prefix="spectree-selftest-1-")
    out2 = tempfile.mkdtemp(prefix="spectree-selftest-2-")
    try:
        count1 = parse_all(root, out1)
        count2 = parse_all(root, out2)
        check("all/count", count1 == 9 and count2 == 9, repr((count1, count2)))
        names1 = sorted(os.listdir(out1))
        check("all/filenames",
              names1 == [name + ".ast.json" for name in sorted(specs)],
              repr(names1))
        check("all/deterministic",
              all(open(os.path.join(out1, name), "rb").read() ==
                  open(os.path.join(out2, name), "rb").read()
                  for name in names1))
        with open(os.path.join(out1, "myapp.manifest.ast.json"),
                  "r", encoding="utf-8") as handle:
            written = json.load(handle)
        check("all/ast-equality",
              written == parse_file(os.path.join(specs_dir, "myapp.manifest"),
                                    root))
    finally:
        for out_dir in (out1, out2):
            for name in os.listdir(out_dir):
                os.remove(os.path.join(out_dir, name))
            os.rmdir(out_dir)

    print("spectree-parse selftest: %d checks passed, %d failed"
          % (passed, len(failures)))
    for failure in failures:
        print("  FAIL %s" % failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
