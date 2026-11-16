#!/usr/bin/env python3
"""scripts/generate-drift-report.py — infrastructure drift report renderer (ADR-0024)

Converts a Terraform plan (``terraform show -json tfplan``, produced by
``terraform plan -detailed-exitcode``) into a deterministic, human-readable
Markdown drift report:

  * ``resource_drift``   — state/config mismatches found during refresh
                           (the drift itself)
  * ``resource_changes`` — the planned remediation, classified by action
                           (replace / delete / update / create / read)

The report is an **incident snapshot**, not a committed artefact: the
pipeline writes it to ``docs/generated/drift-report.md`` inside the job
workspace, publishes it as a workflow artefact and the run summary, and
never commits it (ADR-0024, decision 2 — committing an ephemeral snapshot
would break the committed-artefact drift gates and the deterministic tree).

Determinism bar (ADR-0018): standard library only, no timestamps, no
network, byte-identical output for an identical plan JSON.

Usage:
    generate-drift-report.py --selftest
    generate-drift-report.py --plan tfplan.json --output drift-report.md
"""

from __future__ import annotations

import argparse
import json
import sys

SCHEMA = "drift-report-v1"

# Deterministic group order: destroy-class changes first (highest urgency
# for a drift report), then in-place, then additive, then read-only.
ACTION_ORDER = ["replace", "delete", "update", "create", "read", "no-op"]

GROUP_TITLES = {
    "replace": "Replace",
    "delete": "Delete",
    "update": "Update",
    "create": "Create",
    "read": "Read",
    "no-op": "No-op",
}

SECTION_TITLES = {
    "replace": "Resources to replace",
    "delete": "Resources to delete",
    "update": "Resources to update in place",
    "create": "Resources to create",
    "read": "Resources to read",
}


class ReportError(Exception):
    """Raised when the plan JSON cannot be rendered."""


# ---------------------------------------------------------------------------
# Plan classification
# ---------------------------------------------------------------------------

def classify_actions(actions):
    """Map a Terraform ``change.actions`` list to a single group label."""
    actions = list(actions or [])
    if actions in ([], ["no-op"]):
        return "no-op"
    if actions == ["create"]:
        return "create"
    if actions == ["read"]:
        return "read"
    if actions == ["update"]:
        return "update"
    if actions == ["delete"]:
        return "delete"
    if set(actions) == {"delete", "create"}:
        # ["delete", "create"] = destroy-then-recreate,
        # ["create", "delete"] = create-then-destroy — both are "replace".
        return "replace"
    raise ReportError("unsupported change actions: %r" % (actions,))


def format_value(value):
    """Render a plan value as deterministic, human-readable JSON."""
    if value is None:
        return "null"
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def _is_masked(sensitive, key):
    """True when the whole attribute is marked sensitive (marker is `True`)."""
    return isinstance(sensitive, dict) and sensitive.get(key) is True


def attribute_diffs(change):
    """Deterministic per-resource attribute diff lines for one change.

    Values marked sensitive at the top level render as ``(sensitive
    value)``; attributes Terraform can only compute during apply render as
    ``(known after apply)``.
    """
    before = change.get("before") or {}
    after = change.get("after") or {}
    after_unknown = change.get("after_unknown") or {}
    before_sensitive = change.get("before_sensitive") or {}
    after_sensitive = change.get("after_sensitive") or {}

    lines = []
    for key in sorted(set(before) | set(after)):
        b = before.get(key)
        a = after.get(key)
        unknown = isinstance(after_unknown, dict) and bool(after_unknown.get(key))
        if b == a and not unknown:
            continue
        if _is_masked(before_sensitive, key):
            b_str = "(sensitive value)"
        else:
            b_str = format_value(b)
        if unknown:
            a_str = "(known after apply)"
        elif _is_masked(after_sensitive, key):
            a_str = "(sensitive value)"
        else:
            a_str = format_value(a)
        lines.append("- `%s`: %s → %s" % (key, b_str, a_str))
    return lines


