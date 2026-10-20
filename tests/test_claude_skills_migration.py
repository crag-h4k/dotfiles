# tests/test_claude_skills_migration.py
"""Check migration from Claude's legacy skill directory to Agent Skills."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
MODULE = REPO / "scripts/migrate-claude-skills.py"
SPEC = importlib.util.spec_from_file_location("migrate_claude_skills", MODULE)
assert SPEC and SPEC.loader
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)

GIT_ENVIRONMENT = ("GIT_DIR", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE")


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

    def test_empty_readable_legacy_root_still_plans_the_link_replacement(self) -> None:
        root = self.home / ".claude/skills"
        root.mkdir(parents=True)

        plan = MIGRATION.migration_plan(self.home)

        self.assertEqual(plan, [("create", self.home / ".agents/skills", None), ("link", root, self.home / ".agents/skills")])

    def test_group_or_world_writable_legacy_root_is_still_refused(self) -> None:
        for mode in (0o775, 0o757):
            with self.subTest(mode=oct(mode)):
                root = self.home / ".claude/skills"
                root.mkdir(parents=True, exist_ok=True)
                root.chmod(mode)

                with self.assertRaisesRegex(ValueError, "not group or world writable"):
                    MIGRATION.migration_plan(self.home)

    def deny(self, path: Path, mode: int = 0) -> None:
        """Set path to a mode that blocks the owner's access until the test ends."""
        original = path.stat().st_mode & 0o7777
        path.chmod(mode)
        # Cleanups run last-in first-out, so this runs before the temporary
        # directory is removed.
        self.addCleanup(path.chmod, original)
        if os.access(path, os.R_OK | os.X_OK):
            self.skipTest("permission bits are not enforced for this account")

    def inaccessible_states(self) -> dict[str, Path]:
        """Create the homes where the legacy skills root cannot be inspected."""
        states = {}
        for name, hidden in (("claude", ".claude"), ("skills", ".claude/skills")):
            home = self.home.parent / ("denied-" + name)
            skill = home / ".claude/skills/local-example/SKILL.md"
            skill.parent.mkdir(parents=True)
            skill.write_text("legacy skill\n")
            self.deny(home / hidden)
            states[name] = home
        return states

    def test_inaccessible_legacy_root_is_skipped_not_raised(self) -> None:
        # Path.exists() and Path.is_symlink() raise EACCES before Python 3.14,
        # so an untraversable ~/.claude used to abort the plan.
        for name, home in self.inaccessible_states().items():
            with self.subTest(denied=name):
                plan = MIGRATION.migration_plan(home)

                self.assertEqual(plan, [("inaccessible", home / ".claude/skills", None)])
                self.assertEqual(
                    MIGRATION.describe(plan),
                    "Claude skills directory is not accessible; skipping legacy migration",
                )
                MIGRATION.apply(plan, home)
                self.assertFalse(MIGRATION.journal_path(home).exists())

    def test_command_line_skips_an_inaccessible_legacy_root(self) -> None:
        for name, home in self.inaccessible_states().items():
            for arguments in ([], ["--apply"]):
                with self.subTest(denied=name, arguments=arguments):
                    result = subprocess.run(
                        [sys.executable, str(MODULE), "--home", str(home), *arguments],
                        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                    )

                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(
                        result.stdout.strip(),
                        "Claude skills directory is not accessible; skipping legacy migration",
                    )
                    self.assertEqual(result.stderr, "")

    def hook_repo(self) -> Path:
        """Build a minimal source tree that manages only the Claude skills link."""
        repo = self.home.parent / "hook-repo"
        scripts = repo / "scripts"
        hooks = repo / "home/.chezmoiscripts"
        (repo / "home/dot_claude").mkdir(parents=True)
        scripts.mkdir()
        hooks.mkdir()
        (repo / ".chezmoiroot").write_text("home\n")
        (repo / "home/dot_claude/symlink_skills").write_text("../.agents/skills\n")
        shutil.copyfile(REPO / "home/.chezmoiscripts/run_before_00-backup.sh", hooks / "run_before_00-backup.sh")
        shutil.copyfile(MODULE, scripts / "migrate-claude-skills.py")
        return repo

    def hook_environment(self, home: Path, repo: Path, *path_prefix: Path) -> dict:
        """Return a clean environment for running the hook or chezmoi against home."""
        # The hook runs `python3`; make it the interpreter under test.
        interpreter = self.home.parent / "interpreter"
        if not interpreter.exists():
            interpreter.mkdir()
            (interpreter / "python3").symlink_to(sys.executable)
        config = home / ".config/chezmoi/chezmoi.toml"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text('sourceDir = "' + str(repo) + '"\n')
        environment = {key: value for key, value in os.environ.items() if key not in GIT_ENVIRONMENT}
        environment.update({
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_DATA_HOME": str(home / ".local/share"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "XDG_STATE_HOME": str(home / ".local/state"),
            "CHEZMOI_SOURCE_DIR": str(repo / "home"),
            "PATH": os.pathsep.join([*map(str, path_prefix), str(interpreter), os.environ["PATH"]]),
        })
        environment.pop("DOTFILES_MIGRATE_CLAUDE_SKILLS", None)
        return environment

    def run_hook(self, repo: Path, environment: dict) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(repo / "home/.chezmoiscripts/run_before_00-backup.sh")],
            env=environment, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )

    def test_pre_apply_hook_skips_an_inaccessible_legacy_root(self) -> None:
        # Run the hook alone: with a non-empty root chezmoi itself must still
        # replace the directory, which is outside what the hook can do. A denied
        # ~/.claude is different: the hook repairs it, so it is covered below.
        repo = self.hook_repo()
        home = self.inaccessible_states()["skills"]
        environment = self.hook_environment(home, repo)

        result = self.run_hook(repo, environment)

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("migrate-claude-skills:", output)
        self.assertNotIn("Traceback", output)
        self.assertNotIn("review the Claude skill migration", output)
        self.assertNotIn("restored owner access", output)

    def test_pre_apply_hook_reviews_skills_inside_an_untraversable_claude_dir(self) -> None:
        # `-d ~/.claude/skills` is false while ~/.claude cannot be searched, so
        # the hook used to skip the review gate and the move-aside entirely.
        repo = self.hook_repo()
        home = self.inaccessible_states()["claude"]
        environment = self.hook_environment(home, repo)

        result = self.run_hook(repo, environment)

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 1, output)
        self.assertIn("review the Claude skill migration", output)
        self.assertEqual(output.count("restored owner access"), 1, output)
        self.assertEqual((home / ".claude").stat().st_mode & 0o777, 0o700)
        self.assertEqual((home / ".claude/skills/local-example/SKILL.md").read_text(), "legacy skill\n")

        environment["DOTFILES_MIGRATE_CLAUDE_SKILLS"] = "true"
        result = self.run_hook(repo, environment)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("restored owner access", result.stdout)
        self.assertTrue((home / ".claude/skills").is_symlink())
        self.assertEqual((home / ".agents/skills/local-example/SKILL.md").read_text(), "legacy skill\n")

    def test_apply_stops_at_the_review_gate_for_an_untraversable_claude_dir(self) -> None:
        # End to end: chezmoi owns the mode of ~/.claude, so it repaired the
        # directory itself and replaced skills/ with the link, losing the skills.
        repo = self.hook_repo()
        home = self.inaccessible_states()["claude"]
        environment = self.hook_environment(home, repo)
        command = ["chezmoi", "--source", str(repo), "--destination", str(home), "--no-tty", "apply"]

        result = subprocess.run(command, env=environment, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=60)

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 1, output)
        self.assertIn("review the Claude skill migration", output)
        skills = home / ".claude/skills"
        self.assertFalse(skills.is_symlink(), output)
        self.assertEqual((skills / "local-example/SKILL.md").read_text(), "legacy skill\n")

        environment["DOTFILES_MIGRATE_CLAUDE_SKILLS"] = "true"
        result = subprocess.run(command, env=environment, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=60)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(skills.is_symlink())
        self.assertEqual((home / ".agents/skills/local-example/SKILL.md").read_text(), "legacy skill\n")

    def test_pre_apply_hook_only_repairs_what_it_owns_and_must(self) -> None:
        repo = self.hook_repo()
        fake_bin = self.home.parent / "fake-bin"
        fake_bin.mkdir()
        (fake_bin / "chmod").write_text("#!/bin/sh\nexit 1\n")
        (fake_bin / "chmod").chmod(0o755)

        def prepared(name: str, mode: int) -> Path:
            home = self.home.parent / ("guard-" + name)
            (home / ".claude").mkdir(parents=True)
            (home / ".claude/settings.json").write_text("{}\n")
            self.deny(home / ".claude", mode)
            return home

        with self.subTest(case="already searchable"):
            home = self.home.parent / "guard-searchable"
            (home / ".claude").mkdir(parents=True)
            (home / ".claude").chmod(0o750)
            result = self.run_hook(repo, self.hook_environment(home, repo))

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("restored owner access", result.stdout)
            self.assertEqual((home / ".claude").stat().st_mode & 0o777, 0o750)

        with self.subTest(case="only the owner bits change"):
            home = prepared("bits", 0o604)
            result = self.run_hook(repo, self.hook_environment(home, repo))

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((home / ".claude").stat().st_mode & 0o777, 0o704)

        with self.subTest(case="symlink is never changed"):
            home = self.home.parent / "guard-symlink"
            home.mkdir()
            target = self.home.parent / "guard-symlink-target"
            target.mkdir()
            (home / ".claude").symlink_to(target)
            self.deny(target)
            result = self.run_hook(repo, self.hook_environment(home, repo))

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("restored owner access", result.stdout)
            self.assertEqual(target.stat().st_mode & 0o777, 0)

        with self.subTest(case="failed chmod warns and continues"):
            home = prepared("chmod-fails", 0)
            result = self.run_hook(repo, self.hook_environment(home, repo, fake_bin))

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("WARNING could not restore access", result.stderr)
            self.assertNotIn("restored owner access", result.stdout)
            self.assertEqual((home / ".claude").stat().st_mode & 0o777, 0)

    def real_apply(self, home: Path, *features: str) -> subprocess.CompletedProcess:
        """Apply the whole repository to a disposable home, configs only, no network."""
        lines = [
            f'sourceDir = "{REPO}"', "[data]", 'installMode = "configs"', 'palette = "dracula"',
            "[data.components]", "zsh = false", "tmux = false", "neovim = false", "[data.components.ai]",
        ]
        for feature in ("claude_hooks", "codex_hooks", "statusline", "opencode", "copilot", "openviking", "codecompanion"):
            lines.append(f"{feature} = {str(feature in features).lower()}")
        lines += [
            "[data.components.git]", "config = false", "personal = false", "ignore_global = false",
            "[data.components.terminal]", "ghostty = false", "iterm2 = false",
        ]
        config = home / ".config/chezmoi/chezmoi.toml"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text("\n".join(lines) + "\n")
        environment = {key: value for key, value in os.environ.items() if key not in GIT_ENVIRONMENT}
        environment.update({
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_DATA_HOME": str(home / ".local/share"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "XDG_STATE_HOME": str(home / ".local/state"),
        })
        environment.pop("DOTFILES_MIGRATE_CLAUDE_SKILLS", None)
        return subprocess.run(
            ["chezmoi", "--source", str(REPO), "--destination", str(home), "--no-tty",
             "apply", "--exclude=externals", "--refresh-externals=never"],
            env=environment, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120,
        )

    def codex_repo(self) -> Path:
        """Build a minimal source tree around the real .chezmoiremove."""
        repo = self.home.parent / "codex-repo"
        (repo / "home/dot_codex").mkdir(parents=True)
        (repo / ".chezmoiroot").write_text("home\n")
        (repo / "home/dot_codex/managed.txt").write_text("managed\n")
        shutil.copyfile(REPO / "home/.chezmoiremove", repo / "home/.chezmoiremove")
        return repo

    def codex_apply(self, repo: Path, home: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["chezmoi", "--source", str(repo), "--destination", str(home), "--no-tty", "apply"],
            env=self.hook_environment(home, repo), stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=60,
        )

    def stale_codex_theme(self, name: str) -> Path:
        """Create a home holding the old Codex theme that .chezmoiremove deletes."""
        stale = self.home.parent / name / ".codex/themes/gud.tmTheme"
        stale.parent.mkdir(parents=True)
        stale.write_text("old theme\n")
        return stale

    def test_apply_tolerates_an_untraversable_codex_directory(self) -> None:
        # Chezmoi reads .chezmoiremove before any script runs, so a hook cannot
        # repair ~/.codex first; the removal of the old theme is skipped instead.
        repo = self.codex_repo()
        stale = self.stale_codex_theme("codex-denied")
        home = stale.parents[2]
        self.deny(home / ".codex")

        result = self.codex_apply(repo, home)

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("permission denied", output)

        # Chezmoi repairs the mode of the directory it manages, so the skipped
        # removal runs on the next apply.
        again = self.codex_apply(repo, home)

        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertFalse(stale.exists())

    def test_apply_still_removes_the_old_codex_theme_from_a_searchable_directory(self) -> None:
        repo = self.codex_repo()
        stale = self.stale_codex_theme("codex-searchable")

        result = self.codex_apply(repo, stale.parents[2])

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(stale.exists())

    def test_full_apply_tolerates_an_untraversable_codex_directory(self) -> None:
        # One run against the real source and selections, which also exercises
        # the ignore rules and the Codex merge target around the removal.
        stale = self.stale_codex_theme("codex-full")
        home = stale.parents[2]
        (home / ".codex/config.toml").write_text('model = "local-model"\n')
        self.deny(home / ".codex")

        result = self.real_apply(home, "claude_hooks", "codex_hooks", "statusline")

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("permission denied", output)
        self.assertIn('model = "local-model"', (home / ".codex/config.toml").read_text())

    def test_openviking_only_apply_tolerates_absent_harness_directories(self) -> None:
        # Claude and Codex are not selected, so a host may have neither, or only
        # one, of their home directories. The apply must still finish cleanly.
        states = {
            "neither": (),
            "claude-only": (".claude",),
            "codex-only": (".codex",),
        }
        failure_markers = ("No such file", "Traceback", "does not exist", "cannot access")
        # The validator needs tomllib (Python 3.11+); the migration helper under
        # test does not, so only this test is skipped on older interpreters.
        validator_spec = importlib.util.spec_from_file_location(
            "validate_agent_skills", REPO / "scripts/validate-agent-skills.py"
        )
        assert validator_spec and validator_spec.loader
        validator = importlib.util.module_from_spec(validator_spec)
        try:
            validator_spec.loader.exec_module(validator)
        except ModuleNotFoundError as error:
            self.skipTest("scripts/validate-agent-skills.py needs " + str(error.name))
        for name, directories in states.items():
            with self.subTest(state=name):
                home = self.home.parent / ("home-" + name)
                home.mkdir()
                for directory in directories:
                    (home / directory).mkdir()
                config = home / ".config/chezmoi/chezmoi.toml"
                config.parent.mkdir(parents=True)
                # The pre-apply hook runs a bare `chezmoi managed`, which finds
                # the source through this config rather than the apply's flags.
                config.write_text(f'sourceDir = "{REPO}"\n' + validator.component_config({"openviking"}))
                environment = {key: value for key, value in os.environ.items() if key not in GIT_ENVIRONMENT}
                environment.update({
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "XDG_DATA_HOME": str(home / ".local/share"),
                    "XDG_CACHE_HOME": str(home / ".cache"),
                    "XDG_STATE_HOME": str(home / ".local/state"),
                })
                environment.pop("DOTFILES_MIGRATE_CLAUDE_SKILLS", None)

                result = subprocess.run(
                    ["chezmoi", "--source", str(REPO), "--destination", str(home), "--no-tty",
                     "apply", "--exclude=externals", "--refresh-externals=never"],
                    env=environment, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120,
                )

                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                for marker in failure_markers:
                    self.assertNotIn(marker, output)
                self.assertEqual((home / ".claude/skills").readlink(), MIGRATION.EXPECTED_LINK)
                self.assertTrue((home / ".agents/skills/openviking-memory").is_symlink())
                self.assertFalse((home / ".codex/skills").exists())
                self.assertFalse((home / ".codex/skill").exists())


if __name__ == "__main__":
    unittest.main()
