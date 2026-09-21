# tests/test_agent_skills.py
"""Regression tests for the public cross-harness agent-skill contract."""

from __future__ import annotations

import importlib.util
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
        (canonical / "readonly_PROVENANCE.md").touch()
        (canonical / "humanizer/readonly_SKILL.md").touch()
        (canonical / "humanizer/agents/readonly_openai.yaml").touch()
        return root

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


if __name__ == "__main__":
    unittest.main()