def _resource_block(rc):
    """Render one resource's Markdown block (heading + provider + diff)."""
    address = rc.get("address") or "<unnamed resource>"
    provider = rc.get("provider_name") or "unknown provider"
    actions = list(rc.get("change", {}).get("actions") or [])
    action_label = classify_actions(actions)
    action_path = " → ".join("`%s`" % a for a in actions) or "`no-op`"

    lines = ["### `%s` — %s" % (address, action_label), ""]
    lines.append("- Provider: `%s`" % provider)
    lines.append("- Actions: %s" % action_path)
    diff = attribute_diffs(rc.get("change") or {})
    if diff:
        lines.append("")
        lines.append("Attribute changes:")
        lines.append("")
        lines.extend(diff)
    lines.append("")
    return "\n".join(lines)


def render_report(plan):
    """Render the full drift report Markdown for a parsed plan JSON object."""
    if not isinstance(plan, dict):
        raise ReportError("plan JSON is not an object")
    if "resource_changes" not in plan:
        raise ReportError("plan JSON has no resource_changes array")

    changes = plan["resource_changes"]
    if not isinstance(changes, list):
        raise ReportError("plan resource_changes is not an array")

    drift = plan.get("resource_drift") or []
    if not isinstance(drift, list):
        raise ReportError("plan resource_drift is not an array")

    groups = {action: [] for action in ACTION_ORDER}
    for rc in changes:
        try:
            action = classify_actions(rc.get("change", {}).get("actions"))
        except ReportError:
            raise ReportError("unclassifiable change at %r"
                              % (rc.get("address"),))
        groups[action].append(rc)
    for action in ACTION_ORDER:
        groups[action].sort(key=lambda rc: rc.get("address") or "")

    total = len(changes)
    drifted = total - len(groups["no-op"])
    state_drift = len(drift)

    lines = []
    lines.append("# Infrastructure Drift Report")
    lines.append("")
    lines.append("The drift check found differences between the deployed "
                 "state and the")
    lines.append("configuration in version control "
                 "(`terraform plan -detailed-exitcode`, ADR-0024).")
    lines.append("")
    lines.append("- Terraform version: `%s`"
                 % plan.get("terraform_version", "unknown"))
    lines.append("- Plan format version: `%s`"
                 % plan.get("format_version", "unknown"))
    lines.append("- Resources in plan: %d" % total)
    lines.append("- Planned changes (drift to reconcile): %d" % drifted)
    lines.append("- State mismatches found during refresh: %d" % state_drift)
    lines.append("")

    lines.append("## Summary")
    lines.append("")
    lines.append("| Action | Resources |")
    lines.append("|--------|-----------|")
    for action in ACTION_ORDER:
        lines.append("| %s | %d |" % (GROUP_TITLES[action], len(groups[action])))
    lines.append("")

    if state_drift:
        lines.append("## State mismatches (refresh)")
        lines.append("")
        lines.append("Resources whose recorded state no longer matches the "
                     "configuration,")
        lines.append("detected while refreshing state against the real "
                     "infrastructure:")
        lines.append("")
        for rc in sorted(drift, key=lambda rc: rc.get("address") or ""):
            lines.append(_resource_block(rc))

    for action in ACTION_ORDER:
        if action == "no-op" or not groups[action]:
            continue
        lines.append("## %s" % SECTION_TITLES[action])
        lines.append("")
        for rc in groups[action]:
            lines.append(_resource_block(rc))

    lines.append("---")
    lines.append("")
    lines.append("Report schema: `%s`.  Reconcile the drift through the "
                 "Infrastructure as Code" % SCHEMA)
    lines.append("tree (never by hand), then re-run the drift check via a "
                 "manual")
    lines.append("`workflow_dispatch` of the documentation pipeline to "
                 "verify the state")
    lines.append("is in sync again.")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def run(plan_path, output_path):
    """Load the plan JSON, render the report, write it to output_path."""
    with open(plan_path, "r", encoding="utf-8") as handle:
        try:
            plan = json.load(handle)
        except json.JSONDecodeError as exc:
            raise ReportError("plan file %s is not valid JSON: %s"
                              % (plan_path, exc)) from exc
    report = render_report(plan)
    with open(output_path, "w", encoding="utf-8") as handle:
        handle.write(report)
    print("drift report: %d planned change(s) rendered -> %s"
          % (len(plan.get("resource_changes") or []), output_path))
    return 0


# ---------------------------------------------------------------------------
# Embedded test suite
# ---------------------------------------------------------------------------

