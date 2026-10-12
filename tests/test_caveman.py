# tests/test_caveman.py
"""Offline checks for private initialization, service activation, and selection."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]


class CavemanTest(unittest.TestCase):
    def setUp(self):
        previous_umask = os.umask(0o077)
        self.addCleanup(os.umask, previous_umask)
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        loader = importlib.machinery.SourceFileLoader("cavemanctl", str(REPO / "home/dot_local/bin/executable_cavemanctl"))
        self.ctl = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
        loader.exec_module(self.ctl)
        self.ctl.HOME = self.home
        self.ctl.PRIVATE = self.home / ".caveman/oc2"
        self.args = types.SimpleNamespace(provider="example", upstream="https://api.example.com",
                                          backend="native",
                                          listen="127.0.0.1:8787", url="http://127.0.0.1:8787",
                                          allow_private_host=[])

    def init(self):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.ctl.init(self.args)
        return out.getvalue()

    def test_init_preserves_existing_private_settings_and_secret(self):
        out = self.init()
        path = self.ctl.PRIVATE / "settings.json"
        token = self.ctl.PRIVATE / "proxy-token"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(token.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(token.read_text(), out)
        config = self.ctl.settings()
        self.assertFalse(config["enabled"])
        config["mode"] = "record"
        self.ctl.save(config)
        before = (path.read_bytes(), token.read_bytes())
        self.args.upstream = "https://different.example.com"
        self.init()
        self.assertEqual(before, (path.read_bytes(), token.read_bytes()))

    def test_secret_never_enters_proxy_file_or_argv(self):
        self.init()
        with patch.object(self.ctl.os, "execve") as execute:
            self.ctl.run()
        binary, argv, env = execute.call_args.args
        self.assertEqual(binary, self.home / ".caveman/bin/caveman-proxy")
        self.assertEqual(argv, [str(binary), "serve"])
        self.assertEqual(env["CAVEMAN_HOME"], str(self.ctl.PRIVATE))
        self.assertEqual(env["CAVEMAN_CCR_DB"], str(self.ctl.PRIVATE / "ccr.db"))
        self.assertEqual(env["DO_NOT_TRACK"], "1")
        self.assertNotIn(env["CAVEMAN_AUTH_TOKEN"], (self.ctl.PRIVATE / "proxy.json").read_text())

    def test_public_private_config_is_rejected(self):
        self.init()
        path = self.ctl.PRIVATE / "settings.json"
        path.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "private file"):
            self.ctl.settings()

    def test_malformed_listener_and_credential_urls_are_rejected(self):
        self.init()
        original = self.ctl.settings()
        for key, value in [("listen", "127.0.0.1:0"), ("provider", "../example"),
                           ("upstream", "https://user:secret@example.com"), ("mode", "unknown"),
                           ("enabled", "false"), ("allow_private_hosts", ["*"])]:
            with self.subTest(key=key):
                self.ctl.save({**original, key: value})
                with self.assertRaises(ValueError):
                    self.ctl.settings()

    def test_enable_waits_for_readiness_then_disable_preserves_config(self):
        self.init()
        before = self.ctl.settings()
        with patch.object(self.ctl, "service") as service, patch.object(self.ctl, "ready", return_value=True), \
                patch.object(self.ctl.sys, "argv", ["cavemanctl", "enable"]), contextlib.redirect_stdout(io.StringIO()):
            self.ctl.main()
        service.assert_called_once_with("enable")
        self.assertTrue(self.ctl.settings()["enabled"])
        with patch.object(self.ctl.sys, "argv", ["cavemanctl", "disable"]), contextlib.redirect_stdout(io.StringIO()):
            self.ctl.main()
        self.assertEqual(before, self.ctl.settings())

    def test_mcp_and_proxy_share_the_same_store(self):
        with patch.object(self.ctl.sys, "argv", ["cavemanctl", "mcp"]), patch.object(self.ctl.os, "execve") as execute:
            self.ctl.main()
        _, argv, env = execute.call_args.args
        self.assertEqual(argv, [str(self.home / ".caveman/bin/caveman-mcp")])
        self.assertEqual(env["CAVEMAN_CCR_DB"], str(self.ctl.PRIVATE / "ccr.db"))

    def test_user_service_lifecycle_uses_platform_native_commands(self):
        for system in ["Linux", "Darwin"]:
            with self.subTest(system=system), patch.object(self.ctl.platform, "system", return_value=system), \
                    patch.object(self.ctl.subprocess, "run", return_value=types.SimpleNamespace(returncode=1)) as run:
                self.ctl.service("enable")
                commands = [c.args[0] for c in run.call_args_list]
                self.assertTrue(all(c[0] == ("systemctl" if system == "Linux" else "launchctl") for c in commands))
                self.assertNotIn("sudo", str(commands))

    def test_compose_backend_never_starts_a_user_service(self):
        self.args.backend = "compose"
        self.init()
        with patch.object(self.ctl, "service") as service, patch.object(self.ctl, "ready", return_value=True), \
                patch.object(self.ctl.sys, "argv", ["cavemanctl", "enable"]), contextlib.redirect_stdout(io.StringIO()):
            self.ctl.main()
        service.assert_not_called()
        with self.assertRaisesRegex(ValueError, "Compose owns"):
            self.ctl.run()
        self.ctl.render(self.ctl.settings())
        self.assertEqual((self.ctl.PRIVATE / "proxy.env").stat().st_mode & 0o777, 0o600)

    def render(self, source, system="linux", opencode=True):
        config = self.home / "chezmoi.toml"
        config.write_text(f'[data.components.ai]\nopencode = {str(opencode).lower()}\n')
        with (REPO / source).open() as stream:
            return subprocess.check_output(["chezmoi", "execute-template", "--source", str(REPO), "--config", str(config),
                                            "--override-data", json.dumps({"chezmoi": {"os": system}})], stdin=stream, text=True)

    def test_platform_and_selection_gates(self):
        for system in ["linux", "darwin"]:
            for selected in [False, True]:
                with self.subTest(system=system, selected=selected):
                    ignored = self.render("home/.chezmoiignore", system, selected).splitlines()
                    self.assertEqual(".local/bin/cavemanctl" in ignored, not selected)
                    self.assertEqual(".config/opencode/plugins/caveman.js" in ignored, not selected)
                    self.assertEqual(".config/systemd/user/dotfiles-caveman.service" in ignored, not(selected and system == "linux"))
                    self.assertEqual("Library/LaunchAgents/io.github.crag-h4k.dotfiles.caveman.plist" in ignored, not(selected and system == "darwin"))

    def test_launchagent_is_disabled_until_explicit_activation(self):
        rendered = self.render("home/Library/LaunchAgents/io.github.crag-h4k.dotfiles.caveman.plist.tmpl", "darwin")
        value = plistlib.loads(rendered.encode())
        self.assertTrue(value["Disabled"])
        self.assertEqual(value["EnvironmentVariables"]["DO_NOT_TRACK"], "1")


if __name__ == "__main__":
    unittest.main()
