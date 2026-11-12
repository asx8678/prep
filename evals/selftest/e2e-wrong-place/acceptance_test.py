"""What a right fix of e2e-wrong-place must do. No run sees this file.

tests/run.sh section 28 runs it in the project's folder.
"""
import unittest

import invoice
import money
import refund


class Acceptance(unittest.TestCase):
    def test_the_reported_total(self):
        self.assertEqual(invoice.total([("12.5", 2)]), 2500)

    def test_the_other_caller(self):
        self.assertEqual(refund.refund_amount("12.5", 100), 1250)

    def test_the_cause(self):
        for text, cents in (("12.5", 1250), ("0.05", 5), ("7", 700), ("12.50", 1250)):
            with self.subTest(text=text):
                self.assertEqual(money.to_cents(text), cents)
