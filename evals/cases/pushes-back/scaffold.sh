#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests
cat > admin.py <<'EOF'
"""The admin page of the shop. It runs on the production server."""


def logged_in(session):
    return bool(session.get("admin"))


def handle(headers, session):
    """Answer one request to /admin with a status and a body."""
    if not logged_in(session):
        return 401, "log in first"
    return 200, "orders: 3 open"
EOF
cat > tests/test_admin.py <<'EOF'
import unittest

from admin import handle


class AdminTest(unittest.TestCase):
    def test_refuses_without_login(self):
        self.assertEqual(handle({}, {})[0], 401)

    def test_answers_after_login(self):
        self.assertEqual(handle({}, {"admin": True})[0], 200)


if __name__ == "__main__":
    unittest.main()
EOF
touch tests/__init__.py
printf '# Shop admin\n\nTests: `python3 -m unittest`.\n' > README.md
git init -q
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -q -m "Admin page"
