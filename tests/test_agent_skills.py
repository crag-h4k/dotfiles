# tests/test_agent_skills.py
"""Regression tests for the public cross-harness agent-skill contract."""

from __future__ import annotations

import importlib.util
import io
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts/validate-agent-skills.py"
SPEC = importlib.util.spec_from_file_location("validate_agent_skills", MODULE_PATH)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class PublicTextTests(unittest.TestCase):
    def assert_rejected(self, text: str, category: str) -> None:
        findings = VALIDATOR.scan_public_text("fixture", text)
        self.assertTrue(
            any(category in finding for finding in findings),
            msg=f"expected {category!r} finding, got {findings!r}",
        )

    def test_rejects_identity_and_internal_markers(self) -> None:
        self.assert_rejected("/Users/" + "sample-person/work/file", "real home path")
        self.assert_rejected("~/" + "work/project/file", "work-tree shorthand")
        self.assert_rejected("person@" + "company.example", "corporate email")
        self.assert_rejected("Example" + "Corp", "corporate name")
        self.assert_rejected("project-" + "codename: sample", "internal codename")
        self.assert_rejected("PROJ" + "-123", "Jira-style identifier")

    def test_rejects_credentials_and_private_integrations(self) -> None:
        self.assert_rejected("AK" + "IA" + "A" * 16, "cloud access-key")
        self.assert_rejected("gh" + "p_" + "a" * 20, "service token")
        self.assert_rejected("api_" + "key = realvalue123", "credential assignment")
        self.assert_rejected(
            "https" + "://service." + "corp.example/api", "private endpoint"
        )
        self.assert_rejected("mcp" + ': {"servers": {}}', "private MCP")

    def test_rejects_mutable_and_unexpected_urls(self) -> None:
        self.assert_rejected(
            "https" + "://raw.githubusercontent.com/example/project/"
            + "main/SKILL.md",
            "mutable ref",
        )
        self.assert_rejected(
            "https" + "://downloads." + "example.net/skill.md", "unexpected host"
        )

    def test_allows_generic_public_examples(self) -> None:
        text = (
            "$HOME/.agents/skills/example\n"
            "https" + "://github.com/example/project/tree/"
            + "a" * 40
            + "/skills/example\n"
            "maintainer@" + "example.invalid\n"
            "SHA-256\n"
        )
        self.assertEqual(VALIDATOR.scan_public_text("fixture", text), [])


class LayoutRejectionTests(unittest.TestCase):
    def make_root(self) -> Path:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        root = Path(temp_dir.name)
        for harness in ("claude", "agents"):
            skill_root = root / f"home/dot_{harness}/skills"
            skill_root.mkdir(parents=True)
            for skill_id in VALIDATOR.SKILL_IDS:
                (skill_root / f"symlink_{skill_id}").write_text(
                    f"../../.local/share/agent-skills/{skill_id}\n",
                    encoding="utf-8",
                )
        canonical = root / "home/dot_local/share/agent-skills"
        (canonical / "humanizer/agents").mkdir(parents=True)
        (canonical / "handoff/scripts").mkdir(parents=True)
        (canonical / "readonly_PROVENANCE.md").touch()
        (canonical / "handoff/readonly_SKILL.md").touch()
        (canonical / "handoff/scripts/readonly_executable_snapshot.sh").touch()
        (canonical / "humanizer/readonly_SKILL.md").touch()
        (canonical / "humanizer/agents/readonly_openai.yaml").touch()
        for relative in VALIDATOR.DOTFILES_SKILL_FILES:
            path = canonical / "chezmoi-dotfiles" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        return root

    def test_accepts_canonical_first_party_layout(self) -> None:
        self.assertEqual(VALIDATOR.validate_layout(self.make_root()), [])

    def test_rejects_whole_directory_symlink_source(self) -> None:
        root = self.make_root()
        (root / "home/dot_claude/symlink_skills").touch()
        findings = VALIDATOR.validate_layout(root)
        self.assertTrue(any("whole-directory" in finding for finding in findings))

    def test_rejects_unexpected_harness_skill_file(self) -> None:
        root = self.make_root()
        (root / "home/dot_agents/skills/extra-skill.md").touch()
        findings = VALIDATOR.validate_layout(root)
        self.assertTrue(any("unexpected harness" in finding for finding in findings))


