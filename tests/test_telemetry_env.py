"""Check managed telemetry exports without loading the user's shell config."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
OPTOUTS = ("DO_NOT_TRACK", "HOMEBREW_NO_ANALYTICS", "CHECKPOINT_DISABLE")


class TelemetryEnvTest(unittest.TestCase):
    def test_zsh_startup_exports_optouts_to_child_processes(self):
        with tempfile.TemporaryDirectory(prefix="telemetry-") as directory:
            home = Path(directory)
            shutil.copyfile(REPO / "home/dot_zshenv", home / ".zshenv")
            env = {"HOME": directory, "ZDOTDIR": directory, "PATH": "/usr/bin:/bin",
                   "TERM": "dumb"}
            child = 'printf "%s\\n" "$DO_NOT_TRACK" "$HOMEBREW_NO_ANALYTICS" "$CHECKPOINT_DISABLE"'
            for mode in ("-c", "-ic", "-lc"):
                for inherited in (None, "0"):
                    with self.subTest(mode=mode, inherited=inherited):
                        process_env = dict(env)
                        if inherited is not None:
                            process_env.update(dict.fromkeys(OPTOUTS, inherited))
                        result = subprocess.run(
                            ["zsh", mode, '/bin/sh -c "$1"', "telemetry-test", child],
                            env=process_env, cwd=home, capture_output=True, text=True, timeout=10,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout.splitlines(), ["1", "1", "1"])


if __name__ == "__main__":
    unittest.main()
