# tests/test_merge_opencode_cli.py
"""Tests for home/dot_config/opencode/modify_private_cli.json.tmpl (chezmoi modify_).

OpenCode V2's Open settings dialog writes ~/.config/opencode/cli.json, so the file is
merge-managed instead of overwritten. These tests pin the ownership contract:

  OWNED   "$schema", attention.notifications/sound = false, keybinds.leader,
          leader.timeout, and the managed "plugins" directives.
  SEEDED  every other default, one leaf key at a time, only when absent.
  KEPT    everything else, including keys this script has never heard of.

The script runs directly for the merge rules. A second group applies it through
real chezmoi in a disposable source, destination, and state to cover first install,
the private mode, TUI edits between applies, and migration from a plain managed file.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).parent.parent
SCRIPT = REPO / "home" / "dot_config" / "opencode" / "modify_private_cli.json.tmpl"

MANAGED_PLUGINS = [
    "-opencode.prompt.footer",
    "-opencode-copilot-statusline.tui",
    "./v2-plugins/statusline",
    "./v2-plugins/agent-catalog",
]

BASELINE = {
    "$schema": "https://opencode.ai/v2/cli.json",
    "theme": {"name": "gud-lucent", "mode": "system"},
    "tabs": {"mode": "on", "scope": "cwd", "layout": "horizontal", "indicators": "status"},
    "keybinds": {
        "leader": "ctrl+g",
        "session.tab.previous": "<leader>h",
        "session.tab.next": "<leader>l",
        "session.list": "<leader>t",
        "session.first": "home",
        "theme.switch": "none",
    },
    "leader": {"timeout": 1500},
    "attention": {"notifications": False, "sound": False},
    "plugins": MANAGED_PLUGINS,
    "session": {
        "sidebar": "hide",
        "permissions": "prompt",
        "verbosity": "high",
        "new_location": "inherit",
        "thinking": "show",
    },
    "animations": True,
    "diffs": {"wrap": "word"},
    "terminal": {"title": True},
}


def merge(current, *, text=False):
    """Run the script on `current` (a dict, or raw text when text=True)."""
    stdin = current if text else json.dumps(current)
    result = subprocess.run(
        [sys.executable, str(SCRIPT)], input=stdin, capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    return result if text else json.loads(result.stdout)


def test_source_has_no_template_syntax():
    # chezmoi renders the .tmpl before running it; this keeps that a no-op.
    assert "{{" not in SCRIPT.read_text()


def test_first_install_writes_the_baseline_in_stable_order():
    result = subprocess.run(
        [sys.executable, str(SCRIPT)], input="", capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == BASELINE
    assert list(json.loads(result.stdout)) == list(BASELINE)
    assert result.stdout.endswith("}\n")


def test_merge_is_idempotent():
    once = merge({})
    assert merge(once) == once
    assert json.dumps(merge(once)) == json.dumps(once)


def test_tui_changes_to_unowned_keys_survive():
    current = merge({})
    current["theme"]["name"] = "tokyonight"
    current["theme"]["mode"] = "dark"
    current["tabs"]["layout"] = "vertical"
    current["session"]["sidebar"] = "auto"
    current["session"]["thinking"] = "hide"
    current["keybinds"]["session.list"] = "<leader>s"
    current["animations"] = False
    current["diffs"]["wrap"] = "none"
    merged = merge(current)
    assert merged == current


def test_unknown_keys_and_groups_survive_in_place():
    current = {
        "highlights": False,
        "cursor": {"style": "line", "blinking": False},
        "mini": {"footer": "hide"},
        "experimental": {"future-flag": True},
        "somethingFromANewerRelease": {"nested": [1, 2]},
        "tabs": {"layout": "vertical", "newTabKey": "x"},
    }
    merged = merge(current)
    for key, value in current.items():
        if key != "tabs":
            assert merged[key] == value
    assert merged["tabs"]["newTabKey"] == "x"
    assert merged["tabs"]["layout"] == "vertical"
    order = list(merged)
    assert order.index("highlights") < order.index("cursor") < order.index("mini")


@pytest.mark.parametrize(
    "path,wrong",
    [
        (("attention", "notifications"), True),
        (("attention", "sound"), True),
        (("keybinds", "leader"), "ctrl+x"),
        (("leader", "timeout"), 2000),
        (("$schema",), "https://opencode.ai/cli.json"),
    ],
)
def test_owned_keys_are_restored(path, wrong):
    current = merge({})
    node = current
    for key in path[:-1]:
        node = node[key]
    node[path[-1]] = wrong
    restored = merge(current)
    expected = BASELINE
    for key in path:
        expected = expected[key]
    node = restored
    for key in path:
        node = node[key]
    assert node == expected


def test_enforcing_attention_leaves_its_other_settings_alone():
    current = {
        "attention": {
            "notifications": True,
            "sound": True,
            "volume": 0.9,
            "sound_pack": "custom",
            "sounds": {"done": "/tmp/done.wav"},
        }
    }
    attention = merge(current)["attention"]
    assert attention["notifications"] is False
    assert attention["sound"] is False
    assert attention["volume"] == 0.9
    assert attention["sound_pack"] == "custom"
    assert attention["sounds"] == {"done": "/tmp/done.wav"}


def test_new_defaults_are_seeded_one_leaf_at_a_time():
    current = {"tabs": {"layout": "vertical"}, "session": {"sidebar": "auto"}}
    merged = merge(current)
    assert merged["tabs"]["layout"] == "vertical"
    assert merged["tabs"]["mode"] == "on"
    assert merged["tabs"]["scope"] == "cwd"
    assert merged["session"]["sidebar"] == "auto"
    assert merged["session"]["permissions"] == "prompt"
    assert list(merged["tabs"])[0] == "layout"


@pytest.mark.parametrize(
    "tabs",
    [{"enabled": True}, {"enabled": False}],
)
def test_legacy_tabs_enabled_suppresses_seeding_tabs_mode(tabs):
    merged = merge({"tabs": dict(tabs)})
    assert merged["tabs"]["enabled"] is tabs["enabled"]
    assert "mode" not in merged["tabs"]
    assert merged["tabs"]["layout"] == "horizontal"


def test_tabs_mode_from_the_tui_is_kept_and_enabled_is_not_added():
    merged = merge({"tabs": {"mode": "off"}})
    assert merged["tabs"]["mode"] == "off"
    assert "enabled" not in merged["tabs"]


def test_both_tab_keys_are_left_as_written():
    merged = merge({"tabs": {"enabled": True, "mode": "off"}})
    assert merged["tabs"]["enabled"] is True
    assert merged["tabs"]["mode"] == "off"


def test_null_and_wrong_typed_groups_become_objects():
    merged = merge({"attention": None, "tabs": None, "plugins": None, "theme": "x"})
    assert merged["attention"] == {"notifications": False, "sound": False}
    assert merged["tabs"]["mode"] == "on"
    assert merged["theme"] == {"name": "gud-lucent", "mode": "system"}
    assert merged["plugins"] == MANAGED_PLUGINS


def test_explicit_null_leaf_counts_as_set_and_is_not_reseeded():
    merged = merge({"diffs": {"wrap": None}})
    assert merged["diffs"]["wrap"] is None


def test_schema_is_moved_to_the_front_when_missing():
    merged = merge({"theme": {"name": "x"}, "tabs": {"layout": "vertical"}})
    assert next(iter(merged)) == "$schema"
    assert list(merged)[1:3] == ["theme", "tabs"]


def test_plugin_directives_and_local_entries_are_preserved_in_order():
    local = {"package": "./plugins/status", "options": {"compact": True}}
    current = {
        "plugins": [
            "*",
            "./v2-plugins/local/reviewer",
            "./v2-plugins/statusline",
            local,
            "-dotfiles.agent-catalog",
        ]
    }
    plugins = merge(current)["plugins"]
    assert plugins[:5] == current["plugins"]
    assert plugins[5:] == [
        "-opencode.prompt.footer",
        "-opencode-copilot-statusline.tui",
        "./v2-plugins/agent-catalog",
    ]
    assert plugins[3] is not local and plugins[3] == local


def test_removed_managed_plugin_is_added_back_at_the_end():
    plugins = merge({"plugins": ["./v2-plugins/statusline", "./v2-plugins/local/x"]})["plugins"]
    assert plugins == [
        "./v2-plugins/statusline",
        "./v2-plugins/local/x",
        "-opencode.prompt.footer",
        "-opencode-copilot-statusline.tui",
        "./v2-plugins/agent-catalog",
    ]


def test_object_form_managed_plugin_counts_as_present_and_keeps_options():
    entry = {"package": "./v2-plugins/statusline", "options": {"compact": True}}
    plugins = merge({"plugins": [entry]})["plugins"]
    assert plugins.count(entry) == 1
    assert sum(1 for p in plugins if isinstance(p, dict)) == 1
    assert [p for p in plugins if isinstance(p, str)] == [
        "-opencode.prompt.footer",
        "-opencode-copilot-statusline.tui",
        "./v2-plugins/agent-catalog",
    ]


def test_plugins_are_not_duplicated_on_reapply():
    once = merge({"plugins": ["./v2-plugins/local/x"]})
    assert merge(once)["plugins"] == once["plugins"]
    assert len(once["plugins"]) == len(set(map(json.dumps, once["plugins"])))


@pytest.mark.parametrize("raw", ["{not json", "[]", '"text"', "42", "null"])
def test_unparseable_or_non_object_input_is_left_unchanged(raw):
    result = merge(raw, text=True)
    assert result.stdout == raw
    assert "leaving cli.json unchanged" in result.stderr


def test_blank_input_is_a_first_install():
    for raw in ("", "  \n"):
        assert json.loads(merge(raw, text=True).stdout) == BASELINE


pytestmark_chezmoi = pytest.mark.skipif(
    shutil.which("chezmoi") is None, reason="chezmoi not installed"
)


class Sandbox:
    """A disposable chezmoi source, destination, config, and state."""

    def __init__(self, root: Path):
        self.root = root
        self.home = root / "home"
        self.home.mkdir()
        (root / "chezmoi.toml").write_text("[data]\n")
        self.target = self.home / ".config" / "opencode" / "cli.json"
        self.override = self.home / ".config" / "opencode" / "cli.override.json"

    def source(self, name: str, filename: str, content: str) -> Path:
        source = self.root / name
        directory = source / "dot_config" / "opencode"
        directory.mkdir(parents=True)
        (directory / filename).write_text(content)
        return source

    def chezmoi(self, source: Path, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [
                "chezmoi",
                "--source", str(source),
                "--destination", str(self.home),
                "--config", str(self.root / "chezmoi.toml"),
                "--persistent-state", str(self.root / "state.boltdb"),
                "--no-tty",
                *args,
            ],
            capture_output=True,
            text=True,
        )

    def tui_edit(self, **changes):
        data = json.loads(self.target.read_text())
        for dotted, value in changes.items():
            node = data
            *parents, leaf = dotted.split(".")
            for key in parents:
                node = node.setdefault(key, {})
            node[leaf] = value
        self.target.write_text(json.dumps(data, indent=4))


@pytest.fixture
def sandbox(tmp_path):
    box = Sandbox(tmp_path)
    box.merge_source = box.source("merge", SCRIPT.name, SCRIPT.read_text())
    box.merge_source_script = box.merge_source / "dot_config" / "opencode" / SCRIPT.name
    box.merge_source_script.chmod(0o755)
    return box


@pytestmark_chezmoi
def test_chezmoi_first_install_is_private_and_matches_the_baseline(sandbox):
    result = sandbox.chezmoi(sandbox.merge_source, "apply")
    assert result.returncode == 0, result.stderr
    assert json.loads(sandbox.target.read_text()) == BASELINE
    assert sandbox.target.stat().st_mode & 0o777 == 0o600


@pytestmark_chezmoi
def test_chezmoi_reapply_after_tui_edits_keeps_them_without_a_prompt(sandbox):
    assert sandbox.chezmoi(sandbox.merge_source, "apply").returncode == 0
    sandbox.tui_edit(
        **{
            "theme.name": "tokyonight",
            "tabs.layout": "vertical",
            "highlights": False,
            "attention.notifications": True,
            "keybinds.leader": "ctrl+x",
        }
    )
    result = sandbox.chezmoi(sandbox.merge_source, "apply")
    assert result.returncode == 0, result.stderr
    assert "changed since chezmoi last wrote" not in result.stderr + result.stdout
    data = json.loads(sandbox.target.read_text())
    assert data["theme"]["name"] == "tokyonight"
    assert data["tabs"]["layout"] == "vertical"
    assert data["highlights"] is False
    assert data["attention"]["notifications"] is False
    assert data["keybinds"]["leader"] == "ctrl+g"
    assert sandbox.target.stat().st_mode & 0o777 == 0o600
    assert sandbox.chezmoi(sandbox.merge_source, "diff").stdout == ""


@pytestmark_chezmoi
def test_chezmoi_updated_managed_default_reaches_an_existing_host(sandbox):
    assert sandbox.chezmoi(sandbox.merge_source, "apply").returncode == 0
    sandbox.tui_edit(**{"leader.timeout": 900})
    data = json.loads(sandbox.target.read_text())
    del data["diffs"]
    sandbox.target.write_text(json.dumps(data))
    assert sandbox.chezmoi(sandbox.merge_source, "apply").returncode == 0
    data = json.loads(sandbox.target.read_text())
    assert data["leader"]["timeout"] == 1500
    assert data["diffs"] == {"wrap": "word"}


@pytestmark_chezmoi
def test_chezmoi_migrates_a_previously_plain_managed_file(sandbox):
    plain = sandbox.source("plain", "private_cli.json", json.dumps(BASELINE, indent=2) + "\n")
    assert sandbox.chezmoi(plain, "apply").returncode == 0
    sandbox.tui_edit(**{"theme.name": "tokyonight", "tabs.layout": "vertical", "cursor": {"style": "line"}})
    result = sandbox.chezmoi(sandbox.merge_source, "apply")
    assert result.returncode == 0, result.stderr
    data = json.loads(sandbox.target.read_text())
    assert data["theme"]["name"] == "tokyonight"
    assert data["tabs"]["layout"] == "vertical"
    assert data["cursor"] == {"style": "line"}
    assert data["attention"] == {"notifications": False, "sound": False}
    assert sandbox.target.stat().st_mode & 0o777 == 0o600


@pytestmark_chezmoi
def test_chezmoi_leaves_the_local_override_untouched_and_unmerged(sandbox):
    override = '{"session":{"sidebar":"auto"},"plugins":["./v2-plugins/local/x"]}\n'
    sandbox.override.parent.mkdir(parents=True)
    sandbox.override.write_text(override)
    result = sandbox.chezmoi(sandbox.merge_source, "apply")
    assert result.returncode == 0, result.stderr
    assert sandbox.override.read_text() == override
    data = json.loads(sandbox.target.read_text())
    assert data["session"]["sidebar"] == "hide"
    assert data["plugins"] == MANAGED_PLUGINS
