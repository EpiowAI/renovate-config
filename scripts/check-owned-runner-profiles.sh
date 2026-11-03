#!/usr/bin/env bash
# Enforce the runner contract for this repository's direct jobs (owner#750,
# standards/dx.md: CI never costs money). Reusable workflows are governed by
# the repository that owns their source. The script checks its own policy
# fixtures before it scans, so a broken rule fails here instead of in review.
#
# - A private repository runs every job on our own runners: GitHub-hosted
#   minutes are billed there.
# - A public repository may also use GitHub's free standard hosted runners
#   (`<os>-latest` and `<os>-<major.minor>`: ubuntu, windows, macos).
# - GitHub's larger and GPU hosted runners are billed even for public
#   repositories, so they always fail, as does every `[self-hosted, ...]`
#   label list except our own macOS list.
#
# REPO_PRIVATE is `github.event.repository.private` from the workflow. Any
# value other than `false` counts as private, so a missing value fails closed.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import os
import re
import sys

root = Path(sys.argv[1])
workflow_dir = root / ".github" / "workflows"

selection = re.compile(r"^\s*runs-on\s*:\s*(?P<value>.*?)(?:\s+#.*)?$")
owned = re.compile(r"^sylphx-linux-(?:(?:standard|large|xlarge)(?:-merge)?|2xlarge)$")
# Only this event selector can choose a reserved merge pool. Both branches
# must retain the same published runner size; arbitrary expressions fail.
merge_selector = re.compile(
    r"^\$\{\{ github\.event_name == 'merge_group' && "
    r"'(sylphx-linux-(?:standard|large|xlarge))-merge' \|\| '\1' \}\}$"
)
owned_macos_array = re.compile(
    r"^\[\s*self-hosted\s*,\s*sylphx\s*,\s*macos\s*,\s*(?:nano|small|standard|large|xlarge|2xlarge)\s*\]$"
)
hosted = re.compile(r"^(?:ubuntu|windows|macos)-", re.I)
standard_hosted = re.compile(r"^(?:ubuntu|windows|macos)-(?:latest|\d+(?:\.\d+)?)$", re.I)
larger_or_gpu = re.compile(r"-xl\b|large|gpu|-\d+-core\b", re.I)
label_list = re.compile(r"^\[")

raw_private = os.environ.get("REPO_PRIVATE")
private = (raw_private or "").strip().lower() != "false"

def reason_for(value, is_private):
    """The violation for one `runs-on` value, or None when it is allowed."""
    if merge_selector.fullmatch(value):
        return None
    if "${{" in value:
        return "dynamic runner selection other than the same-size merge-group selector"
    if owned_macos_array.fullmatch(value):
        return None
    if label_list.match(value):
        return (
            "not an owned label list; the only owned list is "
            "[self-hosted, sylphx, macos, <class>], otherwise use the bare Sylphx runner label"
        )
    if owned.fullmatch(value):
        return None
    if larger_or_gpu.search(value):
        return "larger or GPU GitHub-hosted runner (billed even for public repositories)"
    if standard_hosted.fullmatch(value):
        if is_private:
            return "GitHub-hosted runner in a private repository (billed)"
        return None
    if hosted.match(value):
        return "not a free standard GitHub-hosted runner"
    return "not a published static Sylphx profile"

def scan(name, text, is_private):
    found = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        match = selection.match(line)
        if not match:
            continue
        value = match.group("value").strip().strip("\"'")
        reason = reason_for(value, is_private)
        if reason:
            found.append((name, line_no, reason, value))
    return found

def self_test():
    fixture = "jobs:\n  verify:\n    runs-on: {}\n    steps:\n      - run: true\n"
    cases = (
        ("private + standard hosted", "ubuntu-latest", True, True),
        ("public + standard hosted", "ubuntu-latest", False, False),
        ("private + owned runner", "sylphx-linux-standard", True, False),
        ("public + owned runner", "sylphx-linux-standard", False, False),
        ("public + larger hosted", "ubuntu-24.04-8-core", False, True),
        ("public + GPU hosted", "gpu_1x_a10", False, True),
        ("private + owned macOS list", "[self-hosted, sylphx, macos, standard]", True, False),
        ("public + owned macOS list", "[self-hosted, sylphx, macos, standard]", False, False),
        ("private + retired Linux list", "[self-hosted, sylphx-linux-standard]", True, True),
        ("self-hosted label list", "[self-hosted, sylphx-linux-standard]", False, True),
        ("unowned macOS list", "[self-hosted, sylphx, macos, huge]", False, True),
        ("private + standard merge pool", "sylphx-linux-standard-merge", True, False),
        ("private + large merge pool", "sylphx-linux-large-merge", True, False),
        ("private + xlarge merge pool", "sylphx-linux-xlarge-merge", True, False),
        ("unpublished merge pool", "sylphx-linux-2xlarge-merge", True, True),
        ("private + standard merge selector", "${{ github.event_name == 'merge_group' && 'sylphx-linux-standard-merge' || 'sylphx-linux-standard' }}", True, False),
        ("public + large merge selector", "${{ github.event_name == 'merge_group' && 'sylphx-linux-large-merge' || 'sylphx-linux-large' }}", False, False),
        ("private + xlarge merge selector", "${{ github.event_name == 'merge_group' && 'sylphx-linux-xlarge-merge' || 'sylphx-linux-xlarge' }}", True, False),
        ("mismatched selector sizes", "${{ github.event_name == 'merge_group' && 'sylphx-linux-large-merge' || 'sylphx-linux-standard' }}", True, True),
        ("wrong event", "${{ github.event_name == 'pull_request' && 'sylphx-linux-standard-merge' || 'sylphx-linux-standard' }}", False, True),
        ("hosted fallback", "${{ github.event_name == 'merge_group' && 'sylphx-linux-standard-merge' || 'ubuntu-latest' }}", False, True),
        ("unknown merge size", "${{ github.event_name == 'merge_group' && 'sylphx-linux-huge-merge' || 'sylphx-linux-huge' }}", True, True),
        ("reversed merge selector", "${{ github.event_name == 'merge_group' && 'sylphx-linux-standard' || 'sylphx-linux-standard-merge' }}", False, True),
        ("dynamic selection", "${{ matrix.runner }}", False, True),
        ("unknown label", "custom-runner-group", False, True),
    )
    failures = []
    for name, value, is_private, must_fail in cases:
        failed = bool(scan("fixture.yml", fixture.format(value), is_private))
        if failed != must_fail:
            failures.append(
                f"{name}: runs-on {value!r} {'failed' if failed else 'passed'},"
                f" expected {'failure' if must_fail else 'pass'}"
            )
    if failures:
        raise SystemExit("runner contract self-test failed:\n" + "\n".join(failures))

self_test()

violations = []
checked = 0
for workflow in sorted((*workflow_dir.glob("*.yml"), *workflow_dir.glob("*.yaml"))):
    text = workflow.read_text()
    checked += sum(1 for line in text.splitlines() if selection.match(line))
    violations.extend(scan(str(workflow.relative_to(root)), text, private))

if checked == 0:
    raise SystemExit("no direct workflow runner selections found")
if violations:
    for name, line_no, reason, value in violations:
        print(f"{name}:{line_no}: {reason}: {value}", file=sys.stderr)
    raise SystemExit("runner contract failed")

visibility = "private" if private else "public"
note = "" if raw_private is not None else " (REPO_PRIVATE unset, treated as private)"
print(f"OK: {checked} direct workflow job(s) use Sylphx runners or free standard hosted runners"
      f" ({visibility} repository{note})")
PY