def _fixture_plan():
    """A representative `terraform show -json` plan: refresh drift plus
    replace/delete/update/no-op changes, sensitive values, and one
    attribute that is only known after apply."""
    return {
        "format_version": "1.2",
        "terraform_version": "1.9.8",
        "resource_drift": [{
            "address": "local_file.config",
            "mode": "managed",
            "type": "local_file",
            "name": "config",
            "provider_name": "registry.terraform.io/hashicorp/local",
            "change": {
                "actions": ["update"],
                "before": {"content": "old", "filename": "app.cfg"},
                "after": {"content": "new", "filename": "app.cfg"},
            },
        }],
        "resource_changes": [
            {
                "address": "aws_instance.example",
                "mode": "managed",
                "type": "aws_instance",
                "name": "example",
                "provider_name": "registry.terraform.io/hashicorp/aws",
                "change": {
                    "actions": ["delete", "create"],
                    "before": {"instance_type": "t3.micro",
                               "tags": {"Name": "example"}},
                    "after": {"instance_type": "t3.small",
                              "tags": {"Name": "example"}},
                },
            },
            {
                "address": "aws_s3_bucket.logs",
                "mode": "managed",
                "type": "aws_s3_bucket",
                "name": "logs",
                "provider_name": "registry.terraform.io/hashicorp/aws",
                "change": {
                    "actions": ["delete"],
                    "before": {"bucket": "example-logs"},
                    "after": {},
                },
            },
            {
                "address": "aws_db_instance.primary",
                "mode": "managed",
                "type": "aws_db_instance",
                "name": "primary",
                "provider_name": "registry.terraform.io/hashicorp/aws",
                "change": {
                    "actions": ["update"],
                    "before": {"password": "old-secret",
                               "allocated_storage": 20},
                    "after": {"allocated_storage": 50},
                    "after_unknown": {"password": True},
                    "before_sensitive": {"password": True},
                    "after_sensitive": {"password": True},
                },
            },
            {
                "address": "aws_iam_role.reader",
                "mode": "managed",
                "type": "aws_iam_role",
                "name": "reader",
                "provider_name": "registry.terraform.io/hashicorp/aws",
                "change": {"actions": ["no-op"],
                          "before": {"name": "reader"},
                          "after": {"name": "reader"}},
            },
        ],
    }


