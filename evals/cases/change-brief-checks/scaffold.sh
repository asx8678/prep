#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests
cat > server.py <<'EOF'
"""Notes service. Run: python3 server.py (serves on port 8000)."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

import store


def route(method, path):
    """Return (status, body) for a request."""
    if method == "GET" and path == "/notes":
        return 200, json.dumps(store.all_notes())
    return 404, "not found"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        status, body = route("GET", self.path)
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    HTTPServer(("127.0.0.1", 8000), Handler).serve_forever()


if __name__ == "__main__":
    main()
EOF
cat > store.py <<'EOF'
_notes = ["first note"]


def all_notes():
    return list(_notes)


def add_note(text):
    if not text.strip():
        raise ValueError("empty note")
    _notes.append(text)
EOF
cat > tests/test_routes.py <<'EOF'
import unittest

from server import route


class RouteTest(unittest.TestCase):
    def test_lists_notes(self):
        self.assertEqual(route("GET", "/notes")[0], 200)

    def test_unknown_path(self):
        self.assertEqual(route("GET", "/nope"), (404, "not found"))


if __name__ == "__main__":
    unittest.main()
EOF
cat > tests/test_store.py <<'EOF'
import unittest

import store


class StoreTest(unittest.TestCase):
    def test_rejects_empty_note(self):
        with self.assertRaises(ValueError):
            store.add_note("  ")


if __name__ == "__main__":
    unittest.main()
EOF
touch tests/__init__.py
printf '# Notes\n\nRun: `python3 server.py` (serves on port 8000).\nRoute tests: `python3 -m unittest tests.test_routes`.\nStore tests: `python3 -m unittest tests.test_store`.\n' > README.md
git init -q
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -q -m "Notes service"
