# tests/test_claude_skills_migration.py
"""Check migration from Claude's legacy skill directory to Agent Skills."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
MODULE = REPO / "scripts/migrate-claude-skills.py"
SPEC = importlib.util.spec_from_file_location("migrate_claude_skills", MODULE)
assert SPEC and SPEC.loader
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)


class ClaudeSkillsMigrationTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name) / "home"
        self.home.mkdir()

    def legacy(self, name: str, content: str = "fixture\n") -> Path:
        path = self.home / ".claude/skills" / name / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def canonical(self, name: str, content: str = "fixture\n") -> Path:
        path = self.home / ".agents/skills" / name / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_missing_legacy_root_leaves_the_managed_link_to_chezmoi(self) -> None:
        plan = MIGRATION.migration_plan(self.home)

        self.assertEqual(plan, [("absent", self.home / ".claude/skills", None)])
        MIGRATION.apply(plan)
        self.assertFalse((self.home / ".claude/skills").exists())

    def test_moves_unique_and_synced_skills_then_creates_the_root_link(self) -> None:
        self.legacy("local-example", "local skill\n")
        self.legacy("synced/account-skill", "synced skill\n")
        self.canonical("managed-example", "managed skill\n")
        self.legacy("managed-example", "managed skill\n")

        plan = MIGRATION.migration_plan(self.home)
        self.assertIn(("move", self.home / ".claude/skills/local-example",
                       self.home / ".agents/skills/local-example"), plan)
        self.assertIn(("deduplicate", self.home / ".claude/skills/managed-example",
                       self.home / ".agents/skills/managed-example"), plan)
        MIGRATION.apply(plan)

        root = self.home / ".claude/skills"
        self.assertTrue(root.is_symlink())
        self.assertEqual(root.readlink(), MIGRATION.EXPECTED_LINK)
        self.assertEqual((self.home / ".agents/skills/local-example/SKILL.md").read_text(), "local skill\n")
        self.assertEqual((self.home / ".agents/skills/synced/account-skill/SKILL.md").read_text(), "synced skill\n")
        self.assertEqual((root / "managed-example/SKILL.md").read_text(), "managed skill\n")

    def test_planning_a_move_does_not_create_the_agent_root(self) -> None:
        self.legacy("local-example", "local skill\n")

        plan = MIGRATION.migration_plan(self.home)

        self.assertIn(("create", self.home / ".agents/skills", None), plan)
        self.assertFalse((self.home / ".agents/skills").exists())

    def test_apply_records_a_private_completed_migration_journal(self) -> None:
        self.legacy("local-example", "local skill\n")
        plan = MIGRATION.migration_plan(self.home)

        MIGRATION.apply(plan, self.home)

        journal = MIGRATION.journal_path(self.home)
        self.assertEqual(journal.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(journal.read_text())["status"], "complete")

    def test_incomplete_journal_blocks_a_second_automatic_migration(self) -> None:
        self.legacy("local-example", "local skill\n")
        MIGRATION.write_journal(self.home, "in_progress", [])

        with self.assertRaisesRegex(ValueError, "incomplete"):
            MIGRATION.migration_plan(self.home)

    def test_incomplete_journal_blocks_an_already_replaced_root(self) -> None:
        agent_root = self.home / ".agents/skills"
        agent_root.mkdir(parents=True)
        claude_root = self.home / ".claude"
        claude_root.mkdir()
        (claude_root / "skills").symlink_to("../.agents/skills")
        MIGRATION.write_journal(self.home, "in_progress", [])

        with self.assertRaisesRegex(ValueError, "incomplete"):
            MIGRATION.migration_plan(self.home)

    def test_conflicting_skill_stops_without_changing_either_root(self) -> None:
        legacy = self.legacy("conflict", "legacy\n")
        canonical = self.canonical("conflict", "canonical\n")

        with self.assertRaisesRegex(ValueError, "conflicts"):
            MIGRATION.migration_plan(self.home)

        self.assertEqual(legacy.read_text(), "legacy\n")
        self.assertEqual(canonical.read_text(), "canonical\n")
        self.assertTrue((self.home / ".claude/skills").is_dir())

    def test_unexpected_legacy_symlink_is_never_replaced(self) -> None:
        root = self.home / ".claude"
        root.mkdir()
        (root / "skills").symlink_to("../elsewhere")

        with self.assertRaisesRegex(ValueError, "unexpected target"):
            MIGRATION.migration_plan(self.home)

        self.assertEqual((root / "skills").readlink(), Path("../elsewhere"))

    def test_humanizer_manifest_moves_outside_skill_discovery(self) -> None:
        source = self.home / ".local/share/agent-skills/humanizer/upstream/SKILL.md"
        source.parent.mkdir(parents=True)
        source.write_text("upstream instructions\n")

        plan = MIGRATION.humanizer_instructions_plan(self.home)
        self.assertEqual(plan, [("move", source, source.with_name("instructions.md"))])
        MIGRATION.apply(plan)

        self.assertFalse(source.exists())
        self.assertEqual(source.with_name("instructions.md").read_text(), "upstream instructions\n")

    def test_pre_apply_hook_migrates_before_chezmoi_writes_the_root_link(self) -> None:
        repo = self.home.parent / "repo"
        source = repo / "home"
        scripts = repo / "scripts"
        source.mkdir(parents=True)
        scripts.mkdir()
        (repo / ".chezmoiroot").write_text("home\n")
        hooks = source / ".chezmoiscripts"
        hooks.mkdir()
        shutil.copyfile(REPO / "home/.chezmoiscripts/run_before_00-backup.sh", hooks / "run_before_00-backup.sh")
        shutil.copyfile(MODULE, scripts / "migrate-claude-skills.py")
        claude = source / "dot_claude"
        claude.mkdir()
        (claude / "symlink_skills").write_text("../.agents/skills\n")
        self.legacy("local-example", "legacy skill\n")
        config = self.home / ".config/chezmoi/chezmoi.toml"
        config.parent.mkdir(parents=True)
        config.write_text('sourceDir = "' + str(repo) + '"\n')
        environment = {
            **os.environ,
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "DOTFILES_MIGRATE_CLAUDE_SKILLS": "true",
        }

        result = subprocess.run(
            ["chezmoi", "--source", str(repo), "--destination", str(self.home), "--no-tty", "apply"],
            env=environment, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        root = self.home / ".claude/skills"
        self.assertTrue(root.is_symlink())
        self.assertEqual((self.home / ".agents/skills/local-example/SKILL.md").read_text(), "legacy skill\n")


if __name__ == "__main__":
    unittest.main()
