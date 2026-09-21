#!/usr/bin/env python3
# tests/test_package_run.py
"""Exercise the persisted packageRun trigger through a real chezmoi init."""

import fcntl
import os
import pty
import shutil
import subprocess
import tempfile
import termios
import threading
import tomllib
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]


class PackageRunTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        shutil.copytree(
            REPO,
            self.repo,
            ignore=shutil.ignore_patterns(".git", "vendor", "__pycache__"),
        )
        self.confirm_log = self.root / "confirm.log"
        (self.repo / "scripts" / "confirm-install.sh").write_text(
            "#!/usr/bin/env bash\n"
            "printf 'called\\n' >>\"$TEST_CONFIRM_LOG\"\n"
            "printf '%s\\n' \"$TEST_INSTALL_CHOICE\"\n",
            encoding="utf-8",
        )

    def tearDown(self):
        self.temp.cleanup()

    def seed_config(
        self, *, package_run=None, install_mode="configs", component_selection="1 2 3 4"
    ):
        config = self.root / "seed.toml"
        lines = [
            "[data]",
            f'componentSelection = "{component_selection}"',
            'gitSelection = "ignore_global"',
            'aiSelection = ""',
            'terminalSelection = ""',
            'palette = "dracula"',
            'zshTheme = "gud"',
        ]
        if install_mode is not None:
            lines.append(f'installMode = "{install_mode}"')
        if package_run is not None:
            lines.append(f"packageRun = {package_run}")
        config.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return config

    def run_init(self, config, *, choice="packages", extra_env=None):
        generated = self.root / "generated.toml"
        destination = self.root / "home"
        destination.mkdir(exist_ok=True)
        env = os.environ.copy()
        env.update(
            {
                "TEST_CONFIRM_LOG": str(self.confirm_log),
                "TEST_INSTALL_CHOICE": choice,
            }
        )
        env.pop("DOTFILES_INSTALL_MODE", None)
        env.pop("DOTFILES_NO_TUI", None)
        env.pop("DOTFILES_PACKAGE_UPDATE", None)
        env.pop("DOTFILES_ASSUME_YES", None)
        if extra_env:
            env.update(extra_env)

        master, slave = pty.openpty()

        def child_setup():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        command = [
            "chezmoi",
            "--source",
            str(self.repo),
            "--config",
            str(config),
            "--destination",
            str(destination),
            "--refresh-externals=never",
            "init",
            "--config-path",
            str(generated),
        ]
        process = subprocess.Popen(
            command,
            stdin=slave,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            env=env,
            preexec_fn=child_setup,
            close_fds=True,
        )

        def drain():
            try:
                while os.read(master, 4096):
                    pass
            except OSError:
                pass

        reader = threading.Thread(target=drain, daemon=True)
        reader.start()
        os.close(slave)
        _, stderr = process.communicate(timeout=30)
        os.close(master)
        reader.join(timeout=2)
        self.assertEqual(process.returncode, 0, stderr.decode())
        with generated.open("rb") as handle:
            return tomllib.load(handle)["data"]

    def headless_init(self, config, generated, *, extra_env, apply=False):
        destination = self.root / "headless-home"
        destination.mkdir(exist_ok=True)
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(destination),
                "XDG_CONFIG_HOME": str(self.root / "xdg-config"),
                "XDG_STATE_HOME": str(self.root / "xdg-state"),
                "DOTFILES_NO_TUI": "1",
            }
        )
        for name in (
            "DOTFILES_INSTALL_MODE",
            "DOTFILES_PACKAGE_UPDATE",
            "DOTFILES_ASSUME_YES",
        ):
            env.pop(name, None)
        env.update(extra_env)
        command = [
            shutil.which("chezmoi"),
            "--source",
            str(self.repo),
            "--config",
            str(config),
            "--destination",
            str(destination),
            "--refresh-externals=never",
            "init",
        ]
        if apply:
            command.append("--apply")
        command.extend(["--config-path", str(generated), "--no-tty"])
        return subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True,
            timeout=30,
            check=False,
        )

    def test_scoped_packages_increments(self):
        data = self.run_init(
            self.seed_config(package_run=7),
            extra_env={"DOTFILES_PACKAGE_UPDATE": "1"},
        )
        self.assertEqual(data["packageRun"], 8)
        self.assertEqual(data["installMode"], "packages")
        self.assertEqual(self.confirm_log.read_text(encoding="utf-8"), "called\n")

    def test_interactive_configs_keeps_counter(self):
        data = self.run_init(
            self.seed_config(package_run=7, install_mode="packages"),
            choice="configs",
            extra_env={"DOTFILES_PACKAGE_UPDATE": "1"},
        )
        self.assertEqual(data["packageRun"], 7)
        self.assertEqual(data["installMode"], "configs")

    def test_automation_keeps_counter(self):
        data = self.run_init(
            self.seed_config(package_run=7),
            extra_env={
                "DOTFILES_INSTALL_MODE": "packages",
                "DOTFILES_NO_TUI": "1",
            },
        )
        self.assertEqual(data["packageRun"], 7)
        self.assertFalse(self.confirm_log.exists())

    def test_reinit_keeps_counter(self):
        data = self.run_init(
            self.seed_config(package_run=7),
            extra_env={"DOTFILES_NO_TUI": "1"},
        )
        self.assertEqual(data["packageRun"], 7)
        self.assertFalse(self.confirm_log.exists())

    def test_first_packages_is_one(self):
        data = self.run_init(
            self.seed_config(package_run=None, install_mode=None),
            extra_env={"DOTFILES_NO_TUI": "1"},
        )
        self.assertEqual(data["packageRun"], 1)

    def test_headless_update_requires_complete_opt_in(self):
        cases = (
            {"DOTFILES_PACKAGE_UPDATE": "1"},
            {
                "DOTFILES_PACKAGE_UPDATE": "1",
                "DOTFILES_INSTALL_MODE": "packages",
            },
            {
                "DOTFILES_PACKAGE_UPDATE": "1",
                "DOTFILES_ASSUME_YES": "1",
            },
        )
        for index, env in enumerate(cases):
            with self.subTest(env=env):
                result = self.headless_init(
                    self.seed_config(package_run=4),
                    self.root / f"rejected-{index}.toml",
                    extra_env=env,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "Headless package update requires DOTFILES_PACKAGE_UPDATE=1",
                    result.stderr,
                )

    def test_headless_update_reruns_once_per_increment(self):
        counter = self.root / "install-count"
        (self.repo / "scripts" / "install.sh").write_text(
            "#!/usr/bin/env bash\n"
            f"printf 'run\\n' >>{str(counter)!r}\n",
            encoding="utf-8",
        )
        env = {
            "DOTFILES_PACKAGE_UPDATE": "1",
            "DOTFILES_INSTALL_MODE": "packages",
            "DOTFILES_ASSUME_YES": "1",
        }
        seed = self.seed_config(
            package_run=4,
            install_mode="configs",
            component_selection="8",
        )
        first = self.root / "headless-first.toml"
        result = self.headless_init(seed, first, extra_env=env, apply=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(counter.read_text(encoding="utf-8"), "run\n")
        with first.open("rb") as handle:
            self.assertEqual(tomllib.load(handle)["data"]["packageRun"], 5)

        destination = self.root / "headless-home"
        plain_env = os.environ.copy()
        plain_env.update(
            {
                "HOME": str(destination),
                "XDG_CONFIG_HOME": str(self.root / "xdg-config"),
                "XDG_STATE_HOME": str(self.root / "xdg-state"),
                "DOTFILES_NO_TUI": "1",
            }
        )
        for name in (
            "DOTFILES_INSTALL_MODE",
            "DOTFILES_PACKAGE_UPDATE",
            "DOTFILES_ASSUME_YES",
        ):
            plain_env.pop(name, None)
        plain = subprocess.run(
            [
                shutil.which("chezmoi"),
                "--source",
                str(self.repo),
                "--config",
                str(first),
                "--destination",
                str(destination),
                "apply",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=plain_env,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertEqual(counter.read_text(encoding="utf-8"), "run\n")

        second = self.root / "headless-second.toml"
        result = self.headless_init(first, second, extra_env=env, apply=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(counter.read_text(encoding="utf-8"), "run\nrun\n")
        with second.open("rb") as handle:
            self.assertEqual(tomllib.load(handle)["data"]["packageRun"], 6)

    def test_declined_packages_only_materialize_missing_external(self):
        real_git = shutil.which("git")
        remote = self.root / "external.git"
        subprocess.run([real_git, "init", "--bare", str(remote)], check=True)
        (self.repo / "home" / ".chezmoiexternal.toml").write_text(
            '[".zsh/test-plugin"]\n'
            'type = "git-repo"\n'
            f'url = "file://{remote}"\n'
            'refreshPeriod = "0"\n'
            '[".zsh/test-plugin".pull]\n'
            'args = ["--ff-only"]\n',
            encoding="utf-8",
        )

        stubs = self.root / "stubs"
        stubs.mkdir()
        git_log = self.root / "git.log"
        manager_log = self.root / "manager.log"
        (stubs / "git").write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$*\" >>{str(git_log)!r}\n"
            f"exec {real_git!r} \"$@\"\n",
            encoding="utf-8",
        )
        for manager in ("brew", "apt", "apt-get", "npm", "pip", "luarocks"):
            (stubs / manager).write_text(
                "#!/bin/sh\n"
                f"printf '%s %s\\n' {manager!r} \"$*\" >>{str(manager_log)!r}\n"
                "exit 97\n",
                encoding="utf-8",
            )
        for stub in stubs.iterdir():
            stub.chmod(0o755)

        generated = self.root / "declined.toml"
        destination = self.root / "declined-home"
        destination.mkdir()
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(destination),
                "PATH": f"{stubs}:{env['PATH']}",
                "DOTFILES_INSTALL_MODE": "packages",
                "DOTFILES_NO_TUI": "1",
                "DOTFILES_PLAN_OS": "macos",
                "DOTFILES_TTY": str(self.root / "no-tty"),
                "DOTFILES_PKG_CONFIRM_SENTINEL": str(self.root / "no-sentinel"),
            }
        )
        env.pop("DOTFILES_ASSUME_YES", None)
        result = subprocess.run(
            [
                shutil.which("chezmoi"),
                "--source",
                str(self.repo),
                "--config",
                str(
                    self.seed_config(
                        package_run=0,
                        install_mode="packages",
                        component_selection="1",
                    )
                ),
                "--destination",
                str(destination),
                "init",
                "--apply",
                "--config-path",
                str(generated),
                "--no-tty",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((destination / ".zsh" / "test-plugin" / ".git").exists())
        git_calls = git_log.read_text(encoding="utf-8")
        self.assertIn("clone", git_calls)
        self.assertNotIn("submodule", git_calls)
        self.assertNotIn("fetch", git_calls)
        self.assertNotIn("pull", git_calls)
        self.assertFalse(manager_log.exists())


if __name__ == "__main__":
    unittest.main()