def _selftest():
    checks = []

    def check(name, condition):
        checks.append((name, bool(condition)))

    # — classification —
    check("empty actions classify as no-op",
          classify_actions([]) == "no-op")
    check("['no-op'] classifies as no-op",
          classify_actions(["no-op"]) == "no-op")
    check("['create'] classifies as create",
          classify_actions(["create"]) == "create")
    check("['read'] classifies as read",
          classify_actions(["read"]) == "read")
    check("['update'] classifies as update",
          classify_actions(["update"]) == "update")
    check("['delete'] classifies as delete",
          classify_actions(["delete"]) == "delete")
    check("['delete','create'] classifies as replace",
          classify_actions(["delete", "create"]) == "replace")
    check("['create','delete'] classifies as replace",
          classify_actions(["create", "delete"]) == "replace")
    try:
        classify_actions(["update", "create"])
        check("unsupported actions raise ReportError", False)
    except ReportError:
        check("unsupported actions raise ReportError", True)

    # — value formatting —
    check("None renders as null", format_value(None) == "null")
    check("string renders as JSON string",
          format_value("t3.micro") == '"t3.micro"')
    check("dict renders sorted and deterministic",
          format_value({"b": 2, "a": 1}) == '{"a": 1, "b": 2}')

    # — attribute diffs —
    diff = attribute_diffs(_fixture_plan()["resource_changes"][0]["change"])
    check("unchanged attribute is not reported",
          all("tags" not in line for line in diff))
    check("changed attribute reports before → after",
          "- `instance_type`: \"t3.micro\" → \"t3.small\"" in diff)
    check("diff keys are sorted",
          [line.split("`")[1] for line in diff]
          == sorted(line.split("`")[1] for line in diff))

    secret = attribute_diffs(_fixture_plan()["resource_changes"][2]["change"])
    check("sensitive before-value is masked",
          any("(sensitive value)" in line for line in secret))
    check("unknown after-apply value is annotated",
          any("(known after apply)" in line for line in secret))
    check("plain changed attribute still renders in mixed change",
          "- `allocated_storage`: 20 → 50" in secret)

    delete = attribute_diffs(_fixture_plan()["resource_changes"][1]["change"])
    check("deleted resource renders value → null",
          "- `bucket`: \"example-logs\" → null" in delete)

    # — rendering —
    report = render_report(_fixture_plan())
    check("report has the expected title",
          report.startswith("# Infrastructure Drift Report\n"))
    check("plan header counts 4 resources",
          "- Resources in plan: 4" in report)
    check("planned-changes count excludes no-op",
          "- Planned changes (drift to reconcile): 3" in report)
    check("refresh drift count is reported",
          "- State mismatches found during refresh: 1" in report)
    check("summary table lists all six action kinds",
          all(("| %s |" % GROUP_TITLES[a]) in report
              for a in ACTION_ORDER))
    check("no-op count appears in the summary",
          "| No-op | 1 |" in report)
    check("refresh drift section is rendered",
          "## State mismatches (refresh)" in report)
    check("refresh drift resource is listed",
          "### `local_file.config` — update" in report)
    check("replace section is rendered",
          "## Resources to replace" in report)
    check("delete section is rendered",
          "## Resources to delete" in report)
    check("update section is rendered",
          "## Resources to update in place" in report)
    check("no no-op section is rendered",
          "## No-op" not in report and "## No-op resources" not in report)
    check("replace actions path is rendered",
          "- Actions: `delete` → `create`" in report)
    check("provider is rendered",
          "- Provider: `registry.terraform.io/hashicorp/aws`" in report)
    check("report declares its schema",
          "`%s`" % SCHEMA in report)
    check("report ends with the reconciliation note",
          report.rstrip().endswith("is in sync again."))

    # — determinism —
    check("rendering is byte-deterministic",
          render_report(_fixture_plan()) == report)

    # — error handling —
    try:
        render_report({"terraform_version": "1.9.8"})
        check("missing resource_changes raises ReportError", False)
    except ReportError:
        check("missing resource_changes raises ReportError", True)
    try:
        render_report([1, 2, 3])
        check("non-object plan raises ReportError", False)
    except ReportError:
        check("non-object plan raises ReportError", True)
    try:
        render_report({"resource_changes": [{"address": "x", "change": {
            "actions": ["bananas"]}}]})
        check("unclassifiable change raises ReportError", False)
    except ReportError:
        check("unclassifiable change raises ReportError", True)

    # — empty plan (no drift) —
    clean = render_report({"format_version": "1.2",
                           "terraform_version": "1.9.8",
                           "resource_changes": []})
    check("empty plan reports zero drift",
          "- Planned changes (drift to reconcile): 0" in clean)
    check("empty plan has no resource sections",
          "## Resources to" not in clean)

    # — file mode round-trip —
    import tempfile
    import os
    with tempfile.TemporaryDirectory() as tmp:
        plan_path = os.path.join(tmp, "tfplan.json")
        out_path = os.path.join(tmp, "drift-report.md")
        with open(plan_path, "w", encoding="utf-8") as handle:
            json.dump(_fixture_plan(), handle)
        run(plan_path, out_path)
        with open(out_path, "r", encoding="utf-8") as handle:
            written = handle.read()
        check("--plan/--output mode writes the rendered report",
              written == report)

    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        if not ok:
            print(f"  FAIL {name}")
    print(f"generate-drift-report selftest: "
          f"{len(checks) - len(failed)}/{len(checks)} checks passed")
    return 1 if failed else 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Infrastructure drift report renderer (ADR-0024)")
    parser.add_argument("--selftest", action="store_true",
                        help="run the embedded test suite and exit")
    parser.add_argument("--plan", metavar="PATH", default=None,
                        help="terraform show -json plan file to render")
    parser.add_argument("--output", metavar="PATH", default=None,
                        help="Markdown drift report to write")
    args = parser.parse_args(argv)

    if args.selftest:
        return _selftest()
    if args.plan and args.output:
        try:
            return run(args.plan, args.output)
        except ReportError as exc:
            print("error: %s" % exc, file=sys.stderr)
            return 1
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
