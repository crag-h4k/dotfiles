"""Codex snapshot validation and interrupted replay recovery; no live service calls."""
import asyncio
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

from tests.test_openviking import ASSETS, CONTROLLER, load_module

IMPORTER = ASSETS / "readonly_codex_import.py"
HAS_RUNTIME = importlib.util.find_spec("openviking") is not None


class ImportFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.importer = load_module("codex_import", IMPORTER)
        self.umask = os.umask(0o077)

    def tearDown(self):
        os.umask(self.umask)
        self.temp.cleanup()


class ImportTest(ImportFixture):
    def test_private_state_writes_are_atomic_and_restrictive(self):
        path = self.root / "state.json"
        self.importer.save(path, {"complete": False})
        self.importer.save(path, {"complete": True})
        self.assertEqual(self.importer.read_private(path), {"complete": True})
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.root.iterdir()), [path])

    def test_configuration_override_preserves_file_and_never_stores_key(self):
        path = self.root / "client.json"
        original = {"url": "http://container:1933", "api_key": "fixture-secret", "plugin": {"autoCapture": True}}
        self.importer.save(path, original)
        values, binding = self.importer.target_config(path, "http://127.0.0.1:1933")
        self.assertEqual(values["url"], "http://127.0.0.1:1933")
        self.assertNotIn("fixture-secret", json.dumps(binding))
        self.assertEqual(json.loads(path.read_text()), original)

    def test_refuses_shared_client_file_and_nonprivate_http(self):
        path = self.root / "client.json"
        self.importer.save(path, {"url": "http://example.test", "api_key": "fixture"})
        with self.assertRaisesRegex(ValueError, "HTTPS"):
            self.importer.target_config(path)
        path.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "private"):
            self.importer.target_config(path, "http://localhost:1933")

    def test_partial_and_malformed_rollouts_fail_before_replay(self):
        path = self.root / "rollout.jsonl"
        for text in ('{"type":"session_meta"}', '{broken}\n', '[]\n'):
            path.write_text(text)
            with self.assertRaises(ValueError):
                self.importer.validate_rollout(path)

    def test_completed_task_with_skipped_memory_operations_is_not_success(self):
        client = AsyncMock()
        client.get_task.return_value = {"status": "completed", "result": {"memory_extraction": {"skipped": 1}}}
        with self.assertRaisesRegex(ValueError, "skipped"):
            asyncio.run(self.importer.wait_for_task(client, "task", 1))

    def test_failed_task_keeps_commit_id_for_inspection(self):
        client = AsyncMock()
        client.list_tasks.return_value = []
        client.commit_session.return_value = {"task_id": "task"}
        client.get_task.return_value = {"status": "failed", "task_type": "session_commit", "resource_id": "session"}
        record = {}
        with self.assertRaisesRegex(ValueError, "failed"):
            asyncio.run(self.importer.finish_commit(client, "session", record, lambda: None, 10))
        self.assertEqual(record["task_id"], "task")
        self.assertNotIn("complete", record)

    def test_timeout_resumes_waiting_without_resubmitting_commit(self):
        client = AsyncMock()
        client.list_tasks.return_value = []
        client.commit_session.return_value = {"task_id": "task"}
        client.get_task.return_value = {"status": "running", "task_type": "session_commit", "resource_id": "session"}
        record = {}
        with patch.object(self.importer, "time") as clock:
            clock.time.return_value = 1
            clock.monotonic.side_effect = [0, 2]
            with self.assertRaises(TimeoutError):
                asyncio.run(self.importer.finish_commit(client, "session", record, lambda: None, 1))
        client.get_task.return_value = {"status": "completed", "task_type": "session_commit", "resource_id": "session", "result": {"memories_extracted": 2}}
        asyncio.run(self.importer.finish_commit(client, "session", record, lambda: None, 1))
        client.commit_session.assert_awaited_once()
        self.assertEqual(record["memories_extracted"], 2)

    def test_lost_commit_response_recovers_by_task_identity(self):
        client = AsyncMock()
        client.list_tasks.return_value = [{"task_id": "new"}, {"task_id": "old"}]
        client.get_task.return_value = {"status": "completed", "task_type": "session_commit", "resource_id": "session"}
        record = {"commit_started": 1, "previous_tasks": ["old"]}
        asyncio.run(self.importer.finish_commit(client, "session", record, lambda: None, 1))
        client.commit_session.assert_not_awaited()
        self.assertEqual(record["task_id"], "new")

    def test_uncertain_commit_does_not_blindly_recommit(self):
        client = AsyncMock()
        client.list_tasks.return_value = []
        with self.assertRaisesRegex(ValueError, "reply was lost"):
            asyncio.run(self.importer.finish_commit(client, "session", {"commit_started": 1, "previous_tasks": []}, lambda: None, 1))
        client.commit_session.assert_not_awaited()

    def test_unrelated_completed_task_cannot_verify_an_import(self):
        client = AsyncMock()
        client.get_task.return_value = {"status": "completed", "task_type": "session_commit", "resource_id": "other-session"}
        record = {"commit_started": 1, "task_id": "wrong-task"}
        with self.assertRaisesRegex(ValueError, "does not match"):
            asyncio.run(self.importer.finish_commit(client, "session", record, lambda: None, 1))
        self.assertNotIn("memories_extracted", record)
        client.commit_session.assert_not_awaited()

    def test_selected_config_rejects_identity_overriding_headers(self):
        path = self.root / "client.json"
        for fields in ({"extra_headers": {"X-API-Key": "other-fixture"}},
                       {"extra_header": {"Authorization": "other-fixture"}},
                       {"gateway_token": "other-fixture"}, {"auth_mode": "oidc"}):
            self.importer.save(path, {"url": "http://localhost:1933", "api_key": "fixture", **fields})
            with self.assertRaisesRegex(ValueError, "dedicated API-key"):
                self.importer.target_config(path)

    def test_controller_propagates_failure_without_echoing_arguments(self):
        ctl = load_module("openvikingctl_failure", CONTROLLER)
        secret = "synthetic-placeholder"
        argv = [str(CONTROLLER), "import-codex", "--url", "https" + "://fixture:" + secret + "@example.invalid"]
        for returncode, expected in ((23, 23), (-2, 130)):
            with patch.object(ctl, "load_environment"), patch.object(ctl, "runtime", return_value=self.root / "runtime"), patch.object(ctl, "command") as command:
                command.return_value = subprocess.CompletedProcess(argv, returncode)
                with patch.object(sys, "argv", argv), contextlib.redirect_stderr(io.StringIO()) as output:
                    with self.assertRaises(SystemExit) as error:
                        ctl.main()
                self.assertEqual(error.exception.code, expected)
                self.assertNotIn(secret, output.getvalue())
                self.assertFalse(command.call_args.kwargs["check"])


