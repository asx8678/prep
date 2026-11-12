"""What a right fix of e2e-second-place must do. No run sees this file.

tests/run.sh section 28 runs it in the project's folder.
"""
import unittest

import report
import stock


class Acceptance(unittest.TestCase):
    def test_the_reported_place(self):
        self.assertEqual(stock.low_stock([("bolt", 5)], 5), ["bolt"])

    def test_the_second_place(self):
        self.assertEqual(report.reorder_lines([("bolt", 5)], 5), ["bolt: reorder"])

    def test_an_item_above_the_limit_stays_out(self):
        self.assertEqual(stock.low_stock([("bolt", 6)], 5), [])
