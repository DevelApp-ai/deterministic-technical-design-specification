#!/usr/bin/env python3
"""Assemble the C4 architecture Mermaid diagrams into a MkDocs page.

Reads the ``*.mermaid.md`` files that the C4Sharp generator
(``dotnet/tools/MyApp.Architecture.Diagrams``) writes to
``docs/generated/architecture/`` and embeds them — fenced and verbatim —
into the documentation page ``docs/application/architecture-diagrams.md``.

Deterministic: output depends only on the generated diagram files. No
timestamps, no environment data, sorted file order. Standard library only.

Usage (from the ``example/`` directory or anywhere)::

    python3 scripts/generate-c4-diagram-docs.py
"""

from __future__ import annotations

from pathlib import Path

EXAMPLE_ROOT = Path(__file__).resolve().parent.parent
ARCHITECTURE_DIR = EXAMPLE_ROOT / "docs" / "generated" / "architecture"
OUTPUT_PAGE = EXAMPLE_ROOT / "docs" / "application" / "architecture-diagrams.md"

# Explicit registry: every generated diagram file maps to one page section.
# Unknown files fail loudly so the page can never silently drift from the
# generated model.
DIAGRAMS = [
    (
        "myapp-system-context-c4context.mermaid.md",
        "System Context",
        "The C4 System Context diagram: the API consumer and the MyApp "
        "software system, with no internal detail.",
    ),
    (
        "myapp-containers-c4container.mermaid.md",
        "Containers",
        "The C4 Container diagram: the MyApp API container and its "
        "in-memory store boundary.",
    ),
    (
        "myapp-api-components-c4component.mermaid.md",
        "Components (MyApp API)",
        "The C4 Component diagram of the MyApp API container — controller, "
        "application service, the domain repository contract, and its "
        "infrastructure implementation. The arrows mirror the strict "
        "Api → Application → Domain layering that the NetArchTest policies "
        "(APP-ARCH-001/002, APP-SEC-001) enforce.",
    ),
]


def load_diagrams() -> list[tuple[str, str, str]]:
    """Return (section title, description, mermaid source) for each diagram."""
    diagrams: list[tuple[str, str, str]] = []
    missing = [
        name for name, _, _ in DIAGRAMS
        if not (ARCHITECTURE_DIR / name).exists()
    ]
    if missing:
        raise SystemExit(
            "error: missing generated diagram(s): " + ", ".join(missing)
            + " — run `dotnet run --project dotnet/tools/MyApp.Architecture.Diagrams`"
            + " first (C4Sharp Mermaid export)."
        )
    registered = {name for name, _, _ in DIAGRAMS}
    unexpected = sorted(
        path.name for path in ARCHITECTURE_DIR.glob("*.mermaid.md")
        if path.name not in registered
    )
    if unexpected:
        raise SystemExit(
            "error: unregistered diagram file(s): " + ", ".join(unexpected)
            + " — register them in scripts/generate-c4-diagram-docs.py"
            + " so the page stays in sync with the generated model."
        )
    for name, title, description in DIAGRAMS:
        source = (ARCHITECTURE_DIR / name).read_text(encoding="utf-8")
        diagrams.append((title, description, source))
    return diagrams


def render_page(diagrams: list[tuple[str, str, str]]) -> list[str]:
    lines = [
        "# Architecture Diagrams (C4 Model)",
        "",
        '!!! note "Auto-generated"',
        "    This page embeds the Mermaid sources in",
        "    `docs/generated/architecture/` — rendered by the C4Sharp",
        "    generator project `dotnet/tools/MyApp.Architecture.Diagrams`",
        "    (C4 model as code: the diagrams are declared in C# and rebuilt",
        "    by the same deterministic pipeline as every other artefact).",
        "    Re-render with",
        "    `python3 scripts/generate-c4-diagram-docs.py` after regenerating",
        "    the diagrams.",
        "",
        "| Field | Value |",
        "|-------|-------|",
        "| **Model** | C4 (Context, Container, Component) |",
        "| **Generator** | C4Sharp 8.1.204 (`dotnet/tools/MyApp.Architecture.Diagrams`) |",
        "| **Output format** | Mermaid (`C4Context` / `C4Container` / `C4Component`) |",
        "| **Generated sources** | `docs/generated/architecture/` |",
        "| **Related Requirements** | [MoSCoW Prioritisation](../requirements/moscow.md) |",
        "| **Related policies** | [Architecture Policies](architecture-policies.md) |",
        "",
        "The diagrams are the reviewable source of truth for the application's",
        "structure: they change only in pull requests, together with the code",
        "they describe, and the pipeline re-renders them on every build.",
        "",
    ]
    for title, description, source in diagrams:
        lines.extend([f"## {title}", ""])
        lines.append(description)
        lines.append("")
        # The .mermaid.md sources are complete ```mermaid fenced blocks;
        # embed them verbatim so the page is a faithful view of the artefact.
        lines.append(source.rstrip())
        lines.append("")
    lines.extend([
        "## Traceability",
        "",
        "The C4 model is a traceable pipeline artefact: it is declared as",
        "code, regenerated deterministically, and embedded in this page.",
        "See the",
        "[Traceability Matrix](../traceability/index.md) for the full chain",
        "from MoSCoW requirements to ADRs, policies, and code. The",
        "C4Sharp-over-Mermaid approach will be recorded in the .NET ADR",
        "series (together with the other tooling decisions).",
        "",
    ])
    return lines


def main() -> None:
    diagrams = load_diagrams()
    OUTPUT_PAGE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PAGE.write_text("\n".join(render_page(diagrams)).rstrip() + "\n", encoding="utf-8")
    print(f"generated {OUTPUT_PAGE.relative_to(EXAMPLE_ROOT)}")


if __name__ == "__main__":
    main()
