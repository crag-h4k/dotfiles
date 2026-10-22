"""File-memory import and OpenCode 2 export: planning, symlinks, approval gates; no live service calls."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import AsyncMock, patch

from tests.test_openviking import ASSETS, load_module

MODULE = ASSETS / "readonly_memory_sources.py"
HAS_RUNTIME = importlib.util.find_spec("openviking") is not None


try:
    from openviking_cli.exceptions import NotFoundError
    REAL_EXCEPTIONS = True
except ImportError:
    REAL_EXCEPTIONS = False

    class NotFoundError(Exception):
        pass


class FakeClient:
    """Just enough of the OpenViking client for planning, writing, and read-back."""

    def __init__(self, files=None, sessions=(), modified="2026-01-01T00:00:00Z", corrupt=()):
        self.files = dict(files or {})
        self.sessions = set(sessions)
        self.modified = modified
        self.corrupt = set(corrupt)
        self.writes = []
        self.made = []

    async def ls(self, uri, simple=False, recursive=False, node_limit=0):
        return ["viking://user/agent/memories/" + rel for rel in sorted(self.files)]

    async def read(self, uri):
        rel = uri.split("/memories/", 1)[1]
        if rel not in self.files:
            raise NotFoundError(rel)
        return self.files[rel] + "\n\n<!-- MEMORY_FIELDS\n{\n  \"version\": 1\n}\n-->\n"

    async def stat(self, uri):
        return {"modTime": self.modified}

    async def write(self, uri, content, mode="replace", wait=False):
        rel = uri.split("/memories/", 1)[1] if "/memories/" in uri else uri.split("~/memories/", 1)[1]
        self.writes.append(rel)
        self.files[rel] = "tampered\n" if rel.rsplit("/", 1)[-1] in self.corrupt else content

    async def mkdir(self, uri):
        self.made.append(uri)

    async def wait_processed(self):
        return {}

    async def get_session(self, session):
        if session not in self.sessions:
            raise NotFoundError(session)
        return {}

    async def close(self):
        return None


def memory(kind, body="Body.\n", name=None):
    return "---\nname: " + (name or kind) + "\ndescription: fixture\ntype: " + kind + "\n---\n\n" + body


class MemoryFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.module = load_module("memory_sources", MODULE)
        self.umask = os.umask(0o077)
        if not REAL_EXCEPTIONS:
            exceptions = types.ModuleType("openviking_cli.exceptions")
            exceptions.NotFoundError = NotFoundError
            patcher = patch.dict(sys.modules, {"openviking_cli": types.ModuleType("openviking_cli"),
                                               "openviking_cli.exceptions": exceptions})
            patcher.start()
            self.addCleanup(patcher.stop)

    def tearDown(self):
        os.umask(self.umask)
        self.temp.cleanup()

    def run_cli(self, argv, client):
        out = io.StringIO()
        with patch.object(self.module, "open_client", AsyncMock(return_value=(client, {"url": "fixture"}))):
            with contextlib.redirect_stdout(out):
                self.module.main(argv)
        return json.loads(out.getvalue())


class FileMemoryTest(MemoryFixture):
    def setUp(self):
        super().setUp()
        self.source = self.root / "agents/memory"
        self.source.mkdir(parents=True)
        self.state = self.root / "state"

    def write(self, name, text):
        (self.source / name).write_text(text)

    def files(self, *extra, client=None):
        return self.run_cli(["files", "--source", str(self.source), "--state-root", str(self.state), *extra], client or FakeClient())

    def actions(self, result):
        return {row["name"]: row["action"] for row in result["files"]}

    def test_classifies_each_file_and_reports_direction_without_writing(self):
        self.write("feedback_new.md", memory("feedback"))
        self.write("feedback_same.md", memory("feedback", "Same.\n"))
        self.write("project_changed.md", memory("project", "File text.\n"))
        self.write("reference_moved.md", memory("reference"))
        self.write("MEMORY.md", "- [reference_skip](reference_skip.md) - note (personal)\n")
        self.write("reference_skip.md", memory("reference"))
        self.write("user_profile.md", memory("user"))
        self.write("notes.md", "no front matter and no known prefix\n")
        client = FakeClient({
            "preferences/user/feedback_same.md": memory("feedback", "Same.\n"),
            "entities/project/project_changed.md": memory("project", "OpenViking text.\n"),
            "entities/other/reference_moved.md": memory("reference"),
        })
        result = self.files(client=client)
        self.assertEqual(self.actions(result), {"feedback_new.md": "new", "project_changed.md": "conflict",
                                                "reference_moved.md": "present-elsewhere"})
        self.assertEqual(result["summary"], {"new": 1, "identical": 1, "conflict": 1, "present-elsewhere": 1})
        changed = next(row for row in result["files"] if row["name"] == "project_changed.md")
        self.assertEqual(changed["newer"], "file")
        self.assertEqual(changed["change"], {"added": 1, "removed": 1})
        skipped = {row["name"]: row["reason"] for row in result["skipped_files"]}
        self.assertEqual(skipped, {"reference_skip.md": "personal-marker", "user_profile.md": "profile-singleton-review",
                                   "notes.md": "unclassified"})
        self.assertEqual(client.writes, [])
        self.assertFalse(self.state.exists())

    def test_symlinks_resolve_to_one_canonical_copy_and_unsafe_links_are_skipped(self):
        self.write("project_real.md", memory("project"))
        outside = self.root / "outside.md"
        outside.write_text(memory("reference"))
        (self.source / "project_link.md").symlink_to("project_real.md")
        (self.source / "reference_out.md").symlink_to(outside)
        (self.source / "reference_gone.md").symlink_to(self.root / "absent.md")
        alias = self.root / "alias"
        alias.symlink_to(self.source)
        result = self.run_cli(["files", "--source", str(alias), "--source", str(self.source),
                               "--state-root", str(self.state)], FakeClient())
        self.assertEqual(result["sources"], [str(self.source.resolve())])
        self.assertEqual(result["aliases"], [{"source": str(self.source), "alias_of": str(self.source.resolve())}])
        self.assertEqual(self.actions(result), {"project_real.md": "new"})
        skipped = {row["name"]: row["reason"] for row in result["skipped_files"]}
        self.assertEqual(skipped, {"project_link.md": "duplicate-of-project_real.md",
                                   "reference_out.md": "link-outside-sources", "reference_gone.md": "dangling-link"})

    def test_a_link_between_two_named_sources_is_followed(self):
        other = self.root / "other"
        other.mkdir()
        (other / "reference_shared.md").write_text(memory("reference"))
        (self.source / "reference_shared.md").symlink_to(other / "reference_shared.md")
        result = self.run_cli(["files", "--source", str(self.source), "--source", str(other),
                               "--state-root", str(self.state)], FakeClient())
        self.assertEqual(self.actions(result), {"reference_shared.md": "new"})
        self.assertEqual(len(result["skipped_files"]), 1)

    def test_apply_writes_only_new_files_and_a_rerun_writes_nothing(self):
        self.write("feedback_new.md", memory("feedback"))
        self.write("project_changed.md", memory("project", "File text.\n"))
        self.write("reference_same.md", memory("reference"))
        client = FakeClient({"entities/project/project_changed.md": memory("project", "OpenViking text.\n"),
                             "entities/reference/reference_same.md": memory("reference")})
        first = self.files("--apply", client=client)
        self.assertEqual(client.writes, ["preferences/user/feedback_new.md"])
        self.assertEqual(first["written"], 1)
        self.assertEqual(self.actions(first), {"feedback_new.md": "written", "project_changed.md": "conflict"})
        again = self.files("--apply", client=client)
        self.assertEqual(client.writes, ["preferences/user/feedback_new.md"])
        self.assertEqual(again["written"], 0)
        manifest = self.module.read_private(self.state / "default/state.json")
        self.assertEqual(sorted(manifest["files"]), ["entities/reference/reference_same.md", "preferences/user/feedback_new.md"])
        self.assertEqual((self.state / "default").stat().st_mode & 0o777, 0o700)

    def test_update_needs_a_named_approval_and_only_replaces_that_file(self):
        self.write("project_one.md", memory("project", "File one.\n"))
        self.write("project_two.md", memory("project", "File two.\n"))
        client = FakeClient({"entities/project/project_one.md": memory("project", "Old one.\n"),
                             "entities/project/project_two.md": memory("project", "Old two.\n")})
        self.files("--apply", "--update", "project_one.md", client=client)
        self.assertEqual(client.writes, ["entities/project/project_one.md"])
        self.assertEqual(client.files["entities/project/project_two.md"], memory("project", "Old two.\n"))
        with self.assertRaisesRegex(ValueError, "no pending change"):
            self.files("--apply", "--update", "project_one.md", client=client)

    def test_manifest_separates_a_file_edit_from_an_openviking_edit(self):
        self.write("project_item.md", memory("project", "Version one.\n"))
        client = FakeClient({"entities/project/project_item.md": memory("project", "Version one.\n")})
        self.files("--apply", client=client)
        self.write("project_item.md", memory("project", "Version two.\n"))
        edited = self.files(client=client)
        self.assertEqual(self.actions(edited), {"project_item.md": "update"})
        self.write("project_item.md", memory("project", "Version one.\n"))
        client.files["entities/project/project_item.md"] = memory("project", "Edited in OpenViking.\n")
        ahead = self.files(client=client)
        self.assertEqual(self.actions(ahead), {"project_item.md": "openviking-ahead"})

    def test_a_write_that_does_not_read_back_is_not_recorded(self):
        self.write("feedback_new.md", memory("feedback"))
        client = FakeClient(corrupt={"feedback_new.md"})
        result = self.files("--apply", client=client)
        self.assertEqual(self.actions(result), {"feedback_new.md": "write-unverified"})
        self.assertEqual(self.module.read_private(self.state / "default/state.json")["files"], {})

    def test_a_file_that_appears_after_the_plan_is_not_overwritten(self):
        class Racing(FakeClient):
            async def ls(self, uri, simple=False, recursive=False, node_limit=0):
                return []

        self.write("feedback_race.md", memory("feedback", "File.\n"))
        client = Racing({"preferences/user/feedback_race.md": memory("feedback", "Added meanwhile.\n")})
        result = self.files("--apply", client=client)
        self.assertEqual(self.actions(result), {"feedback_race.md": "appeared-since-plan"})
        self.assertEqual(client.writes, [])

    def test_an_approved_replacement_is_skipped_if_openviking_changed_after_the_plan(self):
        class Drifting(FakeClient):
            reads = 0

            async def read(self, uri):
                text = await super().read(uri)
                Drifting.reads += 1
                return text if Drifting.reads == 1 else memory("project", "Edited after the plan.\n")

        self.write("project_item.md", memory("project", "File text.\n"))
        client = Drifting({"entities/project/project_item.md": memory("project", "Reviewed text.\n")})
        result = self.files("--apply", "--update", "project_item.md", client=client)
        self.assertEqual(self.actions(result), {"project_item.md": "changed-since-plan"})
        self.assertEqual(client.writes, [])
        self.assertEqual(self.module.read_private(self.state / "default/state.json")["files"], {})

    def test_show_diff_is_opt_in(self):
        self.write("project_item.md", memory("project", "File.\n"))
        client = FakeClient({"entities/project/project_item.md": memory("project", "Remote.\n")})
        self.assertNotIn("diffs", self.files(client=client))
        diffs = self.files("--show-diff", "project_item.md", client=client)["diffs"]
        self.assertIn("-Remote.", diffs["project_item.md"])
        self.assertIn("+File.", diffs["project_item.md"])


def build_database(path, sessions):
    connection = sqlite3.connect(path)
    connection.execute("CREATE TABLE session_v2 (id TEXT PRIMARY KEY, project_id TEXT, parent_id TEXT, time_created INTEGER, time_updated INTEGER)")
    connection.execute("CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT)")
    for session in sessions:
        connection.execute("INSERT INTO session_v2 VALUES (?, ?, ?, ?, ?)", (session["id"], session.get("project", "proj one"),
                                                                       session.get("parent"), session["created"], session["updated"]))
        for seq, (kind, data) in enumerate(session.get("messages", [])):
            connection.execute("INSERT INTO session_message VALUES (?, ?, ?, ?, ?, ?, ?)",
                               (session["id"] + str(seq), session["id"], kind, seq, session["created"] + seq, session["created"] + seq, json.dumps(data)))
    connection.commit()
    connection.close()


def conversation(text="Question?"):
    return [("user", {"text": text}),
            ("assistant", {"model": {"id": "model-x", "providerID": "p"},
                           "content": [{"type": "reasoning", "text": "private thoughts"}, {"type": "tool", "text": "tool output"},
                                       {"type": "text", "text": "Answer."}]}),
            ("synthetic", {"text": "injected"})]


class OpenCodeExportTest(MemoryFixture):
    OLD = 1_700_000_000_000

    def setUp(self):
        super().setUp()
        self.database = self.root / "opencode.db"
        self.out = self.root / "snapshot"
        self.imports = self.root / "imports"
        build_database(self.database, [
            {"id": "ses_keep", "created": self.OLD, "updated": self.OLD, "messages": conversation()},
            {"id": "ses_live", "created": self.OLD, "updated": self.OLD, "messages": conversation()},
            {"id": "ses_done", "created": self.OLD, "updated": self.OLD, "messages": conversation()},
            {"id": "ses_child", "parent": "ses_keep", "created": self.OLD, "updated": self.OLD, "messages": conversation()},
            {"id": "ses_busy", "created": self.OLD, "updated": int(time.time() * 1000), "messages": conversation()},
            {"id": "ses_empty", "created": self.OLD, "updated": self.OLD,
             "messages": [("assistant", {"content": [{"type": "tool", "text": "only a tool"}]})]},
            {"id": "ses_old", "created": self.OLD - 10_000_000_000, "updated": self.OLD - 10_000_000_000, "messages": conversation()},
        ])
        (self.imports / "claude-earlier/state").mkdir(parents=True)
        self.module.save(self.imports / "claude-earlier/state/progress.json", {"files": {"ses_done": {"complete": True}}})

    def export(self, *extra, client=None, database=None):
        return self.run_cli(["oc2", "--db", str(database or self.database), "--imports-root", str(self.imports), *extra],
                            client or FakeClient(sessions={"oc-ses_live"}))

    def test_plan_names_why_each_session_is_skipped_and_writes_nothing(self):
        result = self.export("--since", "2023-11-01")
        self.assertEqual(result["summary"]["sessions"], 7)
        self.assertEqual(result["summary"]["skipped"], {"already-in-openviking": 1, "imported-elsewhere": 1, "child-session": 1,
                                                        "recently-active": 1, "no-conversation-text": 1, "before-since": 1})
        self.assertEqual(result["eligible_sessions"], ["ses_keep"])
        self.assertFalse(self.out.exists())

    def test_offline_mode_does_not_ask_openviking_which_sessions_it_holds(self):
        offline = self.export("--no-ov-check", client=FakeClient())
        self.assertEqual(sorted(offline["eligible_sessions"]), ["ses_keep", "ses_live", "ses_old"])

    def test_export_writes_a_private_claude_shaped_snapshot_of_conversation_text_only(self):
        result = self.export("--apply", "--out", str(self.out))
        self.assertEqual(result["snapshot"], str(self.out))
        self.assertEqual(self.out.stat().st_mode & 0o777, 0o700)
        folder = self.out / "proj_one"
        self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
        file = folder / "ses_keep.jsonl"
        self.assertEqual(file.stat().st_mode & 0o777, 0o600)
        records = [json.loads(line) for line in file.read_text().splitlines()]
        self.assertEqual([record["type"] for record in records], ["user", "assistant"])
        self.assertEqual(records[0]["message"], {"role": "user", "content": "Question?"})
        self.assertEqual(records[1]["message"], {"role": "assistant", "model": "model-x",
                                                 "content": [{"type": "text", "text": "Answer."}]})
        self.assertTrue(records[0]["timestamp"].endswith("Z"))
        self.assertNotIn("private thoughts", file.read_text())
        self.assertNotIn("tool output", file.read_text())

    @unittest.skipUnless(HAS_RUNTIME, "OpenViking runtime is not installed")
    def test_snapshot_lines_parse_with_the_upstream_claude_source(self):
        from openviking.ingest.sources.claude_code import ClaudeCodeSource

        self.export("--apply", "--out", str(self.out))
        source = ClaudeCodeSource.__new__(ClaudeCodeSource)
        source.user_peer = lambda **kwargs: None
        source.assistant_peer = lambda model, provider=None: None
        lines = (self.out / "proj_one/ses_keep.jsonl").read_text().splitlines()
        parsed = [source.parse_line(json.loads(line), None) for line in lines]
        self.assertEqual([[message.text for message in group] for group in parsed], [["Question?"], ["Answer."]])

    def test_export_needs_a_new_empty_directory(self):
        self.export("--apply", "--out", str(self.out))
        with self.assertRaisesRegex(ValueError, "new, empty"):
            self.export("--apply", "--out", str(self.out))
        with self.assertRaisesRegex(ValueError, "--out is required"):
            self.export("--apply")

    def test_a_symlinked_database_path_is_resolved_and_a_v1_database_is_refused(self):
        link = self.root / "link.db"
        link.symlink_to(self.database)
        self.assertEqual(self.export(database=link)["database"], str(self.database.resolve()))
        legacy = self.root / "legacy.db"
        with contextlib.closing(sqlite3.connect(legacy)) as connection:
            connection.execute("CREATE TABLE session (id TEXT)")
        with self.assertRaisesRegex(ValueError, "session_v2"):
            self.export(database=legacy)
        with self.assertRaisesRegex(ValueError, "not found"):
            self.export(database=self.root / "absent.db")


if __name__ == "__main__":
    unittest.main()
