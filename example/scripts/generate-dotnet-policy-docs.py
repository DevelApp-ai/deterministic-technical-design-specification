#!/usr/bin/env python3
"""Generate the .NET architecture policy documentation page.

Extracts policy metadata (id + description) from the architecture test
suite of the .NET example application and renders it as a MkDocs page,
mirroring the ``__rego__metadoc__`` → ``opa-policies.md`` flow used for
the OPA policies.

Two literal shapes are recognised in the test source:

1. ``Policy.Define("APP-XXX-000", "...")`` — NetArchTest-based policies.
2. ``("APP-XXX-000", "...")`` metadata tuples — custom (non-NetArchTest)
   policies that cannot use ``Policy.Define``.

For NetArchTest policies the rule name and rule description passed to
``.Add(...)`` are extracted as well.

The output is deterministic: no timestamps, no environment data, and a
stable ordering (policies sorted by id). Standard library only.

Usage (from the ``example/`` directory or anywhere)::

    python3 scripts/generate-dotnet-policy-docs.py
"""

from __future__ import annotations

import re
from pathlib import Path

EXAMPLE_ROOT = Path(__file__).resolve().parent.parent
TEST_SOURCE = EXAMPLE_ROOT / "dotnet" / "tests" / "MyApp.ArchitectureTests" / "ArchitecturePoliciesTests.cs"
OUTPUT_PAGE = EXAMPLE_ROOT / "docs" / "application" / "architecture-policies.md"

POLICY_ID_PATTERN = r"APP-[A-Z]+-\d+"

# Severity is derived from the id namespace: security policies are
# CRITICAL, structural/quality policies are HIGH. Documented here so
# the mapping is reviewable and deterministic.
SEVERITY_BY_PREFIX = {
    "APP-SEC": "CRITICAL",
}

DEFAULT_SEVERITY = "HIGH"

POLICY_METADATA_HEADING = "# .NET Architecture Policy Summary"


def id_fragment(policy_id: str) -> str:
    """APP-ARCH-001 -> AppArch001 (the fragment used in test method names)."""
    return "".join(part.capitalize() for part in policy_id.split("-"))


def extract_policies(source: str) -> list[dict[str, str]]:
    """Extract policy metadata from the architecture test source."""
    # Split into [Fact] test methods so each policy's rules stay scoped.
    methods = re.split(r"\n    \[Fact\]", "\n" + source)
    test_names = [
        match.group(1)
        for match in re.finditer(r"public void (\w+)\(\)", source)
    ]
    policies: list[dict[str, str]] = []
    seen: set[str] = set()

    # NetArchTest-based policies: Policy.Define(...) inside test methods.
    for method in methods[1:]:
        define = re.search(
            r'Policy\s*\.\s*Define\(\s*"(' + POLICY_ID_PATTERN + r')"\s*,\s*"([^"]*)"',
            method,
        )
        if not define:
            continue

        policy_id, description = define.group(1), define.group(2)
        if policy_id in seen:
            raise SystemExit(f"error: duplicate policy id {policy_id}")

        test_name = re.search(r"public void (\w+)\(\)", method)
        rule = re.search(
            r'\.Add\(\s*[\s\S]*?,\s*"([a-z0-9-]+)",\s*"([^"]*)"\s*\)',
            method,
        )

        policies.append(
            {
                "id": policy_id,
                "description": description,
                "test": test_name.group(1) if test_name else "",
                "rule_name": rule.group(1) if rule else "",
                "rule_description": rule.group(2) if rule else "",
            }
        )
        seen.add(policy_id)

    # Custom (non-NetArchTest) policies: metadata tuple literals declared
    # anywhere in the file — they cannot use Policy.Define.
    for match in re.finditer(
        r'\(\s*"(' + POLICY_ID_PATTERN + r')"\s*,\s*"([^"]*)"', source
    ):
        policy_id, description = match.group(1), match.group(2)
        if policy_id in seen:
            continue

        fragment = id_fragment(policy_id)
        test_name = next((name for name in test_names if fragment in name), "")

        policies.append(
            {
                "id": policy_id,
                "description": description,
                "test": test_name,
                "rule_name": "",
                "rule_description": "",
            }
        )
        seen.add(policy_id)

    if not policies:
        raise SystemExit("error: no policies found in " + str(TEST_SOURCE))
    if any(not p["test"] for p in policies):
        missing = ", ".join(p["id"] for p in policies if not p["test"])
        raise SystemExit(f"error: no test method found for policy ids: {missing}")

    return sorted(policies, key=lambda p: p["id"])


