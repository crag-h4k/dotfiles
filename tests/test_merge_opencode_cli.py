# tests/test_merge_opencode_cli.py
"""Tests for home/dot_config/opencode/modify_private_cli.json.tmpl (chezmoi modify_).

OpenCode V2's Open settings dialog writes ~/.config/opencode/cli.json, so the file is
merge-managed instead of overwritten. These tests pin the ownership contract:

  OWNED   "$schema", attention.notifications/sound = false, keybinds.leader,
          leader.timeout, the tab navigation keys and the pane and terminal
          defaults they displace, the managed "plugins" directives, and their
          npm pins.
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

ATTENTION_PATH = "./v2-plugins/attention-tabs"
ATTENTION = {"package": ATTENTION_PATH, "options": {"sort": False, "jumpKey": "<leader>z"}}
# The voice plugin is built from source into ~/.config/opencode/v2-plugins/talk, so it
# is a local path. Its id is opencode-talk, which is also its npm name.
TALK_PATH = "./v2-plugins/talk"
TALK = {
    "package": TALK_PATH,
    "options": {"keybind": "<leader>v", "onDeviceOnly": True, "autoSend": False},
}
VOICE_ON = "[data.components.ai]\nopencode = true\nvoice = true\n"
VOICE_OFF = "[data.components.ai]\nopencode = true\nvoice = false\n"

MANAGED_PLUGINS = [
    "-opencode.prompt.footer",
    "./v2-plugins/agent-catalog",
    "./v2-plugins/demo",
    PILLBOX,
    SIDEQUEST,
    ATTENTION,
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
        "leader": "ctrl+x",
        "session.tab.previous": "<leader>h,<leader>left,<leader>k,<leader>up",
        "session.tab.next": "<leader>l,<leader>right,<leader>j,<leader>down",
        "session.list": "<leader>t",
        "agent.cycle": "shift+tab",
        "session.first": "home,<leader>f",
        "session.sidebar.toggle": "none",
        "pane.focus.left": "none",
        "pane.focus.right": "none",
        "terminal.select": "none",
        "terminal.close": "none",
        "terminal.toggle": "none",
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

# ---- Prompt submit keys: Enter inserts a newline, Option+Enter submits ---------
# Seeded only; see the matching block in modify_private_cli.json.tmpl. Kept apart
# from BASELINE so it merges cleanly with other keybind work.
PROMPT_KEYS = {
    "input.submit": "super+return,alt+return",
    "input.newline": "return,shift+return,ctrl+return,ctrl+j",
}
BASELINE["keybinds"].update(PROMPT_KEYS)


def render(directory: Path, data: str = "", os_name: str | None = None) -> Path:
    """Render the modify_ template the way chezmoi will, return the script path.

    os_name pins .chezmoi.os, so a test of the macOS-only voice entry gives the same
    answer on a Linux runner.
    """
    config = directory / "chezmoi.toml"
    config.write_text("[data]\n" + data)
    command = ["chezmoi", "execute-template", "--source", str(REPO), "--config", str(config)]
    if os_name:
        command += ["--override-data", json.dumps({"chezmoi": {"os": os_name}})]
    out = subprocess.run(
        command, stdin=SCRIPT.open(), capture_output=True, text=True, check=True,
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
        "session.new": "alt+n",
    }}
    once = merge(script, current)
    keys = once["keybinds"]
    assert keys["session.sidebar.toggle"] == expected
    assert keys["leader"] == "ctrl+x"
    assert keys["session.child.next"] == "right"
    assert keys["session.new"] == "alt+n"
    assert "sidequest.dag.focus" not in keys
    assert merge(script, once) == once


@pytest.mark.parametrize("binding", ["alt+a", ["shift+tab", "alt+a"], {"key": "shift+tab", "fallthrough": True}, False, "none"])
def test_native_agent_cycle_preserves_explicit_bindings(script, binding):
    once = merge(script, {"keybinds": {"agent.cycle": binding}})
    assert once["keybinds"]["agent.cycle"] == binding
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
        (("keybinds", "leader"), "ctrl+g"),
        (("keybinds", "session.tab.previous"), "alt+h"),
        (("keybinds", "session.tab.next"), "alt+l"),
        (("keybinds", "session.first"), "ctrl+g"),
        (("keybinds", "pane.focus.left"), "<leader>left"),
        (("keybinds", "pane.focus.right"), "<leader>right"),
        (("keybinds", "terminal.select"), "<leader>down"),
        (("keybinds", "terminal.close"), "<leader>up"),
        (("keybinds", "terminal.toggle"), "<leader>t"),
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


def test_previous_release_keybinds_move_to_the_default_leader(script):
    previous = {"keybinds": {
        "leader": "ctrl+g",
        "session.tab.previous": "<leader>h",
        "session.tab.next": "<leader>l",
        "session.first": "home",
        "session.list": "<leader>s",
    }}
    keys = merge(script, previous)["keybinds"]
    for action in ("leader", "session.tab.previous", "session.tab.next", "session.first"):
        assert keys[action] == BASELINE["keybinds"][action], action
    assert keys["session.list"] == "<leader>s", "a seeded binding the user changed stays"
    for action in ("pane.focus.left", "pane.focus.right", "terminal.select", "terminal.close", "terminal.toggle"):
        assert keys[action] == "none", action


def test_no_two_managed_actions_share_a_leader_chord():
    chords = {}
    for action, value in BASELINE["keybinds"].items():
        for chord in str(value).split(","):
            if chord.startswith("<leader>"):
                chords.setdefault(chord, []).append(action)
    assert {chord: actions for chord, actions in chords.items() if len(actions) > 1} == {}


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
    assert merged["keybinds"]["agent.cycle"] == "shift+tab"
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
        ATTENTION,
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
        ATTENTION,
    ]


def test_object_form_managed_plugin_counts_as_present_and_keeps_options(script):
    entry = {"package": "./v2-plugins/agent-catalog", "options": {"compact": True}}
    plugins = merge(script, {"plugins": [entry]})["plugins"]
    assert plugins.count(entry) == 1
    assert plugins == [entry, "-opencode.prompt.footer", "./v2-plugins/demo", PILLBOX, SIDEQUEST, ATTENTION]


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
        ATTENTION,
    ]
    assert merge(script, once) == once


def test_previous_fresh_install_converges_on_the_new_baseline(script):
    previous = dict(BASELINE, plugins=RETIRED_DEFAULT_PLUGINS)
    assert merge(script, previous) == BASELINE


def attention_entries(plugins):
    return [p for p in plugins if (p.get("package") if isinstance(p, dict) else p) == ATTENTION_PATH]


def test_attention_tabs_is_managed_by_its_path_with_sorting_seeded_off(script):
    plugins = merge(script, {})["plugins"]
    assert attention_entries(plugins) == [ATTENTION]
    assert plugins[-1] == ATTENTION
    # Only these two are seeded; the rest keep their in-plugin defaults.
    assert set(plugins[-1]["options"]) == {"sort", "jumpKey"}
    assert plugins[-1]["options"]["sort"] is False


@pytest.mark.parametrize("existing", [
    ATTENTION_PATH,
    {"package": ATTENTION_PATH},
    {"package": ATTENTION_PATH, "options": {"sort": True}},
])
def test_attention_tabs_converges_to_one_object_entry_and_is_idempotent(script, existing):
    once = merge(script, {"plugins": ["./v2-plugins/local/x", existing]})
    assert len(attention_entries(once["plugins"])) == 1
    assert once["plugins"][0] == "./v2-plugins/local/x"
    entry = once["plugins"][1]
    assert entry["package"] == ATTENTION_PATH
    assert entry["options"]["jumpKey"] == "<leader>z"
    assert entry["options"]["sort"] is (isinstance(existing, dict) and existing.get("options", {}).get("sort", False))
    assert merge(script, once) == once


def test_a_host_that_turns_sorting_on_keeps_it_and_its_other_options(script):
    edited = {
        "package": ATTENTION_PATH,
        "options": {"sort": True, "jumpKey": "<leader>g", "toast": False, "futureOption": 1},
        "futureField": "keep",
    }
    once = merge(script, {"plugins": [edited]})
    assert once["plugins"][0] == edited
    assert merge(script, once) == once


def test_a_dash_control_for_attention_tabs_survives_the_merge(script):
    plugins = merge(script, {"plugins": ["-dotfiles.attention-tabs"]})["plugins"]
    assert plugins[0] == "-dotfiles.attention-tabs"
    assert attention_entries(plugins) == [ATTENTION]


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


# --- voice: the opt-in dictation plugin (components.ai.voice, macOS) ----------------
#
# The entry is managed only when voice is on, the OS is macOS, and the plugin has been
# built (~/.config/opencode/v2-plugins/talk/tui.js). Every test runs with HOME pointed at
# an empty directory, so the answer never depends on the machine running the suite.

@pytest.fixture(autouse=True)
def fake_home(tmp_path, monkeypatch) -> Path:
    home = tmp_path / "empty-home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    return home


@pytest.fixture
def built(fake_home) -> Path:
    plugin = fake_home / ".config" / "opencode" / "v2-plugins" / "talk"
    plugin.mkdir(parents=True)
    (plugin / "tui.js").write_text("// built plugin\n")
    return plugin


@pytest.fixture(scope="module")
def voice_script(tmp_path_factory) -> Path:
    return render(tmp_path_factory.mktemp("opencode-cli-voice"), VOICE_ON, os_name="darwin")


def run_merge(script, current):
    """Like merge(), but keep stderr, for the not-built notice."""
    result = subprocess.run(
        [sys.executable, str(script)], input=json.dumps(current), capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout), result.stderr


def talk_entries(plugins):
    return [p for p in plugins if isinstance(p, dict) and p.get("package") == TALK_PATH]


def talk_like(entry):
    """Any enabling entry for the voice plugin: its local path or its npm name, any form."""
    name = entry.get("package") if isinstance(entry, dict) else entry
    if not isinstance(name, str) or name.startswith("-"):
        return False
    return name.split("@")[0].endswith(("opencode-talk", "v2-plugins/talk"))


def test_voice_off_leaves_the_baseline_alone(tmp_path):
    for data in ("", VOICE_OFF):
        off = render(tmp_path, data, os_name="darwin")
        assert merge(off, {}) == BASELINE


def test_voice_off_ignores_a_built_plugin(tmp_path, built):
    off = render(tmp_path, VOICE_OFF, os_name="darwin")
    assert merge(off, {}) == BASELINE


def test_voice_on_and_built_appends_the_entry_after_sidequest_and_changes_nothing_else(voice_script, built):
    result = merge(voice_script, {})
    assert result["plugins"] == MANAGED_PLUGINS + [TALK]
    assert {key: value for key, value in result.items() if key != "plugins"} == {
        key: value for key, value in BASELINE.items() if key != "plugins"
    }
    # Pillbox and Sidequest are exactly what they are without voice.
    assert result["plugins"][3] == PILLBOX
    assert result["plugins"][4] == SIDEQUEST


def test_voice_on_off_macos_adds_no_entry(tmp_path, built):
    # The helper builds only on macOS; a persisted voice key elsewhere must not leave a
    # plugin path that cannot load, even if a directory happens to exist.
    linux = render(tmp_path, VOICE_ON, os_name="linux")
    assert merge(linux, {}) == BASELINE


def test_voice_entry_is_appended_to_an_existing_host_in_order(voice_script, built):
    current = {"plugins": ["./v2-plugins/local/x", PILLBOX, "-sidequest.tui", SIDEQUEST]}
    plugins = merge(voice_script, current)["plugins"]
    assert plugins[:4] == current["plugins"]
    assert plugins[4:] == [
        "-opencode.prompt.footer", "./v2-plugins/agent-catalog", "./v2-plugins/demo", ATTENTION, TALK,
    ]


def test_voice_merge_is_idempotent(voice_script, built):
    once = merge(voice_script, {})
    assert merge(voice_script, once) == once
    assert len(talk_entries(once["plugins"])) == 1
    assert json.dumps(merge(voice_script, once)) == json.dumps(once)


def test_voice_options_the_user_set_survive_and_new_ones_arrive(voice_script, built):
    existing = {"package": TALK_PATH, "options": {
        "keybind": "ctrl+y", "autoSend": True, "liveText": False, "silenceStop": 5,
    }}
    entry = talk_entries(merge(voice_script, {"plugins": [existing]})["plugins"])[0]
    assert entry["options"] == {
        "keybind": "ctrl+y", "autoSend": True, "liveText": False, "silenceStop": 5,
        "onDeviceOnly": True,
    }


@pytest.mark.parametrize("wrong", [False, None, "false", 0])
def test_on_device_only_is_reasserted_on_every_apply(voice_script, built, wrong):
    existing = {"package": TALK_PATH, "options": {"onDeviceOnly": wrong, "autoSend": True}}
    entry = talk_entries(merge(voice_script, {"plugins": [existing]})["plugins"])[0]
    assert entry["options"]["onDeviceOnly"] is True
    assert entry["options"]["autoSend"] is True


def test_bare_voice_path_becomes_the_managed_entry(voice_script, built):
    plugins = merge(voice_script, {"plugins": [TALK_PATH]})["plugins"]
    assert talk_entries(plugins) == [TALK]
    assert TALK_PATH not in plugins


def test_voice_keybind_does_not_share_a_chord_with_another_managed_action(voice_script, built):
    chord = TALK["options"]["keybind"]
    taken = {}
    for action, value in BASELINE["keybinds"].items():
        for bound in str(value).split(","):
            taken.setdefault(bound, []).append(action)
    taken.setdefault(SIDEQUEST["options"]["focusKey"], []).append("sidequest focus")
    assert chord.startswith("<leader>")
    assert chord not in taken
    assert merge(voice_script, {})["keybinds"] == BASELINE["keybinds"]


def test_voice_replaces_the_npm_package_with_the_local_build(voice_script, built):
    # The npm tarball leaves out the helper source, so a registry entry is never wanted.
    for stale in ("opencode-talk", "opencode-talk@0.1.1", {"package": "opencode-talk@latest"}):
        plugins = merge(voice_script, {"plugins": ["./v2-plugins/local/x", stale]})["plugins"]
        assert plugins[0] == "./v2-plugins/local/x"
        assert talk_entries(plugins) == [TALK]
        assert [p for p in plugins if talk_like(p)] == [TALK]


def test_voice_opt_out_control_after_the_managed_section_survives(voice_script, built):
    current = {"plugins": [*MANAGED_PLUGINS, TALK, "-opencode-talk"]}
    plugins = merge(voice_script, current)["plugins"]
    assert plugins == [*MANAGED_PLUGINS, TALK, "-opencode-talk"]


# Not built yet: the entry is neither added nor retired, and one line says how to build it.

def test_voice_on_but_not_built_adds_no_entry_and_says_how_to_build(voice_script):
    result, stderr = run_merge(voice_script, {})
    assert result == BASELINE
    assert stderr.count("\n") == 1
    assert "not built" in stderr
    assert "scripts/opencode-talk/build.sh" in stderr


def test_a_hand_added_entry_is_untouched_until_the_plugin_is_built(voice_script):
    hand = [
        TALK_PATH,
        {"package": TALK_PATH, "options": {"keybind": "ctrl+y", "onDeviceOnly": False}},
        "opencode-talk",
        {"package": "opencode-talk@latest", "options": {"autoSend": True}},
    ]
    for entry in hand:
        current = {"plugins": ["./v2-plugins/local/x", entry, "-opencode-talk"]}
        plugins, stderr = run_merge(voice_script, current)
        assert plugins["plugins"][:3] == current["plugins"]
        assert plugins["plugins"][3:] == BASELINE["plugins"]
        assert "not built" in stderr


def test_not_built_merge_is_idempotent_and_keeps_the_notice(voice_script):
    once, first = run_merge(voice_script, {})
    twice, second = run_merge(voice_script, once)
    assert twice == once
    assert first == second


def test_building_the_plugin_adds_the_entry_on_the_next_apply(voice_script, fake_home):
    before, stderr = run_merge(voice_script, {})
    assert "not built" in stderr
    plugin = fake_home / ".config" / "opencode" / "v2-plugins" / "talk"
    plugin.mkdir(parents=True)
    (plugin / "tui.js").write_text("// built\n")
    after, stderr = run_merge(voice_script, before)
    assert stderr == ""
    assert after["plugins"] == MANAGED_PLUGINS + [TALK]


@pytest.mark.parametrize("missing", ["tui.js", "plugin directory"])
def test_a_half_removed_install_counts_as_not_built(voice_script, built, missing):
    if missing == "tui.js":
        (built / "tui.js").unlink()
    else:
        (built / "tui.js").unlink()
        built.rmdir()
    result, stderr = run_merge(voice_script, {})
    assert result == BASELINE
    assert "not built" in stderr


def test_the_notice_is_silent_when_voice_is_off_or_the_input_is_unusable(tmp_path, voice_script):
    off = render(tmp_path, VOICE_OFF, os_name="darwin")
    _, stderr = run_merge(off, {})
    assert stderr == ""
    result = subprocess.run(
        [sys.executable, str(voice_script)], input="{not json", capture_output=True, text=True
    )
    assert result.returncode == 0
    assert "not built" not in result.stderr


@pytest.mark.parametrize("data", ["", VOICE_OFF])
def test_voice_off_removes_every_form_of_the_entry(tmp_path, data):
    # This also removes an entry added by hand: with voice off, the plugin is not wanted.
    stale = [
        TALK_PATH,
        {"package": TALK_PATH, "options": {"keybind": "ctrl+y"}},
        "opencode-talk",
        "opencode-talk@0.1.1",
        {"package": "opencode-talk@latest", "options": {"autoSend": True}},
    ]
    off = render(tmp_path, data, os_name="darwin")
    current = {"plugins": ["./v2-plugins/local/x", *stale, "-opencode-talk", PILLBOX]}
    plugins = merge(off, current)["plugins"]
    assert plugins[:3] == ["./v2-plugins/local/x", "-opencode-talk", PILLBOX]
    assert [p for p in plugins if talk_like(p)] == []
    assert plugins[3:] == [
        "-opencode.prompt.footer", "./v2-plugins/agent-catalog", "./v2-plugins/demo", SIDEQUEST, ATTENTION,
    ]


def test_turning_voice_off_after_it_was_on_converges_on_the_baseline(tmp_path, voice_script, built):
    on = merge(voice_script, {})
    off = render(tmp_path, VOICE_OFF, os_name="darwin")
    assert merge(off, on) == BASELINE


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
            "keybinds.leader": "ctrl+g",
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
    assert data["keybinds"]["leader"] == "ctrl+x"
    assert sandbox.target.stat().st_mode & 0o777 == 0o600
    assert sandbox.chezmoi(sandbox.merge_source, "diff").stdout == ""


def test_chezmoi_updated_managed_default_reaches_an_existing_host(sandbox):
    assert sandbox.chezmoi(sandbox.merge_source, "apply").returncode == 0
    sandbox.tui_edit(**{"leader.timeout": 900})
    data = json.loads(sandbox.target.read_text())
    del data["diffs"]
    del data["keybinds"]["agent.cycle"]
    sandbox.target.write_text(json.dumps(data))
    assert sandbox.chezmoi(sandbox.merge_source, "apply").returncode == 0
    data = json.loads(sandbox.target.read_text())
    assert data["leader"]["timeout"] == 1500
    assert data["diffs"] == {"wrap": "word"}
    assert data["keybinds"]["agent.cycle"] == "shift+tab"


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


# ---- Prompt submit keys: Enter inserts a newline, Option+Enter submits ---------
# input.submit and input.newline bind to any focused textarea; forms, dialogs and
# the autocomplete popup keep acting on Enter. Both are SEEDED, never owned.
def chords(value):
    return set(value.split(","))


def test_enter_makes_a_newline_and_option_enter_submits(script):
    keys = merge(script, {})["keybinds"]
    submit, newline = chords(keys["input.submit"]), chords(keys["input.newline"])
    assert "alt+return" in submit, "Option+Enter, which tmux also delivers as ESC CR"
    assert "super+return" in submit, "Cmd+Enter, for a host that frees it from Ghostty"
    assert "return" in newline and "return" not in submit
    assert {"shift+return", "ctrl+return", "ctrl+j"} <= newline, "the native newline chords stay"
    # A chord on both actions is ambiguous, and Alt+Enter is a newline by default.
    assert submit.isdisjoint(newline)


@pytest.mark.parametrize("action", sorted(PROMPT_KEYS))
@pytest.mark.parametrize("binding", [
    "ctrl+s",
    "return",
    ["ctrl+s", "alt+return"],
    {"key": "ctrl+s", "fallthrough": True},
    "none",
    False,
    None,
])
def test_prompt_keys_a_user_set_are_never_replaced(script, action, binding):
    once = merge(script, {"keybinds": {action: binding}})
    assert once["keybinds"][action] == binding
    assert merge(script, once) == once


def test_prompt_keys_are_seeded_one_at_a_time(script):
    only_submit = merge(script, {"keybinds": {"input.submit": "ctrl+s"}})["keybinds"]
    assert only_submit["input.submit"] == "ctrl+s"
    assert only_submit["input.newline"] == PROMPT_KEYS["input.newline"]
    only_newline = merge(script, {"keybinds": {"input.newline": "ctrl+j"}})["keybinds"]
    assert only_newline["input.newline"] == "ctrl+j"
    assert only_newline["input.submit"] == PROMPT_KEYS["input.submit"]


def test_prompt_keys_leave_unrelated_keybinds_alone(script):
    mine = {
        "prompt.submit": "ctrl+enter",
        "prompt.clear": "ctrl+u",
        "input.move.left": "left",
        "dialog.select.submit": "return",
        "prompt.autocomplete.select": "tab",
        "session.new": "alt+n",
    }
    keys = merge(script, {"keybinds": dict(mine)})["keybinds"]
    for action, binding in mine.items():
        assert keys[action] == binding, action
    assert "prompt.submit" not in merge(script, {})["keybinds"], "no native default to seed"
    for action in ("leader", "session.list", "agent.cycle"):
        assert keys[action] == BASELINE["keybinds"][action], action


def test_chezmoi_prompt_keys_reach_an_existing_host_and_a_user_choice_stays(sandbox):
    assert sandbox.chezmoi(sandbox.merge_source, "apply").returncode == 0
    data = json.loads(sandbox.target.read_text())
    del data["keybinds"]["input.submit"]
    data["keybinds"]["input.newline"] = "ctrl+j"
    sandbox.target.write_text(json.dumps(data))
    result = sandbox.chezmoi(sandbox.merge_source, "apply")
    assert result.returncode == 0, result.stderr
    keys = json.loads(sandbox.target.read_text())["keybinds"]
    assert keys["input.submit"] == PROMPT_KEYS["input.submit"]
    assert keys["input.newline"] == "ctrl+j"
    assert sandbox.chezmoi(sandbox.merge_source, "diff").stdout == ""
