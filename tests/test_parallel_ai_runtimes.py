"""Runtime scheduling with real subprocesses and disposable installer stubs."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ("opencode2", "copilot", "ssh-mcp", "caveman", "openviking")
NAMES = ("@opencode/cli", "@github/copilot", "ssh-mcp", "@caveman-ai/cli", "openviking")
LEAF = '''import json, os, pathlib, sys, time
name = sys.argv[1]
root = pathlib.Path(os.environ["TEST_ROOT"])
if os.environ.get("TEST_REQUIRE_BOOTSTRAP") == "true" and not (root / "node-ready").exists():
    sys.exit(91)
start = time.monotonic()
(root / (name + ".started")).touch()
if os.environ.get("TEST_BARRIER") == "true" and name in ("opencode2", "copilot", "openviking"):
    deadline = time.monotonic() + 5
    while not all((root / (n + ".started")).exists() for n in ("opencode2", "copilot", "openviking")):
        if time.monotonic() > deadline: sys.exit(90)
        time.sleep(0.01)
if os.environ.get("TEST_HANG") == "true":
    import subprocess
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    (root / (name + ".pids")).write_text(f"{os.getpid()} {child.pid}")
    time.sleep(60)
time.sleep(0.15)
(root / (name + ".json")).write_text(json.dumps({
    "start": start, "end": time.monotonic(),
    "opencode": os.environ.get("OPENCODE2_VERSION"),
    "copilot": os.environ.get("COPILOT_VERSION"),
    "openviking": os.environ.get("OPENVIKING_VERSION"),
    "age": os.environ.get("NPM_CONFIG_MIN_RELEASE_AGE"),
}))
print("installer output " + name, flush=True)
sys.exit(1 if os.environ.get("TEST_FAIL") == name else 0)
'''


class ParallelRuntimesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        for name in ("common.sh", "install-ai-runtime-group.sh", "install-ai-runtimes.py"):
            shutil.copy2(ROOT / "scripts" / name, self.scripts / name)
        self.leaf = self.root / "leaf.py"
        self.leaf.write_text(LEAF)
        for name in PACKAGES:
            (self.scripts / f"install-{name}.sh").write_text(f'exec "$TEST_PYTHON" "$TEST_LEAF" {name}\n')
        self.plan = self.root / "plan"
        self.write_plan()
        self.result = self.root / "result"
        self.env = {
            **os.environ, "HOME": str(self.root / "home"), "TEST_ROOT": str(self.root),
            "TEST_PYTHON": sys.executable, "TEST_LEAF": str(self.leaf),
            "DOTFILES_PACKAGES_APPROVED": "true", "DOTFILES_PACKAGE_PLAN": str(self.plan),
            "DOTFILES_NODE_READY": "true", "DOTFILES_RUNTIME_JOBS": "3",
            "INSTALL_AI_OPENCODE": "true", "INSTALL_AI_COPILOT": "true",
            "INSTALL_AI_OPENVIKING": "true", "NPM_CONFIG_MIN_RELEASE_AGE": "7",
        }
        self.env.pop("OPENCODE2_NPM_PREFIX", None)

    def write_plan(self, **statuses):
        self.plan.write_text("".join(
            f'{"uv-tool" if name == "openviking" else "npm"}\t{name}\t{statuses.get(package, "planned")}\tpinned\torigin\tprobe\t-\t1.2.3\ttest reason\n'
            for package, name in zip(PACKAGES, NAMES)
        ))

    def run_install(self, **env):
        return subprocess.run(
            [sys.executable, str(self.scripts / "install-ai-runtimes.py"), str(self.result)],
            env={**self.env, **env}, capture_output=True, text=True, timeout=12,
        )

    def records(self):
        return {name: json.loads((self.root / f"{name}.json").read_text())
                for name in PACKAGES if (self.root / f"{name}.json").exists()}

    def test_groups_overlap_but_shared_prefix_stays_serial(self):
        result = self.run_install(TEST_BARRIER="true")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.result.read_text().strip(), "5 0 0")
        records = self.records()
        for first, second in (("copilot", "ssh-mcp"), ("ssh-mcp", "caveman")):
            self.assertLessEqual(records[first]["end"], records[second]["start"])
        for package in ("opencode2", "copilot", "openviking"):
            self.assertEqual(records[package]["age"], "0")
        self.assertEqual(records["opencode2"]["opencode"], "1.2.3")
        self.assertEqual(records["copilot"]["copilot"], "1.2.3")
        self.assertEqual(records["openviking"]["openviking"], "1.2.3")
        self.assertIn("[shared-npm] installer output caveman", result.stdout)

    def test_parallelism_limit_and_serial_override(self):
        for jobs in ("1", "2"):
            with self.subTest(jobs=jobs):
                result = self.run_install(DOTFILES_RUNTIME_JOBS=jobs)
                self.assertEqual(result.returncode, 0, result.stderr)
                events = sorted((record[key], change) for record in self.records().values()
                                for key, change in (("start", 1), ("end", -1)))
                active = peak = 0
                for _, change in events:
                    active += change
                    peak = max(peak, active)
                self.assertEqual(peak, int(jobs))

    def test_shared_opencode_prefix_forces_serial_installation(self):
        result = self.run_install(OPENCODE2_NPM_PREFIX=str(Path(self.env["HOME"]) / ".local"))
        self.assertEqual(result.returncode, 0, result.stderr)
        records = sorted(self.records().values(), key=lambda record: record["start"])
        for first, second in zip(records, records[1:]):
            self.assertLessEqual(first["end"], second["start"])

    def test_failure_does_not_stop_other_installers(self):
        result = self.run_install(TEST_FAIL="ssh-mcp")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.result.read_text().strip(), "4 1 0")
        self.assertEqual(set(self.records()), set(PACKAGES))

    def test_current_and_blocked_entries_do_not_run(self):
        self.write_plan(copilot="installed", **{"ssh-mcp": "blocked"})
        result = self.run_install()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.result.read_text().strip(), "3 1 1")
        self.assertEqual(set(self.records()), {"opencode2", "caveman", "openviking"})

    def test_node_failure_only_skips_node_consumers(self):
        result = self.run_install(DOTFILES_NODE_READY="false")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.result.read_text().strip(), "1 0 4")
        self.assertEqual(set(self.records()), {"openviking"})

    def test_unselected_runtimes_and_unapproved_plan_do_not_install(self):
        result = self.run_install(INSTALL_AI_OPENCODE="false", INSTALL_AI_COPILOT="false", INSTALL_AI_OPENVIKING="false")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.result.read_text().strip(), "0 0 0")
        result = self.run_install(DOTFILES_PACKAGES_APPROVED="false")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.records(), {})

    def test_termination_stops_workers_and_their_children(self):
        proc = subprocess.Popen(
            [sys.executable, str(self.scripts / "install-ai-runtimes.py"), str(self.result)],
            env={**self.env, "TEST_HANG": "true"}, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        try:
            deadline = time.monotonic() + 5
            while len(list(self.root.glob("*.pids"))) != 3:
                self.assertLess(time.monotonic(), deadline, "workers did not start")
                time.sleep(0.01)
            proc.send_signal(signal.SIGTERM)
            proc.communicate(timeout=5)
            self.assertEqual(proc.returncode, 130)
            self.assertFalse(self.result.exists())
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()

    def run_top_level(self, **env):
        shutil.copy2(ROOT / "scripts/install.sh", self.scripts / "install.sh")
        with (self.scripts / "common.sh").open("a") as stream:
            stream.write('''
os_detect() { printf '%s' "${TEST_OS:-macos}"; }
pkg_confirm() { [[ "${TEST_APPROVE:-true}" == true ]]; }
verify_node_runtime() { touch "$TEST_ROOT/node-ready"; }
ensure_chezmoi() { :; }
package_plan_resolve_deferred_git() { touch "$TEST_ROOT/git-started"; }
''')
        planner = self.scripts / "package-plan.sh"
        planner.write_text("#!/bin/sh\nexit 0\n")
        planner.chmod(0o755)
        binaries = self.root / "bin"
        binaries.mkdir(exist_ok=True)
        brew = binaries / "brew"
        brew.write_text('''#!/bin/sh
printf '%s\n' "$*" >>"$TEST_ROOT/brew.log"
[ -z "${HOMEBREW_NO_INSTALL_UPGRADE+x}" ] || exit 97
[ "${TEST_BREW_FAIL:-false}" != true ]
''')
        brew.chmod(0o755)
        sudo = binaries / "sudo"
        sudo.write_text('''#!/bin/sh
printf '%s\n' "$*" >>"$TEST_ROOT/apt.log"
[ "${TEST_APT_FAIL:-false}" != true ]
''')
        sudo.chmod(0o755)
        plan = self.plan.read_bytes()
        result = subprocess.run(
            ["bash", str(self.scripts / "install.sh")],
            env={**self.env, "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                 "XDG_STATE_HOME": str(self.root / "state"), "DOTFILES_PACKAGES_APPROVED": "false",
                 "DOTFILES_INSTALL_MODE": "packages", "INSTALL_ZSH": "false", "INSTALL_TMUX": "false",
                 "INSTALL_NEOVIM": "false", "INSTALL_AI_CODECOMPANION": "false",
                 "TEST_REQUIRE_BOOTSTRAP": "true", **env},
            capture_output=True, text=True, timeout=12,
        )
        self.plan.write_bytes(plan)
        return result

    def test_top_level_bootstraps_first_and_reports_worker_failures(self):
        result = self.run_top_level(TEST_FAIL="ssh-mcp")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("package run summary: ok=6 failed=1 skipped=0", result.stdout)
        self.assertEqual(set(self.records()), set(PACKAGES))
        self.assertTrue((self.root / "git-started").exists())

    def test_declined_top_level_run_does_not_launch_workers(self):
        result = self.run_top_level(TEST_APPROVE="false")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.records(), {})
        self.assertFalse((self.root / "node-ready").exists())

    def test_brew_missing_and_outdated_formulae_use_one_approved_transaction(self):
        self.plan.write_text(
            'brew-formula\tgum\tplanned\tfloating\tHomebrew\tgum\t-\t-\tmissing\n'
            'brew-formula\tgit\tupdate\tfloating\tHomebrew\tgit\t1\t2\toutdated\n'
            'brew-formula\tpython3\tinstalled\tfloating\tHomebrew\tpython3\t2\t2\tcurrent\n'
        )
        flags = {"INSTALL_AI_OPENCODE": "false", "INSTALL_AI_COPILOT": "false", "INSTALL_AI_OPENVIKING": "false"}
        result = self.run_top_level(HOMEBREW_NO_INSTALL_UPGRADE="1", **flags)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "brew.log").read_text(), "install --no-ask gum git\n")
        self.assertIn("package run summary: ok=2 failed=0 skipped=1", result.stdout)
        (self.root / "brew.log").unlink()
        result = self.run_top_level(TEST_BREW_FAIL="true", **flags)
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.root / "brew.log").read_text(), "install --no-ask gum git\n")
        self.assertIn("package run summary: ok=1 failed=1 skipped=1", result.stdout)
        (self.root / "brew.log").unlink()
        result = self.run_top_level(TEST_APPROVE="false", **flags)
        self.assertEqual(result.returncode, 0)
        self.assertFalse((self.root / "brew.log").exists())

    def test_debian_selected_packages_already_share_one_apt_transaction(self):
        self.plan.write_text(
            'apt\tgit\tplanned\tfloating\tDebian\tgit\t-\t2\tmissing\n'
            'apt\tcurl\tupdate\tfloating\tDebian\tcurl\t1\t3\toutdated\n'
            'apt\tzsh\tinstalled\tfloating\tDebian\tzsh\t2\t2\tcurrent\n'
        )
        flags = {"INSTALL_AI_OPENCODE": "false", "INSTALL_AI_COPILOT": "false", "INSTALL_AI_OPENVIKING": "false"}
        result = self.run_top_level(TEST_OS="debian", **flags)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "apt.log").read_text(), "apt-get install -y git=2 curl=3\n")
        self.assertIn("package run summary: ok=2 failed=0 skipped=3", result.stdout)
        (self.root / "apt.log").unlink()
        result = self.run_top_level(TEST_OS="debian", TEST_APT_FAIL="true", **flags)
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.root / "apt.log").read_text(), "apt-get install -y git=2 curl=3\n")
        self.assertIn("package run summary: ok=1 failed=1 skipped=3", result.stdout)


if __name__ == "__main__":
    unittest.main()
