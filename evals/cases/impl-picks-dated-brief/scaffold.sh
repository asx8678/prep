#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests .briefs
cat > calc.py <<'EOF'
def add(a, b):
    return a + b
EOF
cat > tests/test_calc.py <<'EOF'
import unittest

from calc import add


class AddTest(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(2, 3), 5)


if __name__ == "__main__":
    unittest.main()
EOF
touch tests/__init__.py
printf '# Calc\n\nTests: `python3 -m unittest`.\n' > README.md
git init -q
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -q -m "Calc"
commit="$(git rev-parse --short HEAD)"

# The brief impl should pick: the only file in .briefs/ named like a brief.
# It is stamped now, because impl asks before it starts on a brief that is
# more than a day old.
stamp="$(date +%Y-%m-%d-%H%M%S)"
cat > ".briefs/$stamp-add-double.md" <<EOF
# Add double() to calc

Type: feature | Date: $stamp | Commit: $commit | Status: ready

## Goal
calc.py gains double(x), which returns x times two, for the pricing page.
- WHEN double(4) is called THE SYSTEM SHALL return 8

## Current state
- calc.py holds add(a, b) only.
- tests/test_calc.py tests add with unittest.

## Example to follow
add() in calc.py and its test in tests/test_calc.py.

## Approach
Add a plain function next to add(), and a test next to the add test.

## Changes
- calc.py: add double(x), returning x * 2.
- tests/test_calc.py: add a test that double(4) == 8.

## Decisions
- No type checks on x (assumed: add() has none either).

## Out of scope
Everything else in calc.py; no new files.

## Risks and blockers
None.

## Proof
- \`python3 -m unittest tests.test_calc\`: the new test fails before the change (baseline: 1 test, OK) and passes after.
- \`python3 -m unittest\`: all tests pass (baseline: Ran 1 test, OK).

## Sources
None needed.

## Open questions
None.

## For the implementing session
Follow this brief. If something in it is wrong or impossible, stop and
say so instead of improvising. Check secrets by name only; never print a
value. Read a live system only where Decisions say the person allowed it.
Never run \`git stash\`, \`checkout\`, \`restore\`, \`reset\` or \`clean\`. Do not
commit, push, deploy, apply or migrate, or change a live system or
Terraform state in any other way, unless the person asks for it in this
conversation after seeing what will change. When finished, tell the person
in one line what this brief got wrong or left out.
EOF

# A note that sorts after the brief and has a Status that is not "done".
cat > .briefs/todo.md <<'EOF'
# Todo

Status: open

- Rename calc.py to arith.py
- Add a triple(x) function
EOF

# What prep puts into .briefs/: git ignores the folder, so a search tool
# finds nothing in it and impl has to list and read the files.
printf '*\n' > .briefs/.gitignore
