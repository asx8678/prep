"""Print old against new from one evals/compare.sh results folder.

A run counts only if it ended without an error and passed every validity
grader (the skills fired; the brief was saved where the prompt asked). Other
runs are reported as dropped, not as failures, because they say nothing
about the text under test.
Usage: python3 -I evals/table.py <results folder>
"""
import json
import sys
from pathlib import Path

VALIDITY = ("skill-fired", "brief-saved", "prep-fired", "impl-fired")
out = Path(sys.argv[1])
arms = {arm: json.loads((out / arm / "aggregate-result.json").read_text()) for arm in ("old", "new")}
counts = {}
dropped = {}
for arm, result in arms.items():
    for case in result["cases"]:
        for run in case["arms"]["with"]:
            graders = {g["name"]: g["passed"] for g in run["graders"]}
            failed = [name for name in VALIDITY if graders.pop(name, True) is False]
            if run["error"] is not None or failed:
                dropped.setdefault(case["name"], {"old": [], "new": []})[arm].append(run["error"] or "failed " + ", ".join(failed))
                continue
            for name, passed in graders.items():
                cell = counts.setdefault((case["name"], name), {"old": [0, 0], "new": [0, 0]})[arm]
                cell[0] += passed
                cell[1] += 1

print(f"{'case':24} {'check':28} {'old':>5} {'new':>5}")
for (case, name), cells in sorted(counts.items()):
    old, new = (f"{c[0]}/{c[1]}" for c in (cells["old"], cells["new"]))
    print(f"{case:24} {name:28} {old:>5} {new:>5}")
for case, arms_dropped in sorted(dropped.items()):
    for arm, reasons in arms_dropped.items():
        for reason in reasons:
            print(f"dropped: {case}, {arm}: {reason}")
for arm, result in arms.items():
    print(f"{arm}: ${result['costUsd']:.2f} list price, {result['durationSeconds']}s, partial: {result['partial']}")
