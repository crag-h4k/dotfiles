# tests/test_openviking.py
"""Offline tests for OpenViking selection, private config, and service commands."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
ASSETS = REPO / "home/dot_local/share/dotfiles/openviking"
CONTROLLER = REPO / "home/dot_local/bin/executable_openvikingctl"


def load_module(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class OpenVikingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name) / "home"
        self.home.mkdir()
        self.ctl = load_module("openvikingctl", CONTROLLER)
        self.ctl.HOME = self.home
        self.ctl.PRIVATE = self.home / ".openviking"
        self.ctl.EXAMPLES = self.home / ".local/share/dotfiles/openviking"
        self.ctl.EXAMPLES.mkdir(parents=True)
        for source in ASSETS.glob("readonly_*.json"):
            shutil.copyfile(source, self.ctl.EXAMPLES / source.name.removeprefix("readonly_"))
        self.environment = patch.dict(os.environ, {"HOME": str(self.home)}, clear=True)
        self.environment.start()
        self.umask = os.umask(0o077)

    def tearDown(self):
        self.environment.stop()
        os.umask(self.umask)
        self.temp.cleanup()

    def init(self, profile="copilot-ollama"):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.ctl.init(profile)
        return out.getvalue()

    def test_private_config_is_seeded_once_and_never_reasserted(self):
        out = self.init()
        server = self.ctl.PRIVATE / "ov.conf"
        client = self.ctl.PRIVATE / "ovcli.conf"
        config = json.loads(server.read_text())
        key = config["server"]["root_api_key"]
        self.assertGreater(len(key), 32)
        self.assertNotIn(key, out)
        self.assertEqual(server.stat().st_mode & 0o777, 0o600)
        self.assertEqual(client.stat().st_mode & 0o777, 0o600)
        config["vlm"]["model"] = "local/custom-model"
        self.ctl.write_private(server, config, replace=True)
        before = (server.read_bytes(), client.read_bytes())
        self.init("openai")
        self.assertEqual(before, (server.read_bytes(), client.read_bytes()))

    def test_starter_profiles_have_local_storage_and_explicit_auth(self):
        for name in ("copilot-ollama", "ollama", "openai", "codex-ollama"):
            with self.subTest(name=name):
                config = json.loads((self.ctl.EXAMPLES / (name + ".json")).read_text())
                self.assertEqual(config["server"]["host"], "127.0.0.1")
                self.assertEqual(config["server"]["auth_mode"], "api_key")
                self.assertEqual(config["storage"]["workspace"], "./data")
                if name != "openai":
                    self.assertEqual(config["embedding"]["dense"]["dimension"], 768)
                    self.assertEqual(config["embedding"]["max_concurrent"], 1)
        client = json.loads((self.ctl.EXAMPLES / "ovcli.json").read_text())
        self.assertFalse(client["api_key"])
        self.assertTrue(client["plugin"]["autoCapture"])
        self.assertEqual(client["plugin"]["recallCompress"], "off")
        self.assertEqual(client["plugin"]["recallQueryExpansion"], "off")
        self.assertFalse(client["plugin"]["opencode"]["mcpEnabled"])
        self.assertEqual(client["plugin"]["opencode"]["commitKeepRecentCount"], 0)

    def test_public_config_is_refused_by_the_service(self):
        self.init()
        config = self.ctl.PRIVATE / "ov.conf"
        config.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "mode 600"):
            self.ctl.server_config()

    def test_nonloopback_and_unprotected_server_configs_are_refused(self):
        self.init()
        path = self.ctl.PRIVATE / "ov.conf"
        original = self.ctl.private_json(path)
        for field, value in (("host", "0.0.0.0"), ("auth_mode", "dev"), ("root_api_key", ""), ("port", "1933")):
            with self.subTest(field=field):
                config = json.loads(json.dumps(original))
                config["server"][field] = value
                self.ctl.write_private(path, config, replace=True)
                with self.assertRaises(ValueError):
                    self.ctl.server_config()

    def test_private_environment_accepts_values_not_commands(self):
        self.ctl.PRIVATE.mkdir(mode=0o700)
        path = self.ctl.PRIVATE / "service.env"
        path.write_text('export OPENAI_API_KEY="fixture value"\n# local comment\n')
        path.chmod(0o600)
        self.ctl.load_environment()
        self.assertEqual(os.environ["OPENAI_API_KEY"], "fixture value")
        path.write_text('echo unsafe\n')
        with self.assertRaisesRegex(ValueError, "not shell commands"):
            self.ctl.load_environment()

    def test_installer_location_record_is_used_without_managing_config(self):
        self.ctl.write_private(self.ctl.PRIVATE / "runtime.json", {"install_root": str(self.home / "custom-runtime")})
        self.assertEqual(self.ctl.runtime(), self.home / "custom-runtime/current")
        with patch.dict(os.environ, {"OPENVIKING_INSTALL_ROOT": str(self.home / "override-runtime")}):
            self.assertEqual(self.ctl.runtime(), self.home / "override-runtime/current")

    def test_existing_client_key_is_not_rotated_or_printed(self):
        self.init()
        path = self.ctl.PRIVATE / "ovcli.conf"
        client = self.ctl.private_json(path)
        client["api_key"] = "fixture-user-key"
        self.ctl.write_private(path, client, replace=True)
        before = path.read_bytes()
        with patch.object(self.ctl.urllib.request, "build_opener") as opener:
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.ctl.bootstrap_client()
        opener.assert_not_called()
        self.assertEqual(path.read_bytes(), before)
        self.assertNotIn("fixture-user-key", out.getvalue())

    def test_bootstrap_uses_root_for_admin_and_persists_a_user_key(self):
        self.init()
        responses = [io.BytesIO(b'{"result": {"account_id": "local"}}'),
                     io.BytesIO(b'{"result": {"user_key": "fixture-agent-key"}}')]
        with patch.object(self.ctl.urllib.request, "build_opener") as builder:
            builder.return_value.open.side_effect = responses
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.ctl.bootstrap_client()
        self.assertNotIn("fixture-agent-key", out.getvalue())
        self.assertEqual(self.ctl.private_json(self.ctl.PRIVATE / "ovcli.conf")["api_key"], "fixture-agent-key")
        request = builder.return_value.open.call_args_list[-1].args[0]
        self.assertEqual(json.loads(request.data), {"user_id": "agent", "role": "user"})

    def test_service_commands_are_user_scoped_on_both_platforms(self):
        self.init()
        binary = self.ctl.runtime() / "bin/openviking-server"
        binary.parent.mkdir(parents=True)
        binary.touch()
        with patch.object(self.ctl.platform, "system", return_value="Linux"):
            with patch.object(self.ctl, "command") as command:
                self.ctl.service("enable")
                self.assertEqual(command.call_args.args[0], ["systemctl", "--user", "enable", "--now", self.ctl.UNIT])
        with patch.object(self.ctl.platform, "system", return_value="Darwin"):
            with patch.object(self.ctl, "command") as command:
                self.ctl.service("enable")
                self.assertEqual(command.call_args.args[0][:3], ["launchctl", "bootstrap", "gui/" + str(os.getuid())])

    def test_native_mcp_fragment_uses_a_private_file_reference_not_a_key(self):
        self.init()
        path = self.ctl.PRIVATE / "ovcli.conf"
        client = self.ctl.private_json(path)
        client["api_key"] = "fixture-user-key"
        self.ctl.write_private(path, client, replace=True)
        fragment = self.ctl.mcp_config()
        text = json.dumps(fragment)
        key_file = self.ctl.PRIVATE / "mcp-user-key"
        self.assertEqual(key_file.read_text(), "fixture-user-key\n")
        self.assertEqual(key_file.stat().st_mode & 0o777, 0o600)
        self.assertNotIn("fixture-user-key", text)
        server = fragment["mcp"]["servers"]["openviking"]
        self.assertFalse(server["oauth"])
        self.assertFalse(server["codemode"])
        self.assertEqual(server["url"], "http://127.0.0.1:1933/mcp")

    def test_native_mcp_refuses_the_incompatible_default_registration_mode(self):
        self.init()
        path = self.ctl.PRIVATE / "ovcli.conf"
        client = self.ctl.private_json(path)
        client["plugin"]["opencode"]["mcpEnabled"] = True
        self.ctl.write_private(path, client, replace=True)
        with self.assertRaisesRegex(ValueError, "mcpEnabled=false"):
            self.ctl.mcp_config()

    def test_registration_check_rejects_missing_skills_without_printing_private_payloads(self):
        self.init()
        responses = [
            {"data": [{"source": {"type": "package", "target": "@openviking/opencode-plugin@2026.10.7"}, "state": {"status": "active"}}]},
            {"data": [{"name": "openviking", "status": {"status": "connected"}}]},
            {"data": [{"id": "openviking-memory", "content": "fixture private body"}]},
        ]
        with patch.object(self.ctl.subprocess, "run") as run:
            pending = iter(responses)

            def reply(*args, **kwargs):
                json.dump(next(pending), kwargs["stdout"])
                kwargs["stdout"].flush()
                return subprocess.CompletedProcess([], 0)

            run.side_effect = reply
            with contextlib.redirect_stdout(io.StringIO()) as out:
                with self.assertRaisesRegex(ValueError, "registration check failed"):
                    self.ctl.check_opencode()
        self.assertNotIn("fixture private body", out.getvalue())

    def test_registration_check_accepts_active_hooks_native_mcp_and_three_skills(self):
        self.init()
        responses = [
            {"data": [{"source": {"type": "package", "target": "@openviking/opencode-plugin@2026.10.7"}, "state": {"status": "active"}}]},
            {"data": [{"name": "openviking", "status": {"status": "connected"}}]},
            {"data": [{"id": name, "content": "fixture private body " * 20000} for name in ("openviking-memory", "openviking-skills", "ov-experience-memory")]},
        ]
        with patch.object(self.ctl.subprocess, "run") as run:
            pending = iter(responses)

            def reply(*args, **kwargs):
                json.dump(next(pending), kwargs["stdout"])
                kwargs["stdout"].flush()
                return subprocess.CompletedProcess([], 0)

            run.side_effect = reply
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.ctl.check_opencode()
        self.assertEqual(json.loads(out.getvalue())["missing_skills"], [])

    def test_registration_check_does_not_treat_connected_mcp_as_active_capture(self):
        self.init()
        responses = iter([
            {"data": [{"source": {"type": "package", "target": "@openviking/opencode-plugin@2026.10.7"}, "state": {"status": "failed"}}]},
            {"data": [{"name": "openviking", "status": {"status": "connected"}}]},
            {"data": [{"id": name} for name in ("openviking-memory", "openviking-skills", "ov-experience-memory")]},
        ])

        def reply(*args, **kwargs):
            json.dump(next(responses), kwargs["stdout"])
            kwargs["stdout"].flush()
            return subprocess.CompletedProcess([], 0)

        with patch.object(self.ctl.subprocess, "run", side_effect=reply):
            with contextlib.redirect_stdout(io.StringIO()) as out:
                with self.assertRaisesRegex(ValueError, "registration check failed"):
                    self.ctl.check_opencode()
        result = json.loads(out.getvalue())
        self.assertFalse(result["plugin_active"])
        self.assertTrue(result["mcp_connected"])

    def test_registration_check_does_not_load_server_environment(self):
        with patch.object(self.ctl.sys, "argv", ["openvikingctl", "check-opencode"]):
            with patch.object(self.ctl, "load_environment") as environment:
                with patch.object(self.ctl, "check_opencode") as check:
                    self.ctl.main()
        environment.assert_not_called()
        check.assert_called_once_with()

    def test_run_enforces_loopback_and_private_working_directory(self):
        self.init()
        with patch.object(self.ctl.os, "execv") as execute:
            with patch.object(self.ctl.os, "chdir") as chdir:
                with patch.object(self.ctl.sys, "argv", ["openvikingctl", "run"]):
                    self.ctl.main()
        chdir.assert_called_once_with(self.ctl.PRIVATE)
        args = execute.call_args.args[1]
        self.assertEqual(args[-4:], ["--host", "127.0.0.1", "--port", "1933"])


class OpenVikingRenderTest(unittest.TestCase):
    def render(self, relative, features, os_name="darwin"):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.toml"
            config.write_text('[data]\ncomponentSelection="5"\naiSelection="' + features + '"\npalette="dracula"\n[data.components.ai]\n' + '\n'.join(name + '=true' for name in features.split()) + '\n')
            result = subprocess.run(["chezmoi", "execute-template", "--source", str(REPO), "--config", str(config), "--override-data", json.dumps({"chezmoi": {"os": os_name, "homeDir": "/home/example"}})], input=(REPO / relative).read_text(), text=True, capture_output=True, check=True)
            return result.stdout

    def test_init_picker_has_an_independent_opt_in_without_reusing_legacy_seven(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.toml"
            for selection, wanted in (("openviking", True), ("8", True), ("opencode", False), ("7", False)):
                config.write_text('[data]\ncomponentSelection="5"\naiSelection="' + selection + '"\npalette="dracula"\n')
                result = subprocess.run(["chezmoi", "execute-template", "--init", "--source", str(REPO), "--config", str(config)], input=(REPO / "home/.chezmoi.toml.tmpl").read_text(), text=True, capture_output=True, check=True, env=dict(os.environ, DOTFILES_NO_TUI="1", DOTFILES_INSTALL_MODE="configs"))
                import tomllib
                features = tomllib.loads(result.stdout)["data"]["components"]["ai"]
                self.assertEqual(features["openviking"], wanted)
                if wanted:
                    self.assertFalse(features["opencode"])

    def test_macos_service_is_valid_plist_and_contains_no_credentials(self):
        rendered = self.render("home/Library/LaunchAgents/io.github.crag-h4k.dotfiles.openviking.plist.tmpl", "openviking")
        service = plistlib.loads(rendered.encode())
        self.assertEqual(service["ProgramArguments"][-1], "run")
        self.assertEqual(service["Umask"], 63)
        self.assertTrue(service["Disabled"])
        self.assertNotIn("api_key", rendered)

    def test_file_gates_keep_private_state_ignored_on_both_platforms(self):
        for os_name in ("darwin", "linux"):
            for selected in ("", "openviking"):
                with self.subTest(os_name=os_name, selected=selected):
                    rendered = self.render("home/.chezmoiignore", selected, os_name)
                    lines = rendered.splitlines()
                    self.assertIn(".openviking", lines)
                    self.assertEqual(".local/bin/openvikingctl" in lines, not bool(selected))
                    self.assertEqual("Library/LaunchAgents/io.github.crag-h4k.dotfiles.openviking.plist" in lines,
                                     os_name != "darwin" or not selected)
                    self.assertEqual(".config/systemd/user/dotfiles-openviking.service" in lines,
                                     os_name != "linux" or not selected)

    def test_plugin_registration_is_selected_and_retired_without_dropping_local_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "merge.py"
            script.write_text(self.render("home/dot_config/opencode/modify_opencode.jsonc.tmpl", "openviking opencode"))
            first = subprocess.run([os.sys.executable, str(script)], input='{\n  "plugins": ["local-plugin"]\n}\n', text=True, capture_output=True, check=True).stdout
            self.assertIn('"@openviking/opencode-plugin@2026.10.7"', first)
            script.write_text(self.render("home/dot_config/opencode/modify_opencode.jsonc.tmpl", "opencode"))
            second = subprocess.run([os.sys.executable, str(script)], input=first, text=True, capture_output=True, check=True).stdout
            self.assertNotIn('"@openviking/opencode-plugin@2026.10.7"', second)
            self.assertIn('"local-plugin"', second)


class OpenVikingBenchmarkTest(unittest.TestCase):
    def setUp(self):
        self.bench = load_module("openviking_benchmark", REPO / "scripts/benchmark-openviking.py")

    def test_first_failure_is_not_relabelled_as_a_successful_cold_request(self):
        error = urllib.error.HTTPError("http://127.0.0.1:1933", 503, "fixture", {}, None)
        response = io.BytesIO(b'{"result": {"abstract": "fixture marker"}}')
        with patch.object(self.bench.urllib.request, "build_opener") as builder:
            builder.return_value.open.side_effect = [error, response]
            result = self.bench.measure({"url": "http://127.0.0.1:1933", "api_key": "fixture"},
                                        [{"query": "fixture query", "expected": "fixture marker"}], 2, 1)
        error.close()
        self.assertIsNone(result["first_request_ms"])
        self.assertIsNotNone(result["warm_p50_ms"])
        self.assertEqual(result["expected_marker_hit_rate"], 0.5)
        self.assertIsNone(result["samples"][0]["server_ms"])
        self.assertNotIn("fixture query", json.dumps(result))
        self.assertNotIn("fixture marker", json.dumps(result))

    def test_remote_plaintext_and_url_credentials_are_rejected(self):
        for url in ("http://example.invalid", "https://user:password@example.invalid", "http://127.0.0.1:1933?key=fixture"):
            with self.subTest(url=url):
                with self.assertRaises(ValueError):
                    self.bench.measure({"url": url, "api_key": "fixture"}, [], 1, 1)


class OpenVikingInstallerTest(unittest.TestCase):
    def test_disabled_component_has_no_package_or_filesystem_side_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "home"
            home.mkdir()
            subprocess.run(["/bin/bash", str(REPO / "scripts/install-openviking.sh")],
                           env=dict(os.environ, HOME=str(home), INSTALL_AI_OPENVIKING="false"),
                           capture_output=True, check=True)
            self.assertEqual(list(home.iterdir()), [])

    def test_unavailable_installer_preserves_an_existing_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            runtime = root / "runtime"
            previous = runtime / "previous"
            previous.mkdir(parents=True)
            (runtime / "current").symlink_to(previous)
            tools = root / "tools"
            tools.mkdir()
            (tools / "uv").write_text('#!/bin/sh\nexit 1\n')
            (tools / "uv").chmod(0o755)
            result = subprocess.run(["/bin/bash", str(REPO / "scripts/install-openviking.sh")],
                                    env=dict(os.environ, HOME=str(home), PATH=str(tools) + ':' + os.environ['PATH'],
                                             INSTALL_AI_OPENVIKING="true", OPENVIKING_INSTALL_ROOT=str(runtime)),
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((runtime / "current").resolve(), previous.resolve())
            self.assertFalse((home / ".openviking/runtime.json").exists())


if __name__ == "__main__":
    unittest.main()