def severity_for(policy_id: str) -> str:
    for prefix, severity in SEVERITY_BY_PREFIX.items():
        if policy_id.startswith(prefix):
            return severity
    return DEFAULT_SEVERITY


def render(policies: list[dict[str, str]]) -> str:
    """Render the MkDocs page for the extracted policies."""
    lines: list[str] = [
        POLICY_METADATA_HEADING,
        "",
        '!!! note "Auto-generated"',
        "    This page is generated from the policy metadata embedded in",
        "    `example/dotnet/tests/MyApp.ArchitectureTests/ArchitecturePoliciesTests.cs`",
        "    (the `Policy.Define` literals and the custom-policy metadata tuple)",
        "    by `scripts/generate-dotnet-policy-docs.py`. Re-run that script after",
        "    changing the architecture policy suite.",
        "",
        "## Policy Inventory",
        "",
    ]

    for policy in policies:
        lines.append(f"### {policy['id']} — {title_of(policy)}")
        lines.append("")
        lines.append("| Field | Value |")
        lines.append("|-------|-------|")
        lines.append(f"| **ID** | `{policy['id']}` |")
        lines.append(f"| **Severity** | {severity_for(policy['id'])} |")
        lines.append("| **File** | `example/dotnet/tests/MyApp.ArchitectureTests/ArchitecturePoliciesTests.cs` |")
        lines.append(f"| **Test** | `{policy['test']}` |")
        if policy["rule_name"]:
            lines.append(f"| **Rule** | `{policy['rule_name']}` |")
        else:
            lines.append("| **Rule** | custom reflection-based check |")
        lines.append("| **Related Requirements** | [MoSCoW Prioritisation](../requirements/moscow.md) |")
        lines.append("")
        lines.append("**Description:**  ")
        lines.append(wrap(policy["description"]))
        if policy["rule_description"]:
            lines.append("")
            lines.append("**Rule:**  ")
            lines.append(wrap(policy["rule_description"]))
        lines.append("")
        lines.append("---")
        lines.append("")

    lines.extend(
        [
            "## Traceability",
            "",
            "See the [Traceability Matrix](../traceability/index.md) for the full chain",
            "from MoSCoW requirements to ADRs, policies, and code.",
            "",
            "The choice of NetArchTest.Rules as the architecture-policy engine",
            "(over alternatives such as ArchUnitNET) will be recorded in an",
            "upcoming ADR as part of the .NET ADR series.",
            "",
            "## Running the Policies Locally",
            "",
            "```bash",
            "# Run the full solution test suite (unit + architecture policies)",
            "cd example/dotnet && dotnet test MyApp.slnx",
            "```",
            "",
        ]
    )

    return "\n".join(lines)


def title_of(policy: dict[str, str]) -> str:
    """Derive a human-readable title from the test method name.

    ``Policy_AppArch001_ControllersMustNotDependOnRepositories`` becomes
    ``Controllers Must Not Depend On Repositories``.
    """
    name = policy["test"]
    if name.startswith("Policy_"):
        name = name[len("Policy_"):]
    words = [
        segment for segment in name.split("_")
        if segment and segment != id_fragment(policy["id"])
    ]
    title_words: list[str] = []
    for segment in words:
        title_words.extend(
            part for part in re.sub(r"(?<!^)(?=[A-Z])", " ", segment).split() if part
        )
    return " ".join(title_words) or policy["id"]


def wrap(text: str, width: int = 79) -> str:
    """Deterministically wrap description text for the Markdown page."""
    words = text.split()
    lines: list[str] = []
    current: list[str] = []
    length = 0
    for word in words:
        if current and length + 1 + len(word) > width:
            lines.append(" ".join(current))
            current = [word]
            length = len(word)
        else:
            current.append(word)
            length += (1 if length else 0) + len(word)
    if current:
        lines.append(" ".join(current))
    return "\n".join(lines)


def main() -> None:
    source = TEST_SOURCE.read_text(encoding="utf-8")
    page = render(extract_policies(source))
    OUTPUT_PAGE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PAGE.write_text(page + "\n", encoding="utf-8")
    print(f"generated {OUTPUT_PAGE.relative_to(EXAMPLE_ROOT)}")


if __name__ == "__main__":
    main()
