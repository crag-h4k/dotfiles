# tests/test_merge_opencode_cli.py
"""Tests for home/dot_config/opencode/modify_private_cli.json.tmpl (chezmoi modify_).

OpenCode V2's Open settings dialog writes ~/.config/opencode/cli.json, so the file is
merge-managed instead of overwritten. These tests pin the ownership contract:

  OWNED   "$schema", attention.notifications/sound = false, keybinds.leader,
          leader.timeout, the managed "plugins" directives, and their npm pins.
  SEEDED  every other default and managed plugin option, one leaf key at a time,
          only when absent.
  KEPT    everything else, including keys this script has never heard of.

The template is rendered once through chezmoi, then the script runs directly for
the merge rules. A second group applies it through real chezmoi in a disposable
source, destination, and state to cover first install, the private mode, TUI edits
between applies, and migration from a plain managed file.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).parent.parent
SCRIPT = REPO / "home" / "dot_config" / "opencode" / "modify_private_cli.json.tmpl"

pytestmark = pytest.mark.skipif(
    shutil.which("chezmoi") is None, reason="chezmoi not installed"
)

PILLBOX_PIN = "opencode-pillbox-statusline@latest"
SIDEQUEST_PIN = "opencode-sidequest@latest"
YELLOW = ["hue.yellow", "feedback.warning"]
CYAN = ["hue.cyan", "hue.accent"]
PILLBOX = {
    "package": PILLBOX_PIN,
    "options": {
        "pills": {
            "git": {"dirtyAccent": YELLOW},
            "identity": {"effortColor": YELLOW},
            "provider": {"warning": YELLOW},
            "spinner": {"accent": CYAN},
            "elapsed": {"accent": CYAN},
            "context": {"accent": CYAN},
            "tier": {"ramp": "value"},
        },
    },
}

SIDEQUEST = {"package": SIDEQUEST_PIN, "options": {"focusKey": "<leader>p"}}

MANAGED_PLUGINS = [
    "-opencode.prompt.footer",
    "./v2-plugins/agent-catalog",
    "./v2-plugins/demo",
    PILLBOX,
    SIDEQUEST,
]

# What the previous dotfiles release wrote for a fresh host.
RETIRED_DEFAULT_PLUGINS = [
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
        "session.sidebar.toggle": "none",
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


def render(directory: Path, data: str = "") -> Path:
    """Render the modify_ template the way chezmoi will, return the script path."""
    config = directory / "chezmoi.toml"
    config.write_text("[data]\n" + data)
    out = subprocess.run(
        ["chezmoi", "execute-template", "--source", str(REPO), "--config", str(config)],
        stdin=SCRIPT.open(), capture_output=True, text=True, check=True,
    ).stdout
    path = directory / "merge.py"
    path.write_text(out)
    return path


@pytest.fixture(scope="module")
def script(tmp_path_factory) -> Path:
    return render(tmp_path_factory.mktemp("opencode-cli-merge"))


def merge(script, current, *, text=False):
    """Run the script on `current` (a dict, or raw text when text=True)."""
    stdin = current if text else json.dumps(current)
    result = subprocess.run(
        [sys.executable, str(script)], input=stdin, capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    return result if text else json.loads(result.stdout)


def pillbox_entries(plugins):
    return [p for p in plugins if isinstance(p, dict)
            and str(p.get("package", "")).startswith("opencode-pillbox-statusline")]


def test_tier_icon_ramp_follows_the_chezmoi_data_key(tmp_path):
    heat = render(tmp_path, 'tierIcons = "heat"\n')
    plugins = merge(heat, {})["plugins"]
    assert pillbox_entries(plugins)[0]["options"]["pills"]["tier"] == {"ramp": "heat"}


def test_tier_icon_ramp_is_owned_by_the_data_key_on_every_apply(script, tmp_path):
    # Changing tierIcons after the first apply must still take effect, and a
    # cli.json edit to the ramp is reasserted; the tier pill's other options survive.
    existing = {"package": PILLBOX_PIN, "options": {"pills": {"tier": {"ramp": "value", "enabled": False}}}}
    heat = render(tmp_path, 'tierIcons = "heat"\n')
    tier = pillbox_entries(merge(heat, {"plugins": [existing]})["plugins"])[0]["options"]["pills"]["tier"]
    assert tier == {"ramp": "heat", "enabled": False}
    edited = {"package": PILLBOX_PIN, "options": {"pills": {"tier": {"ramp": "heat"}}}}
    tier = pillbox_entries(merge(script, {"plugins": [edited]})["plugins"])[0]["options"]["pills"]["tier"]
    assert tier == {"ramp": "value"}


def test_first_install_writes_the_baseline_in_stable_order(script):
    result = subprocess.run(
        [sys.executable, str(script)], input="", capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == BASELINE
    assert list(json.loads(result.stdout)) == list(BASELINE)
    assert result.stdout.endswith("}\n")


def test_merge_is_idempotent(script):
    once = merge(script, {})
    assert merge(script, once) == once
    assert json.dumps(merge(script, once)) == json.dumps(once)


def test_tui_changes_to_unowned_keys_survive(script):
    current = merge(script, {})
    current["theme"]["name"] = "tokyonight"
    current["theme"]["mode"] = "dark"
    current["tabs"]["layout"] = "vertical"
    current["session"]["sidebar"] = "auto"
    current["session"]["thinking"] = "hide"
    current["keybinds"]["session.list"] = "<leader>s"
    current["animations"] = False
    current["diffs"]["wrap"] = "none"
    merged = merge(script, current)
    assert merged == current


@pytest.mark.parametrize("binding,expected", [
    ("<leader>b", "none"),
    (["<leader>b"], "none"),
    ("alt+b", "alt+b"),
    (["alt+b", "ctrl+b"], ["alt+b", "ctrl+b"]),
    (False, False),
    ("none", "none"),
])
def test_sidequest_frees_only_the_stock_sidebar_binding(script, binding, expected):
    current = {"keybinds": {
        "session.sidebar.toggle": binding,
        "session.child.next": "right",
        "session.tab.previous": "alt+h",
    }}
    once = merge(script, current)
    keys = once["keybinds"]
    assert keys["session.sidebar.toggle"] == expected
    assert keys["leader"] == "ctrl+g"
    assert keys["session.child.next"] == "right"
    assert keys["session.tab.previous"] == "alt+h"
    assert "sidequest.dag.focus" not in keys
    assert merge(script, once) == once


def test_unknown_keys_and_groups_survive_in_place(script):
    current = {
        "highlights": False,
        "cursor": {"style": "line", "blinking": False},
        "mini": {"footer": "hide"},
        "experimental": {"future-flag": True},
        "somethingFromANewerRelease": {"nested": [1, 2]},
        "tabs": {"layout": "vertical", "newTabKey": "x"},
    }
    merged = merge(script, current)
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
def test_owned_keys_are_restored(script, path, wrong):
    current = merge(script, {})
    node = current
    for key in path[:-1]:
        node = node[key]
    node[path[-1]] = wrong
    restored = merge(script, current)
    expected = BASELINE
    for key in path:
        expected = expected[key]
    node = restored
    for key in path:
        node = node[key]
    assert node == expected


def test_enforcing_attention_leaves_its_other_settings_alone(script):
    current = {
        "attention": {
            "notifications": True,
            "sound": True,
            "volume": 0.9,
            "sound_pack": "custom",
            "sounds": {"done": "/tmp/done.wav"},
        }
    }
    attention = merge(script, current)["attention"]
    assert attention["notifications"] is False
    assert attention["sound"] is False
    assert attention["volume"] == 0.9
    assert attention["sound_pack"] == "custom"
    assert attention["sounds"] == {"done": "/tmp/done.wav"}


def test_new_defaults_are_seeded_one_leaf_at_a_time(script):
    current = {"tabs": {"layout": "vertical"}, "session": {"sidebar": "auto"}}
    merged = merge(script, current)
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
def test_legacy_tabs_enabled_suppresses_seeding_tabs_mode(script, tabs):
    merged = merge(script, {"tabs": dict(tabs)})
    assert merged["tabs"]["enabled"] is tabs["enabled"]
    assert "mode" not in merged["tabs"]
    assert merged["tabs"]["layout"] == "horizontal"


def test_tabs_mode_from_the_tui_is_kept_and_enabled_is_not_added(script):
    merged = merge(script, {"tabs": {"mode": "off"}})
    assert merged["tabs"]["mode"] == "off"
    assert "enabled" not in merged["tabs"]


def test_both_tab_keys_are_left_as_written(script):
    merged = merge(script, {"tabs": {"enabled": True, "mode": "off"}})
    assert merged["tabs"]["enabled"] is True
    assert merged["tabs"]["mode"] == "off"


def test_null_and_wrong_typed_groups_become_objects(script):
    merged = merge(script, {"attention": None, "tabs": None, "plugins": None, "theme": "x"})
    assert merged["attention"] == {"notifications": False, "sound": False}
    assert merged["tabs"]["mode"] == "on"
    assert merged["theme"] == {"name": "gud-lucent", "mode": "system"}
    assert merged["plugins"] == MANAGED_PLUGINS


def test_explicit_null_leaf_counts_as_set_and_is_not_reseeded(script):
    merged = merge(script, {"diffs": {"wrap": None}})
    assert merged["diffs"]["wrap"] is None


def test_schema_is_moved_to_the_front_when_missing(script):
    merged = merge(script, {"theme": {"name": "x"}, "tabs": {"layout": "vertical"}})
    assert next(iter(merged)) == "$schema"
    assert list(merged)[1:3] == ["theme", "tabs"]


def test_plugin_directives_and_local_entries_are_preserved_in_order(script):
    local = {"package": "./plugins/status", "options": {"compact": True}}
    current = {
        "plugins": [
            "*",
            "./v2-plugins/local/reviewer",
            "./v2-plugins/demo",
            local,
            "-dotfiles.agent-catalog",
        ]
    }
    plugins = merge(script, current)["plugins"]
    assert plugins[:5] == current["plugins"]
    assert plugins[5:] == [
        "-opencode.prompt.footer",
        "./v2-plugins/agent-catalog",
        PILLBOX,
        SIDEQUEST,
    ]
    assert plugins[3] is not local and plugins[3] == local


def test_removed_managed_plugin_is_added_back_at_the_end(script):
    plugins = merge(script, {"plugins": ["./v2-plugins/demo", "./v2-plugins/local/x"]})["plugins"]
    assert plugins == [
        "./v2-plugins/demo",
        "./v2-plugins/local/x",
        "-opencode.prompt.footer",
        "./v2-plugins/agent-catalog",
        PILLBOX,
        SIDEQUEST,
    ]


def test_object_form_managed_plugin_counts_as_present_and_keeps_options(script):
    entry = {"package": "./v2-plugins/agent-catalog", "options": {"compact": True}}
    plugins = merge(script, {"plugins": [entry]})["plugins"]
    assert plugins.count(entry) == 1
    assert plugins == [entry, "-opencode.prompt.footer", "./v2-plugins/demo", PILLBOX, SIDEQUEST]


def test_plugins_are_not_duplicated_on_reapply(script):
    once = merge(script, {"plugins": ["./v2-plugins/local/x"]})
    assert merge(script, once)["plugins"] == once["plugins"]
    assert len(once["plugins"]) == len(set(map(json.dumps, once["plugins"])))
    assert len(pillbox_entries(once["plugins"])) == 1


def test_retired_footer_entries_are_stripped_from_an_existing_host(script):
    current = {"plugins": [
        *RETIRED_DEFAULT_PLUGINS,
        {"package": "./v2-plugins/statusline", "options": {"compact": True}},
        "./v2-plugins/local/statusline",
        "-dotfiles.statusline",
    ]}
    once = merge(script, current)
    assert once["plugins"] == [
        "-opencode.prompt.footer",
        "./v2-plugins/agent-catalog",
        "./v2-plugins/local/statusline",
        "-dotfiles.statusline",
        "./v2-plugins/demo",
        PILLBOX,
        SIDEQUEST,
    ]
    assert merge(script, once) == once


def test_previous_fresh_install_converges_on_the_new_baseline(script):
    previous = dict(BASELINE, plugins=RETIRED_DEFAULT_PLUGINS)
    assert merge(script, previous) == BASELINE


def test_pillbox_pin_bump_rewrites_the_spec_and_keeps_user_options(script, tmp_path):
    edited = {
        "package": PILLBOX_PIN,
        "options": {
            "preset": "minimal",
            "pills": {
                "git": {"dirtyAccent": "#ff5555", "maxWidth": 20},
                "cost": {"enabled": False},
            },
        },
        "futureField": "keep this too",
    }
    current = {"plugins": ["./v2-plugins/local/x", edited, "-pillbox.tui"]}
    bumped = tmp_path / "bumped.py"
    bumped.write_text(Path(script).read_text().replace(PILLBOX_PIN, "opencode-pillbox-statusline@0.2.0"))
    plugins = merge(bumped, current)["plugins"]
    assert len(pillbox_entries(plugins)) == 1
    assert plugins[0] == "./v2-plugins/local/x"
    assert plugins[2] == "-pillbox.tui"
    entry = plugins[1]
    assert list(entry) == ["package", "options", "futureField"]
    assert entry["package"] == "opencode-pillbox-statusline@0.2.0"
    assert entry["futureField"] == "keep this too"
    options = entry["options"]
    assert options["preset"] == "minimal"
    assert options["pills"]["git"] == {"dirtyAccent": "#ff5555", "maxWidth": 20}
    assert options["pills"]["cost"] == {"enabled": False}
    # Options the user never set are seeded from the managed defaults.
    assert options["pills"]["spinner"] == {"accent": CYAN}
    assert options["pills"]["tier"] == {"ramp": "value"}


@pytest.mark.parametrize("existing", [
    "opencode-pillbox-statusline",
    "opencode-pillbox-statusline@0.0.9",
    {"package": "opencode-pillbox-statusline@latest"},
])
def test_any_version_of_pillbox_becomes_the_single_managed_entry(script, existing):
    plugins = merge(script, {"plugins": ["./v2-plugins/local/x", existing]})["plugins"]
    assert plugins[:2] == ["./v2-plugins/local/x", PILLBOX]
    assert len(pillbox_entries(plugins)) == 1


@pytest.mark.parametrize("existing", [
    "opencode-sidequest",
    "opencode-sidequest@0.0.9",
    {"package": "opencode-sidequest@latest", "options": {"futureOption": True}},
])
def test_sidequest_pin_and_focus_option_converge_without_duplicate_entries(script, existing):
    current = {"plugins": [existing, "-sidequest.tui"]}
    once = merge(script, current)
    entry = once["plugins"][0]
    assert entry["package"] == SIDEQUEST_PIN
    assert entry["options"]["focusKey"] == "<leader>p"
    if isinstance(existing, dict):
        assert entry["options"]["futureOption"] is True
    assert once["plugins"][1] == "-sidequest.tui"
    assert sum(p.get("package") == SIDEQUEST_PIN for p in once["plugins"] if isinstance(p, dict)) == 1
    assert merge(script, once) == once


def test_sidequest_pin_bump_preserves_custom_focus_and_other_options(script, tmp_path):
    current = {"plugins": [{
        "package": SIDEQUEST_PIN,
        "options": {"focusKey": "alt+p", "futureOption": {"keep": True}},
    }, "-sidequest.tui"]}
    bumped = tmp_path / "bumped.py"
    bumped.write_text(Path(script).read_text().replace(SIDEQUEST_PIN, "opencode-sidequest@0.2.0"))
    once = merge(bumped, current)
    assert once["plugins"][0] == {
        "package": "opencode-sidequest@0.2.0",
        "options": {"focusKey": "alt+p", "futureOption": {"keep": True}},
    }
    assert once["plugins"][1] == "-sidequest.tui"
    assert merge(bumped, once) == once


def test_pillbox_lookalikes_and_controls_are_local_entries(script):
    local = [
        "opencode-pillbox-statusline-fork@1.0.0",
        "@example/opencode-pillbox-statusline@1.0.0",
        "./opencode-pillbox-statusline",
        "/opt/example/opencode-pillbox-statusline",
        "-pillbox.tui",
        "-opencode-pillbox-statusline",
    ]
    plugins = merge(script, {"plugins": list(local)})["plugins"]
    assert plugins[:len(local)] == local
    assert plugins[len(local):] == MANAGED_PLUGINS


@pytest.mark.parametrize("raw", ["{not json", "[]", '"text"', "42", "null"])
def test_unparseable_or_non_object_input_is_left_unchanged(script, raw):
    result = merge(script, raw, text=True)
    assert result.stdout == raw
    assert "leaving cli.json unchanged" in result.stderr


def test_blank_input_is_a_first_install(script):
    for raw in ("", "  \n"):
        assert json.loads(merge(script, raw, text=True).stdout) == BASELINE


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


def test_chezmoi_first_install_is_private_and_matches_the_baseline(sandbox):
    result = sandbox.chezmoi(sandbox.merge_source, "apply")
    assert result.returncode == 0, result.stderr
    assert json.loads(sandbox.target.read_text()) == BASELINE
    assert sandbox.target.stat().st_mode & 0o777 == 0o600


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
