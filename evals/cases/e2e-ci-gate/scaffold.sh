#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests docs tools .github/workflows
# main refuses what is not in OPTIONS, so a new option has to be added there,
# and tools/check_docs.py then asks for it in the docs.
cat > cli.py <<'EOF'
"""Prints a greeting. Run: python3 cli.py [--name NAME] [--shout]"""
import sys

OPTIONS = {
    "--name": "who to greet (default: world)",
    "--shout": "print the greeting in capital letters",
}


def greeting(name="world", shout=False):
    text = f"hello, {name}"
    return text.upper() if shout else text


def main(argv):
    name, shout = "world", False
    args = list(argv)
    while args:
        option = args.pop(0)
        if option not in OPTIONS:
            raise SystemExit(f"unknown option: {option}")
        if option == "--name":
            name = args.pop(0)
        elif option == "--shout":
            shout = True
    print(greeting(name, shout))


if __name__ == "__main__":
    main(sys.argv[1:])
EOF
# An option with a value has it inside the backticks, as the request writes
# `--times N`; check_docs.py accepts a row written either way.
cat > docs/options.md <<'EOF'
# Options

| Option | What it does |
| :- | :- |
| `--name NAME` | Greets NAME instead of world |
| `--shout` | Prints the greeting in capital letters |
EOF
cat > tools/check_docs.py <<'EOF'
"""Fails when docs/options.md does not list an option of cli.py."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import cli

docs = (ROOT / "docs" / "options.md").read_text()
missing = [name for name in cli.OPTIONS if not re.search("`" + re.escape(name) + "[ `]", docs)]
if missing:
    sys.exit("not in docs/options.md: " + ", ".join(missing))
EOF
# The only place that says the docs check is part of CI.
cat > .github/workflows/ci.yml <<'EOF'
name: ci

on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: python3 -m unittest
      - run: python3 tools/check_docs.py
EOF
cat > tests/test_cli.py <<'EOF'
import contextlib
import io
import unittest

import cli


class GreetingTest(unittest.TestCase):
    def test_greets_the_world(self):
        self.assertEqual(cli.greeting(), "hello, world")

    def test_shouts(self):
        self.assertEqual(cli.greeting("Ada", shout=True), "HELLO, ADA")

    def test_main_prints_the_greeting(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            cli.main(["--name", "Ada"])
        self.assertEqual(out.getvalue(), "hello, Ada\n")


if __name__ == "__main__":
    unittest.main()
EOF
touch tests/__init__.py
printf '# Greeter\n\nRun: `python3 cli.py --name Ada`.\nTests: `python3 -m unittest`.\n' > README.md
git init -q
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -q -m "Greeter"
