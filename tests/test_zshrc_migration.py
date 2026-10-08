# tests/test_zshrc_migration.py
"""Guard narrowly scoped PATH-tail migration with disposable chezmoi state."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class ZshrcMigrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.source = self.repo / "home/dot_zshrc"
        self.home = self.root / "home"
        self.home.mkdir()
        self.source.parent.mkdir(parents=True)
        self.source.write_text("# fixture zshrc\nexport EDITOR=nvim\n")
        self.source.with_name("dot_zshenv").write_text('export PATH=$HOME/.local/bin:$PATH\n')
        self.target = self.home / ".zshrc"
        self.target.write_bytes(self.source.read_bytes())
        (self.home / ".zshenv").write_bytes(self.source.with_name("dot_zshenv").read_bytes())
        self.backup = self.root / "backup"
        self.backup.mkdir()
        spec = importlib.util.spec_from_file_location("normalize_zshrc", REPO / "scripts/normalize-zshrc.py")
        self.helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.helper)
        self.original = self.source.read_bytes() + ("\n# Example Agent command\n" + self.helper.PATH_GUARD + "\n").encode()

    def tearDown(self):
        self.temp.cleanup()

    def seed_tail(self):
        self.target.write_bytes(self.original)
        (self.backup / ".zshrc").write_bytes(self.original)

    def test_known_guard_is_removed_only_after_its_matching_backup(self):
        self.seed_tail()
        self.target.chmod(0o640)
        self.assertTrue(self.helper.normalize(self.source, self.target, self.backup))
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o640)
        self.assertEqual((self.backup / ".zshrc").read_bytes(), self.original)
        self.assertFalse(self.helper.normalize(self.source, self.target, self.backup))

    def test_missing_or_stale_backup_stops_before_changing_target(self):
        self.target.write_bytes(self.original)
        with self.assertRaisesRegex(ValueError, "matching pre-apply backup"):
            self.helper.normalize(self.source, self.target, self.backup)
        self.assertEqual(self.target.read_bytes(), self.original)
        (self.backup / ".zshrc").write_bytes(self.source.read_bytes())
        with self.assertRaises(ValueError):
            self.helper.normalize(self.source, self.target, self.backup)

    def test_unrecognized_edits_and_changed_zshenv_are_preserved(self):
        for content in (self.original + b"export CUSTOM=fixture\n",
                        self.original.replace(b"EDITOR=nvim", b"EDITOR=vi"),
                        self.original.replace(b"# Example Agent command", b"# important local note")):
            with self.subTest(content=content):
                self.target.write_bytes(content)
                self.assertFalse(self.helper.normalize(self.source, self.target, self.backup))
                self.assertEqual(self.target.read_bytes(), content)
        self.seed_tail()
        (self.home / ".zshenv").write_text("# local env\n")
        self.assertFalse(self.helper.normalize(self.source, self.target, self.backup))
        self.assertEqual(self.target.read_bytes(), self.original)

    def test_symlinked_target_is_not_replaced(self):
        self.target.unlink()
        self.target.symlink_to(self.source)
        self.assertFalse(self.helper.normalize(self.source, self.target, self.backup))
        self.assertTrue(self.target.is_symlink())

    def prepare_chezmoi(self):
        (self.repo / ".chezmoiroot").write_text("home\n")
        scripts = self.repo / "scripts"
        scripts.mkdir()
        shutil.copyfile(REPO / "scripts/normalize-zshrc.py", scripts / "normalize-zshrc.py")
        hooks = self.source.parent / ".chezmoiscripts"
        hooks.mkdir()
        shutil.copyfile(REPO / "home/.chezmoiscripts/run_before_00-backup.sh", hooks / "run_before_00-backup.sh")
        config = self.home / ".config/chezmoi/chezmoi.toml"
        config.parent.mkdir(parents=True)
        config.write_text('sourceDir = "' + str(self.repo) + '"\n')
        env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / ".config"),
                   XDG_DATA_HOME=str(self.root / "data"), XDG_CACHE_HOME=str(self.root / "cache"),
                   XDG_STATE_HOME=str(self.root / "state"))
        return env

    def apply(self, env):
        return subprocess.run(["chezmoi", "--no-tty", "apply"], env=env, cwd=self.repo,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)

    def test_real_apply_removes_known_tail_without_a_conflict_prompt(self):
        env = self.prepare_chezmoi()
        first = self.apply(env)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.target.write_bytes(self.original)
        result = self.apply(env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        snapshots = list((self.home / ".dotfiles-backup").glob("*/.zshrc"))
        self.assertGreaterEqual(len(snapshots), 2)
        self.assertTrue(any(path.read_bytes() == self.original for path in snapshots))
        self.assertIn("redundant .zshrc PATH tail", result.stdout)

    def test_real_apply_keeps_unrelated_local_edits_as_conflicts(self):
        env = self.prepare_chezmoi()
        self.assertEqual(self.apply(env).returncode, 0)
        modified = self.source.read_bytes() + b"export CUSTOM=fixture\n"
        self.target.write_bytes(modified)
        result = self.apply(env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_bytes(), modified)

    def test_ignored_zshrc_is_not_migrated(self):
        env = self.prepare_chezmoi()
        self.target.write_bytes(self.original)
        (self.source.parent / ".chezmoiignore").write_text(".zshrc\n")
        result = self.apply(env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