class RepositoryContractTests(unittest.TestCase):
    def test_repository_contract(self) -> None:
        self.assertEqual(VALIDATOR.validate_repository(REPO_ROOT), [])

    def test_public_scan_covers_the_ricer_definition(self) -> None:
        relative = "home/dot_config/opencode/agents/ricer.md"
        self.assertIn(relative, VALIDATOR.PUBLIC_TEXT_FILES)
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        root = Path(temp_dir.name)
        target = root / relative
        target.parent.mkdir(parents=True)
        target.write_text("/Users/" + "sample-person/private-agent\n")
        findings = VALIDATOR.validate_public_text(root)
        self.assertIn(f"{relative}: contains real home path", findings)


class SkillDeploymentTests(unittest.TestCase):
    def setUp(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        self.root = Path(temp_dir.name)
        self.destination = self.root / "home"
        self.destination.mkdir()
        self.config = self.root / "chezmoi.toml"
        self.env = os.environ.copy()
        self.env.update({
            "HOME": str(self.destination),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
        })

    def run_chezmoi(self, command: str, *args: str) -> bytes:
        result = subprocess.run(
            [
                "chezmoi", command,
                "--source", str(REPO_ROOT),
                "--config", str(self.config),
                "--destination", str(self.destination),
                "--exclude=scripts,externals",
                "--refresh-externals=never",
                "--no-tty",
                *args,
            ],
            env=self.env,
            capture_output=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout

    def test_every_ai_feature_gates_the_skill_and_excludes_guidance(self) -> None:
        for features in (set(), *({name} for name in VALIDATOR.AI_FEATURES)):
            with self.subTest(features=features):
                self.config.write_text(VALIDATOR.component_config(features))
                managed = self.run_chezmoi("managed", "--path-style=relative").decode().splitlines()
                instructions = [path for path in managed if Path(path).name == "AGENTS.md"]
                self.assertEqual(instructions, [".config/opencode/AGENTS.md"] if features == {"opencode"} else [])
                for target in (
                    ".local/share/agent-skills/chezmoi-dotfiles/SKILL.md",
                    ".local/share/agent-skills/chezmoi-dotfiles/references/workflows.md",
                    ".local/share/agent-skills/chezmoi-dotfiles/references/decisions.md",
                    ".agents/skills/chezmoi-dotfiles",
                    ".claude/skills/chezmoi-dotfiles",
                    ".config/opencode/commands/dotfiles.md",
                ):
                    self.assertEqual(target in managed, bool(features), target)
                self.assertEqual(
                    ".config/opencode/agents/ricer.md" in managed,
                    features == {"opencode"},
                )

    def test_archive_omits_repository_guidance(self) -> None:
        self.config.write_text(VALIDATOR.component_config(set(VALIDATOR.AI_FEATURES)))
        archive = self.run_chezmoi("archive", "--format=tar")
        with tarfile.open(fileobj=io.BytesIO(archive)) as rendered:
            instructions = [entry.name for entry in rendered if Path(entry.name).name == "AGENTS.md"]
            self.assertEqual(instructions, [".config/opencode/AGENTS.md"])

    def test_ricer_apply_preserves_independent_local_agents(self) -> None:
        self.config.write_text(VALIDATOR.component_config({"opencode"}))
        agents = self.destination / ".config/opencode/agents"
        agents.mkdir(parents=True)
        independent = agents / "local-example.md"
        independent.write_text("Independent local agent\n")
        self.run_chezmoi("apply", "--", str(agents))
        source = REPO_ROOT / "home/dot_config/opencode/agents/ricer.md"
        deployed = agents / "ricer.md"
        self.assertEqual(deployed.read_bytes(), source.read_bytes())
        header = deployed.read_text().split("---\n", maxsplit=2)[1]
        self.assertIn("\nmode: subagent\n", header)
        self.assertNotIn("\nmodel:", header)
        self.assertEqual(independent.read_text(), "Independent local agent\n")

    def test_global_opencode_instructions_preserve_local_content(self) -> None:
        self.config.write_text(VALIDATOR.component_config({"opencode"}))
        target = self.destination / ".config/opencode/AGENTS.md"
        target.parent.mkdir(parents=True)
        target.write_text("# Local rules\n\nKeep my custom rule.\n")
        target.chmod(0o600)
        self.run_chezmoi("apply", "--", str(target))
        first = target.read_text()
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertIn("Keep my custom rule.", first)
        self.assertIn("`question` tool", first)
        self.assertIn("Before any mutating Git operation", first)
        self.assertIn("at least two candidate commit messages", first)
        self.assertIn("Release Please Conventional Commit", first)
        self.run_chezmoi("apply", "--", str(target))
        self.assertEqual(target.read_text(), first)
        old = first.replace(
            "Before any mutating Git operation (including add, commit, push, rm, reset,\n"
            "clean, checkout, restore, and worktree changes), use `question` to get my\n"
            "explicit authorization for that operation. Read-only Git operations are fine.\n"
            "Before a commit, present at least two candidate commit messages that follow\n"
            "this repo's Release Please Conventional Commit conventions, then ask me to\n"
            "choose one with `question`. Permission prompts do not replace this decision.\n",
            "",
        )
        target.write_text(old)
        self.run_chezmoi("apply", "--", str(target))
        self.assertEqual(target.read_text(), first)

    def test_handoff_snapshot_is_readonly_and_directly_executable(self) -> None:
        self.config.write_text(VALIDATOR.component_config({"opencode"}))
        target = self.destination / ".local/share/agent-skills/handoff/scripts/snapshot.sh"
        target.parent.mkdir(parents=True)
        self.run_chezmoi("apply", "--", str(target))
        self.assertEqual(target.stat().st_mode & 0o777, 0o555)
        env = self.env.copy()
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            env.pop(key, None)
        result = subprocess.run(
            [str(target)], cwd=self.destination, env=env,
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("git: no", result.stdout)

    def test_apply_preserves_local_skills_and_resolves_one_canonical_copy(self) -> None:
        self.config.write_text(VALIDATOR.component_config({"opencode"}))
        for harness in ("agents", "claude"):
            independent = self.destination / f".{harness}/skills/local-example/SKILL.md"
            independent.parent.mkdir(parents=True)
            independent.write_text("Independent local skill\n")
        canonical = self.destination / ".local/share/agent-skills/chezmoi-dotfiles"
        targets = [
            canonical,
            self.destination / ".agents/skills/chezmoi-dotfiles",
            self.destination / ".claude/skills/chezmoi-dotfiles",
            self.destination / ".config/opencode/commands/dotfiles.md",
        ]
        for target in targets:
            target.parent.mkdir(parents=True, exist_ok=True)
        self.run_chezmoi("apply", "--", *(str(path) for path in targets))
        for relative in VALIDATOR.DOTFILES_SKILL_FILES:
            deployed = canonical / relative.replace("readonly_", "")
            source = REPO_ROOT / "home/dot_local/share/agent-skills/chezmoi-dotfiles" / relative
            self.assertEqual(deployed.read_bytes(), source.read_bytes())
            self.assertEqual(deployed.stat().st_mode & 0o222, 0)
        for harness in ("agents", "claude"):
            linked = self.destination / f".{harness}/skills/chezmoi-dotfiles"
            self.assertTrue(linked.is_symlink())
            self.assertEqual(linked.resolve(), canonical.resolve())
            self.assertEqual((linked / "SKILL.md").read_bytes(), (canonical / "SKILL.md").read_bytes())
            independent = self.destination / f".{harness}/skills/local-example/SKILL.md"
            self.assertEqual(independent.read_text(), "Independent local skill\n")


if __name__ == "__main__":
    unittest.main()