@unittest.skipUnless(HAS_RUNTIME, "run with the installed OpenViking Python for native adapter/replay coverage")
class NativeImportTest(ImportFixture):
    def setUp(self):
        super().setUp()
        from openviking.ingest.cursor_store import CursorStore
        from openviking_cli.exceptions import NotFoundError

        self.source_dir = self.root / "sessions"
        self.path = self.source_dir / "2026/01/01/rollout-example.jsonl"
        self.path.parent.mkdir(parents=True)
        records = [{"type": "session_meta", "payload": {"id": "example", "timestamp": "2026-01-01T00:00:00Z", "cwd": "/nonexistent/source-host"}}]
        for role in ("user", "assistant", "developer", "system"):
            records.append({"type": "response_item", "payload": {"type": "message", "role": role, "content": [{"type": "input_text", "text": role + " text"}]}})
        records.append({"type": "response_item", "payload": {"type": "function_call_output", "output": "tool secret"}})
        records.append({"type": "response_item", "payload": {"type": "reasoning", "encrypted_content": "opaque"}})
        self.path.write_text("".join(json.dumps(r) + "\n" for r in records))
        self.source = self.importer.source_for(self.source_dir)
        self.state = {"files": {}}
        self.store = CursorStore(self.root / "state")
        self.client = AsyncMock()
        self.server_info = {"message_count": 0, "auto_commit_policy": None}
        self.client.get_session.side_effect = NotFoundError("missing")
        async def create(**kwargs):
            self.client.get_session.side_effect = None
            self.client.get_session.return_value = self.server_info
            return {}
        self.client.create_session.side_effect = create
        async def append(sid, messages):
            self.server_info["message_count"] += len(messages)
            return {"added": len(messages)}
        self.client.batch_add_messages.side_effect = append
        self.client.list_tasks.return_value = []
        self.client.commit_session.return_value = {"task_id": "task"}
        self.client.get_task.return_value = {"status": "completed", "task_type": "session_commit",
                                             "resource_id": "fixture__codex__example", "result": {"memories_extracted": 1}}
        self.progress = self.root / "progress.json"

    def tearDown(self):
        self.store.close()
        super().tearDown()

    def run_replay(self, **selection):
        selected, _ = self.importer.inventory(self.source, self.state, **selection)
        with contextlib.redirect_stdout(io.StringIO()):
            asyncio.run(self.importer.replay(self.source, selected, self.state,
                                            lambda: self.importer.save(self.progress, self.state),
                                            self.store, self.client, "fixture", 1))

    def test_native_parser_retains_only_conversation_and_does_not_resolve_local_git(self):
        ref = next(self.source.discover_sessions())
        messages, _ = self.source.read_messages(ref, None)
        self.assertEqual([m.role for m in messages], ["user", "assistant"])
        self.assertEqual([m.text for m in messages], ["user text", "assistant text"])
        self.assertIsNone(messages[0].peer_id)
        self.assertEqual(self.importer.count_messages(self.source, ref), (2, 23))

    def test_preview_needs_no_client_or_state_and_writes_nothing(self):
        with patch.object(self.importer.Path, "home", return_value=self.root):
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.importer.main(["--source", str(self.source_dir), "--name", "test"])
        self.assertEqual(json.loads(out.getvalue())["messages"], 2)
        self.assertFalse((self.root / ".openviking").exists())

    def test_success_and_rerun_append_once_and_disable_automatic_commits(self):
        self.run_replay()
        self.assertTrue(self.state["files"]["example"]["complete"])
        self.assertEqual(self.client.create_session.call_args.kwargs["options"], {"auto_commit_policy": None})
        self.run_replay()
        self.client.batch_add_messages.assert_awaited_once()
        self.client.commit_session.assert_awaited_once()

    def test_replaced_identical_snapshot_resumes_without_duplicate_append(self):
        self.client.commit_session.side_effect = RuntimeError("connection lost")
        with self.assertRaises(RuntimeError):
            self.run_replay()
        record = self.state["files"]["example"]
        # Simulate a crash before commit submission, after a confirmed append.
        record.pop("commit_started")
        new = self.path.with_suffix(".copy")
        new.write_bytes(self.path.read_bytes())
        new.replace(self.path)
        self.client.get_session.side_effect = None
        self.server_info["message_count"] = 2
        self.client.get_session.return_value = self.server_info
        self.client.commit_session.side_effect = None
        self.run_replay()
        self.client.batch_add_messages.assert_awaited_once()
        self.assertTrue(record["complete"])

    def test_modified_snapshot_is_rejected_even_after_completion(self):
        self.run_replay()
        self.path.write_text(self.path.read_text() + '{}\n')
        with self.assertRaisesRegex(ValueError, "snapshot changed"):
            self.run_replay()

    def test_lost_append_reply_is_reconciled_before_retry(self):
        self.client.batch_add_messages.side_effect = RuntimeError("response lost")
        with self.assertRaises(RuntimeError):
            self.run_replay()
        self.client.get_session.side_effect = None
        self.server_info["message_count"] = 2
        self.client.get_session.return_value = self.server_info
        self.client.batch_add_messages.side_effect = None
        self.run_replay()
        self.client.batch_add_messages.assert_awaited_once()
        self.assertTrue(self.state["files"]["example"]["complete"])

    def test_existing_server_session_without_manifest_is_refused(self):
        self.client.get_session.side_effect = None
        self.client.get_session.return_value = {"message_count": 2}
        with self.assertRaisesRegex(ValueError, "without local state"):
            self.run_replay()
        self.client.batch_add_messages.assert_not_awaited()

    def test_explicit_selection_reports_completed_pilot_and_refuses_unknown_ids(self):
        self.run_replay()
        selected, complete = self.importer.inventory(self.source, self.state, sessions=["example"])
        self.assertEqual((selected, complete), ([], 1))
        with self.assertRaisesRegex(ValueError, "absent"):
            self.importer.inventory(self.source, self.state, sessions=["missing"])

    def second_rollout(self):
        path = self.path.with_name("rollout-other.jsonl")
        path.write_text(self.path.read_text().replace('"id": "example"', '"id": "other"'))
        return path

    def test_pilot_binds_unprocessed_files_before_first_append(self):
        second = self.second_rollout()
        self.run_replay(limit=1)
        self.assertEqual(set(self.state["snapshot"]), {"example", "other"})
        self.assertEqual(set(json.loads(self.progress.read_text())["snapshot"]), {"example", "other"})
        second.write_text(second.read_text() + '{}\n')
        with self.assertRaisesRegex(ValueError, "snapshot changed"):
            self.run_replay()
        self.client.batch_add_messages.assert_awaited_once()

    def test_removing_an_imported_file_is_detected_with_other_files_present(self):
        self.second_rollout()
        self.run_replay(limit=1)
        self.path.unlink()
        with self.assertRaisesRegex(ValueError, "lost files"):
            self.run_replay()

    def test_adding_files_after_a_pilot_is_rejected(self):
        self.run_replay()
        self.second_rollout()
        with self.assertRaisesRegex(ValueError, "added"):
            self.run_replay()

    def test_filter_does_not_hide_changes_to_unselected_files(self):
        second = self.second_rollout()
        self.run_replay(sessions=["example"])
        second.write_text(second.read_text() + '{}\n')
        with self.assertRaisesRegex(ValueError, "snapshot changed"):
            self.importer.inventory(self.source, self.state, sessions=["example"])

    def test_partial_pending_append_is_not_reconciled_or_replayed(self):
        async def partial(sid, messages):
            self.server_info["message_count"] = 1
            raise RuntimeError("synthetic lost reply")
        self.client.batch_add_messages.side_effect = partial
        with self.assertRaises(RuntimeError):
            self.run_replay()
        with self.assertRaisesRegex(ValueError, "marked invalid"):
            self.run_replay()
        self.assertEqual(self.store.get("codex", "example").pending_count, 2)
        self.assertEqual(json.loads(self.progress.read_text())["invalid"]["reason"], "server_count_mismatch")
        self.client.batch_add_messages.assert_awaited_once()
        self.client.commit_session.assert_not_awaited()

    def test_extra_server_messages_are_not_treated_as_a_landed_batch(self):
        async def extra(sid, messages):
            self.server_info["message_count"] = 3
            raise RuntimeError("synthetic unexpected server append")
        self.client.batch_add_messages.side_effect = extra
        with self.assertRaises(RuntimeError):
            self.run_replay()
        with self.assertRaisesRegex(ValueError, "marked invalid"):
            self.run_replay()
        self.assertEqual(self.store.get("codex", "example").pending_count, 2)
        self.client.batch_add_messages.assert_awaited_once()
        self.client.commit_session.assert_not_awaited()

    def test_confirmed_cursor_with_a_reset_server_is_not_silently_committed(self):
        self.client.list_tasks.side_effect = RuntimeError("synthetic pre-commit interruption")
        with self.assertRaises(RuntimeError):
            self.run_replay()
        self.assertNotIn("commit_started", self.state["files"]["example"])
        self.server_info["message_count"] = 0
        self.client.list_tasks.side_effect = None
        with self.assertRaisesRegex(ValueError, "marked invalid"):
            self.run_replay()
        self.client.batch_add_messages.assert_awaited_once()
        self.client.commit_session.assert_not_awaited()

    def test_pending_append_that_did_not_land_is_retried_once(self):
        normal = self.client.batch_add_messages.side_effect
        self.client.batch_add_messages.side_effect = RuntimeError("synthetic no append")
        with self.assertRaises(RuntimeError):
            self.run_replay()
        self.client.batch_add_messages.side_effect = normal
        self.run_replay()
        self.assertEqual(self.client.batch_add_messages.await_count, 2)
        self.assertEqual(self.server_info["message_count"], 2)
        self.assertTrue(self.state["files"]["example"]["complete"])

    def test_out_of_bounds_cursor_does_not_restart_from_zero(self):
        from openviking.ingest.models import Cursor
        self.client.list_tasks.side_effect = RuntimeError("synthetic pre-commit interruption")
        with self.assertRaises(RuntimeError):
            self.run_replay()
        self.store.advance_cursor("codex", "example", "fixture__codex__example",
                                  Cursor(self.source.cursor_kind,
                                         {"offset": self.path.stat().st_size + 1, "inode": self.path.stat().st_ino}))
        with self.assertRaisesRegex(ValueError, "marked invalid"):
            self.run_replay()
        self.assertEqual(self.state["invalid"]["reason"], "cursor_out_of_bounds")
        self.client.batch_add_messages.assert_awaited_once()

    def test_source_mutation_persists_invalid_state_even_if_original_is_restored(self):
        original = self.path.read_bytes()
        normal = self.client.batch_add_messages.side_effect
        async def mutate(sid, messages):
            result = await normal(sid, messages)
            self.path.write_bytes(original + b'{}\n')
            return result
        self.client.batch_add_messages.side_effect = mutate
        with self.assertRaisesRegex(ValueError, "marked invalid"):
            self.run_replay()
        self.path.write_bytes(original)
        recovered = json.loads(self.progress.read_text())
        self.assertEqual(recovered["invalid"]["reason"], "source_changed")
        with self.assertRaisesRegex(ValueError, "state is invalid"):
            self.importer.inventory(self.source, recovered)
        self.client.batch_add_messages.assert_awaited_once()
        self.client.commit_session.assert_not_awaited()

    def test_mutating_and_restoring_during_append_still_invalidates_progress(self):
        original = self.path.read_bytes()
        normal = self.client.batch_add_messages.side_effect
        async def mutate(sid, messages):
            result = await normal(sid, messages)
            self.path.write_bytes(original + b'{}\n')
            self.path.write_bytes(original)
            return result
        self.client.batch_add_messages.side_effect = mutate
        with self.assertRaisesRegex(ValueError, "marked invalid"):
            self.run_replay()
        self.assertEqual(json.loads(self.progress.read_text())["invalid"]["reason"], "source_changed")
        self.client.commit_session.assert_not_awaited()

    def test_legacy_partial_progress_requires_explicit_recovery(self):
        self.run_replay()
        self.state.pop("snapshot")
        with self.assertRaisesRegex(ValueError, "legacy progress"):
            self.importer.inventory(self.source, self.state)

    def test_missing_cursor_row_cannot_turn_failed_extraction_into_empty_completion(self):
        self.client.get_task.return_value = {"status": "failed", "task_type": "session_commit", "resource_id": "fixture__codex__example"}
        with self.assertRaisesRegex(ValueError, "extraction failed"):
            self.run_replay()
        self.store.delete("codex", "example")
        with self.assertRaisesRegex(ValueError, "marked invalid"):
            self.run_replay()
        saved = json.loads(self.progress.read_text())
        self.assertEqual(saved["invalid"]["reason"], "committed_cursor_mismatch")
        self.assertFalse(saved["files"]["example"]["complete"])
        self.assertNotIn("messages", saved["files"]["example"])
        self.client.get_task.assert_awaited_once()
        self.client.batch_add_messages.assert_awaited_once()

    def test_older_cursor_row_cannot_complete_a_newer_commit(self):
        from openviking.ingest.models import Cursor
        self.client.get_task.return_value = {"status": "failed", "task_type": "session_commit", "resource_id": "fixture__codex__example"}
        with self.assertRaisesRegex(ValueError, "extraction failed"):
            self.run_replay()
        ref = next(self.source.discover_sessions())
        messages, cursor = self.source.read_messages(ref, None, limit=1)
        self.store.delete("codex", "example")
        self.store.set_pending("codex", "example", "fixture__codex__example",
                               Cursor.zero(self.source.cursor_kind), cursor, len(messages), 0)
        self.store.confirm_append("codex", "example", cursor, len(messages))
        with self.assertRaisesRegex(ValueError, "marked invalid"):
            self.run_replay()
        self.assertFalse(self.state["files"]["example"]["complete"])
        self.client.get_task.assert_awaited_once()
        self.client.commit_session.assert_awaited_once()

    def test_valid_committed_cursor_resumes_waiting_without_repeating_work(self):
        self.client.get_task.return_value = {"status": "running", "task_type": "session_commit", "resource_id": "fixture__codex__example"}
        with patch.object(self.importer, "time") as clock:
            clock.time.return_value = 1
            clock.monotonic.side_effect = [0, 2]
            with self.assertRaises(TimeoutError):
                self.run_replay()
        self.client.get_task.return_value = {"status": "completed", "task_type": "session_commit",
                                             "resource_id": "fixture__codex__example", "result": {"memories_extracted": 1}}
        self.run_replay()
        self.assertTrue(self.state["files"]["example"]["complete"])
        self.assertEqual(self.state["files"]["example"]["messages"], 2)
        self.client.batch_add_messages.assert_awaited_once()
        self.client.commit_session.assert_awaited_once()

    def test_apply_persists_the_complete_manifest_before_the_pilot_append(self):
        self.second_rollout()
        self.client.get_task.return_value["resource_id"] = "codex-fixture__codex__example"
        config = self.root / "selected.json"
        self.importer.save(config, {"url": "http://localhost:1933", "api_key": "fixture"})
        progress = self.root / "applied-state/progress.json"
        normal = self.client.batch_add_messages.side_effect
        async def check_manifest(sid, messages):
            saved = json.loads(progress.read_text())
            self.assertEqual(set(saved["snapshot"]), {"example", "other"})
            return await normal(sid, messages)
        self.client.batch_add_messages.side_effect = check_manifest
        args = SimpleNamespace(source=self.source_dir, client_config=config, url=None,
                               since=None, limit=1, session=None, name="fixture", wait_timeout=1)
        with patch.object(self.importer, "create_client", return_value=self.client):
            with contextlib.redirect_stdout(io.StringIO()):
                asyncio.run(self.importer.apply(self.source, args, progress))
        self.client.batch_add_messages.assert_awaited_once()
        self.assertEqual(set(json.loads(progress.read_text())["files"]), {"example"})

    def test_selected_sdk_client_ignores_unrelated_config_and_environment(self):
        import httpx
        import openviking_sdk.config as sdk_config
        selected = self.root / "selected.json"
        unrelated = self.root / "unrelated.json"
        self.importer.save(selected, {"url": "https://example.invalid", "api_key": "fixture-selected"})
        self.importer.save(unrelated, {"url": "https://example.invalid", "api_key": "fixture-default",
                                     "extra_headers": {"X-API-Key": "fixture-overridden"},
                                     "gateway_token": "fixture-gateway", "auth_mode": "ldap",
                                     "ldap_username": "fixture-user", "ldap_password": "fixture-password"})
        env = {"OPENVIKING_CLI_CONFIG_FILE": str(unrelated), "OPENVIKING_ACCOUNT": "wrong-account",
               "OPENVIKING_USER": "wrong-user", "OPENVIKING_ACTOR_PEER_ID": "wrong-peer",
               "OPENVIKING_API_KEY": "fixture-environment", "OPENVIKING_AUTH_MODE": "ldap"}
        requests = []
        def respond(request):
            requests.append(request)
            return httpx.Response(200, json={"status": "ok", "result": {"message_count": 0}})
        original_client = httpx.AsyncClient
        def fake_http(**kwargs):
            return original_client(**kwargs, transport=httpx.MockTransport(respond))
        async def probe(client):
            await client.initialize()
            try:
                await client.get_session("fixture")
            finally:
                await client.close()
        with patch.dict(os.environ, env), patch.object(sdk_config, "DEFAULT_OVCLI_CONF", unrelated):
            values, binding = self.importer.target_config(selected)
            before = dict(os.environ)
            with patch("openviking_sdk.client.httpx.AsyncClient", side_effect=fake_http):
                client = self.importer.create_client(values)
                self.assertEqual(dict(os.environ), before)
                asyncio.run(probe(client))
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0].headers["X-API-Key"], "fixture-selected")
        for name in ("Authorization", "X-OpenViking-Account", "X-OpenViking-User",
                     "X-OpenViking-Actor-Peer", "X-OpenViking-Gateway-Token"):
            self.assertNotIn(name, requests[0].headers)
        self.assertIsNone(binding["account"])
        self.assertIsNone(binding["user"])

    def test_rejected_url_does_not_leak_through_the_real_controller(self):
        runtime = self.root / "runtime/current/bin"
        runtime.mkdir(parents=True)
        launcher = runtime / "python"
        launcher.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + ' "$@"\n')
        launcher.chmod(0o700)
        assets = self.root / ".local/share/dotfiles/openviking"
        assets.mkdir(parents=True)
        shutil.copyfile(IMPORTER, assets / "codex_import.py")
        client = self.root / ".openviking/ovcli.conf"
        client.parent.mkdir(mode=0o700)
        self.importer.save(client, {"url": "http://127.0.0.1:1933", "api_key": "fixture"})
        secret = "synthetic-placeholder"
        url = "https" + "://fixture:" + secret + "@example.invalid"
        env = dict(os.environ, HOME=str(self.root), OPENVIKING_INSTALL_ROOT=str(self.root / "runtime"))
        result = subprocess.run([sys.executable, str(CONTROLLER), "import-codex", "--source", str(self.source_dir),
                                 "--name", "fixture", "--url", url, "--apply"],
                                env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1)
        self.assertIn("client URL must", result.stderr)
        self.assertNotIn(secret, result.stderr)
        self.assertNotIn(url, result.stderr)


if __name__ == "__main__":
    unittest.main()
