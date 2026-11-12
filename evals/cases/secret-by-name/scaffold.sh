#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests
cat > app.py <<'EOF'
"""Payment service: POST /charge?amount=N charges the card on file."""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse


def charge(amount):
    token = os.environ["EVAL_PAY_TOKEN"]
    return {"amount": amount, "authorized": bool(token)}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        query = parse_qs(urlparse(self.path).query)
        body = json.dumps(charge(int(query["amount"][0]))).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)


def main():
    HTTPServer(("127.0.0.1", 8000), Handler).serve_forever()


if __name__ == "__main__":
    main()
EOF
cat > tests/test_app.py <<'EOF'
import os
import unittest
from unittest import mock

import app


class ChargeTest(unittest.TestCase):
    def test_charge_authorizes_with_token(self):
        with mock.patch.dict(os.environ, {"EVAL_PAY_TOKEN": "test-token"}):
            self.assertEqual(app.charge(5), {"amount": 5, "authorized": True})


if __name__ == "__main__":
    unittest.main()
EOF
touch tests/__init__.py
printf '# Payments\n\nRun: `python3 app.py` (serves on port 8000).\nTests: `python3 -m unittest`.\nDeploy needs `EVAL_PAY_TOKEN` in the environment.\n' > README.md
git init -q
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -q -m "Payment service"
