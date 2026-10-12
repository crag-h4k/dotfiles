# tests/test_private_managed_dirs.py
"""Check chezmoi's target modes for opt-in MCP and skill directories."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class PrivateManagedDirsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="private-managed-dirs-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "source"
        self.destination = root / "home"
        self.config = root / "chezmoi.toml"
        self.source.mkdir()
        self.destination.mkdir()
        (self.source / ".chezmoiroot").write_text("home\n")
        (self.source / "home").mkdir()
        shutil.copyfile(REPO / "home/.chezmoiignore", self.source / "home/.chezmoiignore")

        canonical = "dot_local/share/agent-skills"
        for skill in ("caveman", "caveman-review"):
            source = self.source / "home" / canonical / f"private_{skill}"
            source.mkdir(parents=True)
            shutil.copyfile(REPO / "home" / canonical / f"private_{skill}/.keep", source / ".keep")

        starter = "dot_local/share/dotfiles/private_ssh-mcp/readonly_config-starter.toml"
        source = self.source / "home" / starter
        source.parent.mkdir(parents=True)
        shutil.copyfile(REPO / "home" / starter, source)

        externals = []
        for skill in ("caveman", "caveman-review"):
            payload = root / f"{skill}.md"
            payload.write_text(f"---\nname: {skill}\n---\n")
            externals.append(
                f'[".local/share/agent-skills/{skill}/SKILL.md"]\n'
                f'type = "file"\nurl = "{payload.as_uri()}"\n'
            )
        (self.source / "home/.chezmoiexternal.toml").write_text(
            '{{ if dig "components" "ai" "opencode" false . -}}\n'
            + "\n".join(externals)
            + "{{ end -}}\n"
        )

    def chezmoi(self, *args):
        result = subprocess.run(
            ["chezmoi", "--source", str(self.source), "--destination", str(self.destination),
             "--config", str(self.config), "--force", *args],
            env={**os.environ, "HOME": str(self.destination)},
            text=True, capture_output=True,
        )
        if result.returncode:
            self.fail(f"chezmoi {args} failed: {result.stderr.strip()}")
        return result

    def test_repeated_apply_restores_private_directory_modes(self):
        directories = [
            self.destination / ".local/share/agent-skills/caveman",
            self.destination / ".local/share/agent-skills/caveman-review",
            self.destination / ".local/share/dotfiles/ssh-mcp",
        ]
        for directory in directories:
            directory.mkdir(parents=True)
        self.config.write_text("[data.components.ai]\nopencode = true\n")

        for _ in range(2):
            for directory in directories:
                directory.chmod(0o775)
            self.chezmoi("apply")
            self.assertEqual([path.stat().st_mode & 0o777 for path in directories], [0o700] * 3)
            self.assertEqual(self.chezmoi("status").stdout, "")
            for directory in directories[:2]:
                self.assertTrue((directory / "SKILL.md").is_file())
                self.assertFalse((directory / ".keep").exists())

    def test_unselected_opencode_does_not_install_directories(self):
        self.config.write_text("[data.components.ai]\nopencode = false\n")
        self.chezmoi("apply")
        for path in (
            ".local/share/agent-skills/caveman",
            ".local/share/agent-skills/caveman-review",
            ".local/share/dotfiles/ssh-mcp",
        ):
            self.assertFalse((self.destination / path).exists())
