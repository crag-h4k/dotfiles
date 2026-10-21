"""Exercise terminal-test deadlines and process-group cleanup."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).with_name("ctty_run.py")
MODES = ("--ctty", "--stdin-tty", "--stdin-only", "--none")


class TerminalRunnerTests(unittest.TestCase):
    def test_exit_status_and_output_survive(self):
        for mode in MODES:
            with self.subTest(mode=mode):
                result = subprocess.run(
                    [sys.executable, str(HELPER), mode, sys.executable,
                     "-c", "print('finished'); raise SystemExit(7)"],
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 7)
                self.assertEqual(result.stdout, "finished\n")

    def test_timeout_closes_child_and_grandchild_output_pipes(self):
        code = (
            "import subprocess, sys, time; "
            "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
            "print('started', flush=True); time.sleep(30)"
        )
        for mode in MODES:
            with self.subTest(mode=mode):
                result = subprocess.run(
                    [sys.executable, str(HELPER), mode, sys.executable, "-c", code],
                    env={**os.environ, "CTTY_TIMEOUT": "1"},
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 124)
                self.assertEqual(result.stdout, "started\n")
                self.assertIn("command exceeded 1 seconds", result.stderr)

    def test_timeout_keeps_terminal_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "tty.log"
            result = subprocess.run(
                [sys.executable, str(HELPER), "--ctty", sys.executable, "-c",
                 "import time; open('/dev/tty', 'w').write('waiting for input\\n'); time.sleep(30)"],
                env={**os.environ, "CTTY_TIMEOUT": "1", "CTTY_LOG": str(log)},
                capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(result.returncode, 124)
            self.assertIn("waiting for input", log.read_text())


if __name__ == "__main__":
    unittest.main()
