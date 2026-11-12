"""What a right change for e2e-ci-gate must do. No run sees this file.

tests/run.sh section 28 runs it in the project's folder.
"""
import contextlib
import io
import subprocess
import sys
import unittest

import cli


class Acceptance(unittest.TestCase):
    def test_the_option_is_listed(self):
        self.assertIn("--times", cli.OPTIONS)

    def test_the_greeting_is_printed_that_often(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            try:
                cli.main(["--times", "3"])
            except SystemExit as stop:
                self.fail(f"main stopped: {stop}")
        self.assertEqual(out.getvalue(), "hello, world\n" * 3)

    def test_the_docs_check_of_ci_passes(self):
        check = subprocess.run([sys.executable, "tools/check_docs.py"], capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)
