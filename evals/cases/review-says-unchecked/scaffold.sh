#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests
cat > pager.py <<'EOF'
"""Split a list of items into pages for the list endpoint."""


def page(items, number, size=10):
    """Return page `number` (1-based) of `items`."""
    if number < 1 or size < 1:
        raise ValueError("number and size must be at least 1")
    start = (number - 1) * size
    end = start + size + 1
    return items[start:end]


def page_count(items, size=10):
    return len(items) // size
EOF
cat > export.py <<'EOF'
"""Write items to CSV for the export button."""
import csv


def write_csv(path, items):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name"])
        for item in items:
            writer.writerow([item["id"], item["name"]])
EOF
cat > tests/test_pager.py <<'EOF'
import unittest

from pager import page


class PageTest(unittest.TestCase):
    def test_first_page_of_a_short_list(self):
        self.assertEqual(page([1, 2, 3], 1), [1, 2, 3])

    def test_rejects_page_zero(self):
        with self.assertRaises(ValueError):
            page([1, 2, 3], 0)


if __name__ == "__main__":
    unittest.main()
EOF
touch tests/__init__.py
printf '# Items\n\nTests: `python3 -m unittest`.\n' > README.md
git init -q
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -q -m "Items list and export"
