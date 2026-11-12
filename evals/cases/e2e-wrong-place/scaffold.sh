#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests
# The cause: "12.5" becomes 1205 cents. The grader matches these lines, so
# keep them as they are.
cat > money.py <<'EOF'
def to_cents(text):
    """Cents for an amount such as "12.50" or "7"."""
    whole, _, part = text.partition(".")
    return int(whole) * 100 + int(part or 0)
EOF
# The file the request blames.
cat > invoice.py <<'EOF'
from money import to_cents


def total(lines):
    """Cents for all lines; a line is a price and a quantity."""
    return sum(to_cents(price) * quantity for price, quantity in lines)
EOF
# A second caller, which a fix in invoice.py alone leaves wrong.
cat > refund.py <<'EOF'
from money import to_cents


def refund_amount(price, percent):
    """Cents to pay back when `percent` of a price is refunded."""
    return to_cents(price) * percent // 100
EOF
cat > tests/test_money.py <<'EOF'
import unittest

from money import to_cents


class ToCentsTest(unittest.TestCase):
    def test_an_amount_with_cents(self):
        self.assertEqual(to_cents("12.50"), 1250)

    def test_a_whole_amount(self):
        self.assertEqual(to_cents("7"), 700)


if __name__ == "__main__":
    unittest.main()
EOF
cat > tests/test_invoice.py <<'EOF'
import unittest

from invoice import total


class TotalTest(unittest.TestCase):
    def test_adds_up_the_lines(self):
        self.assertEqual(total([("12.50", 2), ("7", 1)]), 3200)


if __name__ == "__main__":
    unittest.main()
EOF
cat > tests/test_refund.py <<'EOF'
import unittest

from refund import refund_amount


class RefundAmountTest(unittest.TestCase):
    def test_half_of_a_price(self):
        self.assertEqual(refund_amount("12.50", 50), 625)


if __name__ == "__main__":
    unittest.main()
EOF
touch tests/__init__.py
printf '# Billing\n\nTests: `python3 -m unittest`.\n' > README.md
git init -q
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -q -m "Invoices and refunds"
