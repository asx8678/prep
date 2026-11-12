#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests
cat > greet.py <<'EOF'
def greeting(name):
    """The greeting for one person."""
    return "Hello, " + name + "."
EOF
cat > tests/test_greet.py <<'EOF'
import unittest

from greet import greeting


class GreetingTest(unittest.TestCase):
    def test_greets_by_name(self):
        self.assertEqual(greeting("Ada"), "Hello, Ada.")


if __name__ == "__main__":
    unittest.main()
EOF
touch tests/__init__.py
printf '# Greet\n\nTests: `python3 -m unittest`.\n' > README.md
git init -q
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -q -m "Greeting"
