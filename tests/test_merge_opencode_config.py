# tests/test_merge_opencode_config.py
"""Tests for home/dot_config/opencode/modify_opencode.jsonc.tmpl (chezmoi modify_).

opencode.jsonc is JSONC and its comments are load-bearing (the per-plugin
supply-chain audit and permission rationale), so the merge script does line-level
surgery. JSON decoding validates input; source slices preserve the output without
a serialization round-trip. These tests pin that contract:

  OWNED   schema, agent fields, Plan handoff rules, and marked plugin registrations.
  SEEDED  native "permissions" are written only when no policy exists; generic
          native Git rules migrate from deny to ask without touching private keys.
  KEPT    local plugins and other top-level keys, with their options and comments.

The work layer this exists for (a real `instructions` path and internal `mcp`
hostnames) is deliberately NOT used here: the fixtures use example.invalid so
nothing environment-specific lands in a public repo.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from fnmatch import fnmatchcase
from pathlib import Path

import pytest

REPO = Path(__file__).parent.parent
TMPL = REPO / "home" / "dot_config" / "opencode" / "modify_opencode.jsonc.tmpl"
MANAGED_PLUGINS = ["opencode-pillbox-statusline@latest", "opencode-sidequest@latest"]

pytestmark = pytest.mark.skipif(
    shutil.which("chezmoi") is None, reason="chezmoi not installed"
)


@pytest.fixture(scope="module")
def script(tmp_path_factory) -> str:
    """Render the modify_ template the way chezmoi will, return the script path."""
    directory = tmp_path_factory.mktemp("opencode-merge")
    config = directory / "chezmoi.toml"
    config.write_text('[data]\npalette="dracula"\n[data.components.ai]\nopencode=true\nopenviking=false\n')
    out = subprocess.run(
        ["chezmoi", "execute-template", "--source", str(REPO), "--config", str(config)],
        stdin=TMPL.open(), capture_output=True, text=True, check=True,
    ).stdout
    path = directory / "merge.py"
    path.write_text(out)
    return str(path)


@pytest.fixture(scope="module")
def ssh_script(tmp_path_factory) -> str:
    directory = tmp_path_factory.mktemp("opencode-ssh-merge")
    config = directory / "chezmoi.toml"
    config.write_text('[data]\npalette="dracula"\n[data.components.ai]\nopencode=true\nssh_mcp=true\n')
    result = subprocess.run(
        ["chezmoi", "execute-template", "--source", str(REPO), "--config", str(config)],
        stdin=TMPL.open(), capture_output=True, text=True, check=True,
    )
    path = directory / "merge.py"
    path.write_text(result.stdout)
    return str(path)


def test_ssh_mcp_starts_disabled_and_local_enable_survives(ssh_script):
    original = '''{
  "mcp": {
    "servers": {
      // Keep this connection intact.
      "other": {"type": "remote", "url": "https://example.invalid/mcp"}
    }
  }
}'''
    merged, error = merge(ssh_script, original)
    assert not error
    assert parse(merged)["mcp"]["servers"]["ssh-mcp"] == {
        "type": "local", "command": ["/bin/sh", "-c", 'exec "$HOME/.local/bin/ssh-mcp"'],
        "disabled": True,
    }
    assert '// Keep this connection intact.' in merged
    enabled = merged.replace('"disabled": true', '"disabled": false')
    again, error = merge(ssh_script, enabled)
    assert not error
    assert parse(again)["mcp"]["servers"]["ssh-mcp"]["disabled"] is False
    assert again == enabled


def test_bundled_mcps_start_disabled_without_individual_selection(script):
    merged, _ = merge(script, "")
    servers = parse(merged)["mcp"]["servers"]
    assert servers["ssh-mcp"]["disabled"] is True
    assert servers["caveman"]["disabled"] is True
    assert servers["caveman"]["codemode"] is False
    assert servers["caveman"]["command"] == ["/bin/sh", "-c", 'exec "$HOME/.local/bin/cavemanctl" mcp']
    local = '{\n  "mcp": {"servers": {"ssh-mcp": {"type": "local", "command": ["ssh-mcp"], "disabled": true}}}\n}'
    merged, _ = merge(script, local)
    assert parse(merged)["mcp"]["servers"]["ssh-mcp"]["disabled"] is True


def test_caveman_local_enable_and_codemode_survive_apply(script):
    initial, error = merge(script, "")
    assert not error
    configured = initial.replace('"codemode": false, "disabled": true', '"codemode": false, "disabled": false')
    repeated, error = merge(script, configured)
    assert not error
    assert repeated == configured
    assert parse(repeated)["mcp"]["servers"]["caveman"]["disabled"] is False


def test_managed_caveman_allow_follows_global_catchall_and_is_idempotent(script):
    original = '{\n  "permissions": [{"action": "*", "resource": "*", "effect": "ask"}]\n}\n'
    result, error = merge(script, original)
    assert not error
    rules = parse(result)["permissions"]
    assert rules[0] == {"action": "*", "resource": "*", "effect": "ask"}
    assert rules[-4] == {"action": "caveman_*", "resource": "*", "effect": "allow"}
    assert merge(script, result)[0] == result


def test_ssh_mcp_seed_handles_missing_servers_and_existing_local_entry(ssh_script):
    for source in ('', '{\n  "mcp": {}\n}', '{\n  "mcp": {"timeout": {"startup": 45000}}\n}'):
        result, error = merge(ssh_script, source)
        assert not error
        assert parse(result)["mcp"]["servers"]["ssh-mcp"]["type"] == "local"
        if "startup" in source:
            assert parse(result)["mcp"]["timeout"]["startup"] == 45000
    original = '{\n  "mcp": {"servers": {"ssh-mcp": {"type": "local", "command": ["custom-ssh"], "disabled": true}}}\n}'
    merged, error = merge(ssh_script, original)
    assert not error
    assert parse(merged)["mcp"]["servers"]["ssh-mcp"]["command"] == ["custom-ssh"]
    assert parse(merged)["mcp"]["servers"]["ssh-mcp"]["disabled"] is True


def merge(script: str, text: str, env: dict | None = None):
    """Run the merge script on `text`; return (stdout, stderr)."""
    e = dict(os.environ)
    if env:
        e.update(env)
    p = subprocess.run(
        [sys.executable, script], input=text.encode("utf-8"),
        capture_output=True, env=e,
    )
    assert p.returncode == 0, p.stderr.decode("utf-8", "replace")
    return p.stdout.decode("utf-8"), p.stderr.decode("utf-8", "replace")


def parse(text: str) -> dict:
    """JSONC-tolerant parse, so comments do not have to be stripped by hand."""
    json5 = pytest.importorskip("json5", reason="json5 needed for a JSONC parse")
    return json5.loads(text)


def strict_json_keys(text: str) -> list:
    """Sanity check that the emitted structure is sound, ignoring comments."""
    return sorted(parse(text).keys())


def permission_effect(rules: list[dict], action: str, resource: str) -> str:
    """Evaluate the ordered V2 rules with whole-resource wildcard matching."""
    effect = "ask"
    for rule in rules:
        pattern = rule["resource"]
        resource_match = fnmatchcase(resource, pattern)
        if action == "shell" and pattern.endswith(" *"):
            resource_match = resource_match or fnmatchcase(resource, pattern[:-2])
        if fnmatchcase(action, rule["action"]) and resource_match:
            effect = rule["effect"]
    return effect


# --- fixtures ---------------------------------------------------------------

WORK = """\
// local header a user wrote
{
  "$schema": "https://opencode.ai/config.json",

  "plugin": [
    "stale@0.0.1"
  ],

  "plugins": [
    "stale-v2@0.0.1"
  ],

  // LOCAL EDIT: loosened on this host; chezmoi must never revert it.
  "permission": {
    "edit": "allow",
    "bash": {
      "*": "ask",
      "terraform plan *": "allow"
    }
  },

  // WORK-ONLY. Memory index loaded every session.
  "instructions": [
    "/home/example/memory/MEMORY.md"
  ],

  // WORK-ONLY. Internal servers. Note the // inside these URLs: a naive line
  // parser would treat them as comments and mangle the file.
  "mcp": {
    "wiki": { "type": "remote", "url": "https://wiki.example.invalid/mcp" },
    "warehouse": { "type": "remote", "url": "https://dw.example.invalid/api/mcp" }
  }
}
"""

LEGACY_SEED = """\
{
  // Permission model: edit asks before writing (approve-on-write), webfetch is
  // allowed. bash is a pattern -> action map; the last matching rule wins, so the
  // catch-all "*": "ask" comes first and the linter/test allowlist follows.
  // Every pattern here is a generic, widely-used linter, formatter, test runner,
  // or the pre-commit driver.
  "permission": {
    "edit": "ask",
    "webfetch": "allow",
    "bash": {
      "*": "ask",
      "pre-commit *": "allow",
      "shellcheck *": "allow",
      "markdownlint *": "allow",
      "markdownlint-cli2 *": "allow",
      "bats *": "allow",
      "luacheck *": "allow",
      "ruff *": "allow",
      "flake8 *": "allow",
      "black *": "allow",
      "yamllint *": "allow",
      "actionlint *": "allow",
      "stylua *": "allow",
      "tflint *": "allow",
      "tfsec *": "allow",
      "checkov *": "allow",
      "golangci-lint *": "allow",
      "go test *": "allow",
      "go vet *": "allow",
      "pytest *": "allow",
      "eslint *": "allow",
      "prettier *": "allow"
    }
  }
}
"""

AGENTS_WITH_PRIVATE = """\
{
  "agents": {
    // This local agent and its comments are not owned by chezmoi.
    "local-reviewer": {
      "description": "Review without changing files",
      "mode": "subagent",
      "permissions": [
        { "action": "edit", "resource": "*", "effect": "deny" }
      ]
    }
  }
}
"""

AGENTS_WITH_BUILTIN_FIELDS = """\
{
  "agents": {
    // Keep the Build entry comment too.
    "build": {
      // Keep the custom Build description and request settings.
      "description": "Build with local conventions",
      // Keep the color rationale while replacing only its value.
      "color": "#000000", // Keep this inline note.
      "request": { "body": { "temperature": 0.2 } }
    },
    "plan": {
      // Plan intentionally omitted color before the merge.
      "description": "Plan without edits",
      "steps": 23
    },
    "ricer": {
      "description": "Keep this local description",
      "mode": "all",
      "system": "Keep this local system prompt"
    },
    "local-helper": {
      "description": "Preserve every custom agent"
    }
  }
}
"""


# --- owned ------------------------------------------------------------------

def test_empty_stdin_seeds_a_complete_generic_file(script):
    out, _ = merge(script, "")
    assert strict_json_keys(out) == ["$schema", "agents", "mcp", "permissions", "plugins"]
    d = parse(out)
    assert d["$schema"] == "https://opencode.ai/config.json"
    assert set(d["agents"]) == {"build", "plan", "ricer"}
    assert d["agents"]["ricer"]["mode"] == "subagent"
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", d["agents"]["build"]["color"])
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", d["agents"]["plan"]["color"])
    assert d["agents"]["build"]["color"] != d["agents"]["plan"]["color"]
    assert "permissions" not in d["agents"]["build"]
    plan_rules = d["agents"]["plan"]["permissions"]
    effective_rules = d["permissions"] + plan_rules
    for root in ("$HOME/.local/share/agent-handoffs/", "/opt/ai/handoffs/"):
        assert permission_effect(effective_rules, "external_directory", root + "*") == "allow"
        assert permission_effect(effective_rules, "edit", root + "Dotfiles/test-handoff-2026-10-05.md") == "allow"
        assert permission_effect(effective_rules, "edit", root + "Dotfiles/write-probe.md") == "deny"
        for name in ("secret.key", "secret.pem", "secret.env", "secret.env.local",
                     "secret.env.backup-handoff-2026-10-05.md"):
            assert permission_effect(effective_rules, "edit", root + "Dotfiles/" + name) == "deny"
    assert permission_effect(plan_rules, "edit", "/opt/other/project.md") == "ask"
    assert permission_effect(plan_rules, "external_directory", "$HOME/.local/share/agent-skills/handoff/scripts/*") == "allow"
    assert d["plugins"] == MANAGED_PLUGINS
    # A fresh host must not come up unguarded.
    assert d["permissions"][0] == {
        "action": "*", "resource": "*", "effect": "ask",
    }


def test_owned_comments_survive_because_nothing_is_reserialized(script):
    out, _ = merge(script, "")
    for comment in (
        "// Managed OpenCode V2 plugins track npm latest. Startup checks for updates;",
        "// Prompt metadata uses each agent's configured color.",
        "// Permission model: ask by default",
        "// Git mutations ask for approval",
    ):
        assert comment in out, f"lost load-bearing comment: {comment}"


def test_existing_v1_retirement_is_unchanged_but_local_v2_plugins_survive(script):
    out, _ = merge(script, WORK)
    assert "stale@0.0.1" not in out
    assert "plugin" not in parse(out)
    assert parse(out)["plugins"] == MANAGED_PLUGINS + ["stale-v2@0.0.1"]


# The managed section exactly as the previous dotfiles release wrote it.
RETIRED_COPILOT_SECTION = '''\
  "plugins": [
    // dotfiles:plugins:start
    // Managed OpenCode V2 plugins, EXACT-pinned. Review every version bump:
    // each plugin runs arbitrary code at startup.
    // opencode-copilot-statusline supplies monthly Copilot quota over RPC.
    // Audited @1.0.0: resolves the existing github-copilot credential and sends
    // it only to GitHub's undocumented Copilot quota API. No telemetry or
    // install-time scripts. cli.json disables its stock TUI half; the local
    // footer displays the quota after session cost, without a reset countdown.
    // A GitHub API change can make the quota unavailable.
    /* Keep this local note. */
    "opencode-copilot-statusline@1.0.0",
    // dotfiles:plugins:end
    "local-plugin@1.2.3",
    "-opencode-copilot-statusline"
  ]
'''


def test_retired_quota_pin_and_its_audit_are_replaced_by_pillbox(script):
    src = '{\n' + RETIRED_COPILOT_SECTION + '}\n'
    out, err = merge(script, src)
    assert err == ""
    assert parse(out)["plugins"] == MANAGED_PLUGINS + ["local-plugin@1.2.3", "-opencode-copilot-statusline"]
    assert "opencode-copilot-statusline supplies" not in out
    assert "Audited @1.0.0" not in out
    assert "/* Keep this local note. */" in out
    assert "// Managed OpenCode V2 plugins, EXACT-pinned." not in out
    assert out.count("// Managed OpenCode V2 plugins track npm latest.") == 1
    assert merge(script, out)[0] == out


def test_old_pin_audit_is_removed_without_dropping_local_comments(script):
    initial, _ = merge(script, "")
    old_audit = '''\
    // Managed OpenCode V2 plugins, EXACT-pinned. Review every version bump:
    // each plugin runs arbitrary code at startup.
    // Audited @0.1.0: resolves existing provider logins and sends each only to
    // this plain pin leaves it off. No install-time scripts or runtime npm
    // a terminal side panel. Reviewed source for @0.1.0: prompts go through the
    // dependencies. Verify the published tarball before the first deployment.
    // Keep my plugin note.
'''
    src = initial.replace('    // dotfiles:plugins:end', old_audit + '    // dotfiles:plugins:end')
    out, err = merge(script, src)
    assert err == ""
    assert "// Audited @0.1.0:" not in out
    assert "// Managed OpenCode V2 plugins, EXACT-pinned." not in out
    assert "// Keep my plugin note." in out
    assert merge(script, out)[0] == out


def managed_script(script, tmp_path, references):
    """Simulate a later dotfiles version or a deselected managed registration."""
    updated = re.sub(r"^MANAGED_PLUGINS = \(.*?^\)", "MANAGED_PLUGINS = " + repr(tuple(references)),
                     Path(script).read_text(), flags=re.M | re.S)
    path = tmp_path / "merge.py"
    path.write_text(updated)
    return str(path)


LOCAL_PLUGINS = '''\
    // This local plugin is deliberately not version-pinned.
    "local-plugin", // Keep this inline note.
    {
      "package": "@example/local-plugin@latest",
      "options": {
        /* Keep formatting and nested option comments. */
        "endpoint": "https://example.invalid/mcp//path",
        "message": "escaped \\"quote\\", comma, bracket ] and // dotfiles:plugins:end",
        "flags": [true, false, null, {"depth": 2}],
      },
    },
    "./plugins/local.ts",
    "../shared/plugin",
    "/opt/example/plugin",
    "file:///opt/example/plugin",
    "github:example/plugin#main",
    "git+ssh://git@example.invalid/plugin.git#main::path:packages/plugin",
    "*",
    "-opencode-pillbox-statusline",
    "opencode-pillbox-statusline",
    "-opencode.provider.*"
'''


def test_local_plugin_bytes_options_and_order_survive(script):
    local = LOCAL_PLUGINS
    src = '{\n  // Keep the local array comment.\n  "plugins": [\n' + local + '  ]\n}\n'
    out, err = merge(script, src)
    assert err == ""
    assert local in out
    assert '// Keep the local array comment.' in out
    assert parse(out)["plugins"][:len(MANAGED_PLUGINS)] == MANAGED_PLUGINS
    assert parse(out)["plugins"][len(MANAGED_PLUGINS):] == parse('{"plugins": [' + local + ']}')["plugins"]
    assert out.index('// dotfiles:plugins:end') < out.index('"-opencode-pillbox-statusline"')
    assert merge(script, out)[0] == out


@pytest.mark.parametrize("controls", [
    ["-opencode-pillbox-statusline", "opencode-pillbox-statusline", "-opencode-pillbox-statusline"],
    ["-*", "opencode-pillbox-statusline", "opencode-pillbox-statusline"],
    ["*", "-opencode-pillbox-statusline", "opencode-pillbox-statusline"],
])
def test_disable_and_reenable_controls_keep_their_order_and_duplicates(script, controls):
    src = '{\n  "plugins": ' + json.dumps(controls) + '\n}\n'
    out, err = merge(script, src)
    assert err == ""
    assert parse(out)["plugins"] == MANAGED_PLUGINS + controls
    assert merge(script, out)[0] == out


@pytest.mark.parametrize("position", [0, 1, 2])
@pytest.mark.parametrize("package", MANAGED_PLUGINS)
def test_exact_old_generated_entry_is_adopted_once(script, position, package):
    entries = ['"before@1"', '"after@2"']
    entries.insert(position, json.dumps(package))
    src = '{\n  "plugins": [' + ', '.join(entries) + ']\n}\n'
    out, err = merge(script, src)
    assert err == ""
    assert parse(out)["plugins"] == MANAGED_PLUGINS + ["before@1", "after@2"]
    assert out.count(json.dumps(package)) == 1
    assert out.count('// dotfiles:plugins:start') == 1
    assert merge(script, out)[0] == out


def test_managed_object_pin_updates_without_changing_options(script, tmp_path):
    options = '''\
      "options": {
        // Private option values and their spacing must survive.
        "endpoint" : "https://example.invalid/quota",
        "nested": {"enabled": true, "list": [1, 2, 3]},
      },
      "futureField": "keep this too"
'''
    src = '{\n  "plugins": [\n    {\n      "package": "opencode-pillbox-statusline@latest",\n' + options + '    },\n    "-opencode-pillbox-statusline"\n  ]\n}\n'
    adopted, err = merge(script, src)
    assert err == ""
    assert options in adopted
    bumped = managed_script(script, tmp_path, ["opencode-pillbox-statusline@2.0.0"])
    out, err = merge(bumped, adopted)
    assert err == ""
    assert options in out
    assert parse(out)["plugins"][0] == {
        "package": "opencode-pillbox-statusline@2.0.0",
        "options": {"endpoint": "https://example.invalid/quota", "nested": {"enabled": True, "list": [1, 2, 3]}},
        "futureField": "keep this too",
    }
    assert parse(out)["plugins"][1] == "-opencode-pillbox-statusline"
    assert merge(bumped, out)[0] == out


def test_removed_managed_registration_leaves_independent_local_copy(script, tmp_path):
    initial, _ = merge(script, '{\n  "plugins": ["local-plugin", "-opencode-pillbox-statusline"]\n}\n')
    # This later version no longer selects the package. A local registration is
    # now independent, even when it names the formerly managed package.
    disabled = managed_script(script, tmp_path, [])
    src = initial.replace('"local-plugin"', '"opencode-pillbox-statusline@9.0.0", "local-plugin"')
    out, err = merge(disabled, src)
    assert err == ""
    assert parse(out)["plugins"] == [
        "opencode-pillbox-statusline@9.0.0", "local-plugin", "-opencode-pillbox-statusline"
    ]
    assert '"opencode-pillbox-statusline@latest"' not in out
    assert merge(disabled, out)[0] == out


def test_new_managed_registration_does_not_discard_local_plugins(script, tmp_path):
    original, _ = merge(script, '{\n  "plugins": ["local-plugin"]\n}\n')
    added = managed_script(script, tmp_path, ["opencode-pillbox-statusline@latest", "@example/new-plugin@2.0.0"])
    out, err = merge(added, original)
    assert err == ""
    assert parse(out)["plugins"] == ["opencode-pillbox-statusline@latest", "@example/new-plugin@2.0.0", "local-plugin"]
    assert merge(added, out)[0] == out


def test_cli_style_local_addition_survives_repeated_applies(script):
    initial, _ = merge(script, "")
    # Match the CLI's effect on the global config without installing a plugin.
    src = initial.replace('    // dotfiles:plugins:end', '    // dotfiles:plugins:end\n    "cli-added-plugin@latest",')
    src = src.replace('    "opencode-sidequest@latest"\n', '    "opencode-sidequest@latest",\n')
    out, err = merge(script, src)
    assert err == ""
    assert parse(out)["plugins"] == MANAGED_PLUGINS + ["cli-added-plugin@latest"]
    assert merge(script, out)[0] == out


def test_managed_entry_comments_survive_pin_updates(script, tmp_path):
    initial, _ = merge(script, "")
    src = initial.replace('    "opencode-pillbox-statusline@latest",',
                          '    /* Local quota rationale. */\n    "opencode-pillbox-statusline@latest", // Local inline rationale.')
    bumped = managed_script(script, tmp_path, ["opencode-pillbox-statusline@2.0.0"])
    out, err = merge(bumped, src)
    assert err == ""
    assert '/* Local quota rationale. */' in out
    assert '// Local inline rationale.' in out
    assert parse(out)["plugins"] == ["opencode-pillbox-statusline@2.0.0"]
    assert merge(bumped, out)[0] == out


@pytest.mark.parametrize("entry", [
    '"opencode-pillbox-statusline@0.1.0"',
    '"opencode-pillbox-statusline@2.0.0"',
    '"opencode-pillbox-statusline"',
    '{"package": "opencode-pillbox-statusline@9.0.0", "options": {"keep": true}}',
    '{"package": "opencode-pillbox-statusline", "options": {"keep": true}}',
    '"opencode-pillbox-statusline@latest", "opencode-pillbox-statusline@latest"',
])
@pytest.mark.parametrize("package", ["opencode-pillbox-statusline", "opencode-sidequest"])
def test_ambiguous_unmarked_ownership_leaves_target_unchanged(script, entry, package):
    entry = entry.replace("opencode-pillbox-statusline", package)
    src = '{\n  "plugins": [' + entry + '],\n  "instructions": ["local.md"]\n}\n'
    out, err = merge(script, src)
    assert out == src
    assert 'cannot merge plugin registrations' in err


def test_competing_local_registration_after_managed_section_is_not_overwritten(script):
    initial, _ = merge(script, "")
    src = initial.replace('    // dotfiles:plugins:end', '    // dotfiles:plugins:end\n    "opencode-pillbox-statusline@9.0.0",')
    src = src.replace('    "opencode-sidequest@latest"\n', '    "opencode-sidequest@latest",\n')
    out, err = merge(script, src)
    assert out == src
    assert 'local registration conflicts' in err


@pytest.mark.parametrize("body", [
    '// dotfiles:plugins:start\n"local"',
    '// dotfiles:plugins:end\n// dotfiles:plugins:start\n"local"',
    '// dotfiles:plugins:start\n// dotfiles:plugins:start\n// dotfiles:plugins:end',
    '"local",\n// dotfiles:plugins:start\n// dotfiles:plugins:end',
    '// dotfiles:plugins:start\n{"package": "local",\n// dotfiles:plugins:end\n"options": {}}',
    '// dotfiles:plugins:start\n"local"\n// dotfiles:plugins:end\n, "another"',
    '// dotfiles:plugins:start\n"opencode-pillbox-statusline@0.1.0", "opencode-pillbox-statusline@2.0.0"\n// dotfiles:plugins:end',
])
def test_ambiguous_marked_section_passes_through_unchanged(script, body):
    src = '{\n  "plugins": [\n' + body + '\n  ]\n}\n'
    out, err = merge(script, src)
    assert out == src
    assert 'cannot merge plugin registrations' in err


@pytest.mark.parametrize("value", [
    '"not an array"', 'null', '{}', '[true]', '[{"options": {}}]',
    '[{"package": 42}]', '["first" "second"]', '["first",, "second"]',
    '[,]', '["first",,]',
])
def test_malformed_plugin_values_pass_through_unchanged(script, value):
    src = '{\n  "plugins": ' + value + '\n}\n'
    out, err = merge(script, src)
    assert out == src
    assert 'leaving the target unchanged' in err


@pytest.mark.parametrize("src", [
    '{\n  "plugins": [],\n  "plugins": ["local"]\n}\n',
    '{\n  "plugins": [{"package": "local", "package": "other"}]\n}\n',
    '{\n  "plugins": []\n}\nnot-json\n',
    '{\n  "plugins": [],\n  /* unclosed comment\n}\n',
    '{\n  "plugins": [],\n  "counter": 1 2\n}\n',
    '{\n  "plugins": [{"package": "local", "options": {"value": NaN}}]\n}\n',
    '{\n  "plugins": [],\n  "options": {,}\n}\n',
    '{\n  "plugins": [],\n  "options": {"missing":,}\n}\n',
])
def test_invalid_jsonc_and_duplicate_keys_are_not_rewritten(script, src):
    out, err = merge(script, src)
    assert out == src
    assert 'leaving the target unchanged' in err


def test_unsupported_escaped_managed_keys_cannot_create_duplicate_output(script):
    src = '{\n  "plug\\u0069ns": ["local"]\n}\n'
    out, err = merge(script, src)
    assert out == src
    assert 'merged config would be invalid JSONC' in err


def test_private_agent_and_comments_survive_agent_color_merge(script):
    out, _ = merge(script, AGENTS_WITH_PRIVATE)
    agents = parse(out)["agents"]
    assert agents["local-reviewer"] == {
        "description": "Review without changing files",
        "mode": "subagent",
        "permissions": [
            {"action": "edit", "resource": "*", "effect": "deny"}
        ],
    }
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", agents["build"]["color"])
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", agents["plan"]["color"])
    assert "// This local agent and its comments are not owned by chezmoi." in out


def test_extra_builtin_agent_fields_and_comments_survive(script):
    out, _ = merge(script, AGENTS_WITH_BUILTIN_FIELDS)
    agents = parse(out)["agents"]
    assert agents["build"]["description"] == "Build with local conventions"
    assert agents["build"]["request"] == {"body": {"temperature": 0.2}}
    assert agents["build"]["color"] != "#000000"
    assert agents["plan"]["description"] == "Plan without edits"
    assert agents["plan"]["steps"] == 23
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", agents["plan"]["color"])
    assert agents["ricer"] == {
        "description": "Keep this local description",
        "mode": "subagent",
        "system": "Keep this local system prompt",
    }
    assert agents["local-helper"] == {
        "description": "Preserve every custom agent"
    }
    assert "// Keep the Build entry comment too." in out
    assert "// Keep the custom Build description and request settings." in out
    assert "// Keep the color rationale while replacing only its value." in out
    assert "// Keep this inline note." in out
    assert "// Plan intentionally omitted color before the merge." in out


def test_plan_handoff_rules_preserve_local_permissions_and_comments(script):
    src = '''\
{
  "agents": {
    "plan": {
      "description": "Plan with local limits",
      "permissions": [
        // This unrelated local rule stays in place.
        { "action": "edit", "resource": "/private/notes/*", "effect": "allow" }
      ]
    }
  }
}
'''
    out, _ = merge(script, src)
    rules = parse(out)["agents"]["plan"]["permissions"]
    assert rules[-1] == {"action": "edit", "resource": "/private/notes/*", "effect": "allow"}
    assert permission_effect(rules, "edit", "/opt/ai/handoffs/Dotfiles/test-handoff-2026-10-05.md") == "allow"
    assert "// This unrelated local rule stays in place." in out
    assert parse(out)["agents"]["plan"]["description"] == "Plan with local limits"
    assert merge(script, out)[0] == out


def test_malformed_plan_permissions_are_not_overwritten(script):
    src = '{\n  "agents": { "plan": { "permissions": "local" } }\n}\n'
    out, err = merge(script, src)
    assert out == src
    assert "plan permissions is not an array" in err


# --- Plan handoff rules for the agent-notes directory ----------------------

PLAN_START = "// dotfiles:plan-handoff:start"
PLAN_END = "// dotfiles:plan-handoff:end"

# The managed block as an earlier release rendered it: the two fixed roots, the
# snapshot script, and the secret denials, with no agent-notes rules.
OLDER_PLAN_RULES = (
    '{ "action": "external_directory", "resource": "$HOME/.local/share/agent-handoffs/*", "effect": "allow" }',
    '{ "action": "edit", "resource": "$HOME/.local/share/agent-handoffs/*", "effect": "deny" }',
    '{ "action": "edit", "resource": "$HOME/.local/share/agent-handoffs/*/*-handoff-????-??-??.md", "effect": "allow" }',
    '{ "action": "external_directory", "resource": "/opt/ai/handoffs/*", "effect": "allow" }',
    '{ "action": "edit", "resource": "/opt/ai/handoffs/*", "effect": "deny" }',
    '{ "action": "edit", "resource": "/opt/ai/handoffs/*/*-handoff-????-??-??.md", "effect": "allow" }',
    '{ "action": "external_directory", "resource": "$HOME/.local/share/agent-skills/handoff/scripts/*", "effect": "allow" }',
    '{ "action": "edit", "resource": "*.env", "effect": "deny" }',
    '{ "action": "edit", "resource": "*.env.*", "effect": "deny" }',
    '{ "action": "edit", "resource": "*.pem", "effect": "deny" }',
    '{ "action": "edit", "resource": "*.key", "effect": "deny" }',
)


def older_plan_block(followed: bool, indent: str = " " * 8) -> str:
    """The block an earlier apply wrote; its last rule carries a comma only when
    another rule follows the block."""
    lines = [indent + PLAN_START]
    for i, rule in enumerate(OLDER_PLAN_RULES):
        lines.append(indent + rule + ("," if i < len(OLDER_PLAN_RULES) - 1 or followed else ""))
    lines.append(indent + PLAN_END)
    return "\n".join(lines)


def out_has_single_block(out: str) -> bool:
    return out.count(PLAN_START) == 1 and out.count(PLAN_END) == 1


def render_with_agents_dir(tmp_path_factory, agents_dir=None):
    """Render the merge script for a given data.agentsDir under a disposable HOME.

    Returns (script_path, home). `agents_dir=None` leaves the key out entirely,
    like a config written before the key existed.
    """
    directory = tmp_path_factory.mktemp("opencode-agents-dir")
    home = directory / "home"
    home.mkdir()
    config = directory / "chezmoi.toml"
    line = "" if agents_dir is None else 'agentsDir = "%s"\n' % agents_dir
    config.write_text(
        '[data]\npalette = "dracula"\n%s[data.components.ai]\nopencode = true\nopenviking = false\n' % line
    )
    env = dict(os.environ, HOME=str(home))
    out = subprocess.run(
        ["chezmoi", "execute-template", "--source", str(REPO), "--config", str(config)],
        stdin=TMPL.open(), capture_output=True, text=True, check=True, env=env,
    ).stdout
    path = directory / "merge.py"
    path.write_text(out)
    return str(path), str(home)


def plan_block_resources(out: str) -> list[str]:
    """Resources inside the managed marker block, in order."""
    block = out.split(PLAN_START, 1)[1].split(PLAN_END, 1)[0]
    return re.findall(r'"resource": "([^"]*)"', block)


def assert_agent_notes_boundary(out: str, notes: str):
    """The agent-notes handoff rules behave like the two fixed roots."""
    d = parse(out)
    effective = d["permissions"] + d["agents"]["plan"]["permissions"]
    plans = notes + "/plans/"
    assert permission_effect(effective, "external_directory", plans + "*") == "allow"
    assert permission_effect(effective, "edit", plans + "Dotfiles/test-handoff-2026-10-20.md") == "allow"
    assert permission_effect(effective, "edit", plans + "Dotfiles/write-probe.md") == "deny"
    for name in ("secret.key", "secret.pem", "secret.env", "secret.env.local",
                 "secret.env.backup-handoff-2026-10-20.md"):
        assert permission_effect(effective, "edit", plans + "Dotfiles/" + name) == "deny"
    # Only the plans subtree is writable; the rest of the notes tree is not.
    for other in ("specs/Dotfiles.md", "drafts/note-handoff-2026-10-20.md", "memory/MEMORY.md"):
        assert permission_effect(effective, "edit", notes + "/" + other) != "allow"
    # The new rules live in Plan only, not in the global native policy.
    assert not any(notes in rule["resource"] for rule in d["permissions"])


def test_plan_handoff_rules_cover_the_default_agent_notes_plans(tmp_path_factory):
    script, home = render_with_agents_dir(tmp_path_factory)
    out, _ = merge(script, "")
    assert_agent_notes_boundary(out, home + "/agents")
    resources = plan_block_resources(out)
    # Two fixed roots first, then agentsDir/plans, then the snapshot script, then
    # the secret denials last.
    assert resources == [
        "$HOME/.local/share/agent-handoffs/*",
        "$HOME/.local/share/agent-handoffs/*",
        "$HOME/.local/share/agent-handoffs/*/*-handoff-????-??-??.md",
        "/opt/ai/handoffs/*",
        "/opt/ai/handoffs/*",
        "/opt/ai/handoffs/*/*-handoff-????-??-??.md",
        home + "/agents/plans/*",
        home + "/agents/plans/*",
        home + "/agents/plans/*/*-handoff-????-??-??.md",
        "$HOME/.local/share/agent-skills/handoff/scripts/*",
        "*.env", "*.env.*", "*.pem", "*.key",
    ]
    rules = parse(out)["agents"]["plan"]["permissions"]
    assert [rule["effect"] for rule in rules[6:9]] == ["allow", "deny", "allow"]
    assert [rule["action"] for rule in rules[6:9]] == ["external_directory", "edit", "edit"]
    assert [rule["effect"] for rule in rules[-4:]] == ["deny"] * 4
    # The existing roots keep working next to the new one.
    for root in ("$HOME/.local/share/agent-handoffs/", "/opt/ai/handoffs/"):
        assert permission_effect(rules, "edit", root + "Dotfiles/test-handoff-2026-10-20.md") == "allow"


@pytest.mark.parametrize("configured, expected", [
    ("/srv/notes", "/srv/notes"),
    ("/srv/notes/", "/srv/notes"),
    ("~/notes/agents", "{home}/notes/agents"),
    ("$HOME/ag", "{home}/ag"),
    ("${HOME}//ag/./x", "{home}/ag/x"),
])
def test_plan_handoff_rules_follow_a_custom_agents_dir(tmp_path_factory, configured, expected):
    script, home = render_with_agents_dir(tmp_path_factory, configured)
    out, _ = merge(script, "")
    notes = expected.format(home=home)
    assert_agent_notes_boundary(out, notes)
    resources = plan_block_resources(out)
    assert notes + "/plans/*" in resources
    # The default location is not granted when another one is configured.
    assert home + "/agents/plans/*" not in resources


def test_plan_handoff_rules_handle_a_path_with_a_space(tmp_path_factory):
    script, home = render_with_agents_dir(tmp_path_factory, "~/my notes/a@b+c%d")
    notes = home + "/my notes/a@b+c%d"
    out, _ = merge(script, "")
    assert_agent_notes_boundary(out, notes)
    assert notes + "/plans/*/*-handoff-????-??-??.md" in plan_block_resources(out)
    # The merge script is plain Python: a space or percent sign must not break it.
    compile(Path(script).read_text(), script, "exec")
    assert merge(script, out)[0] == out


@pytest.mark.parametrize("bad", ["relative/path", "/", "/tmp/a$(id)", "/tmp/it's", '/tmp/q"uote'])
def test_unsafe_agents_dir_fails_the_render_instead_of_reaching_python(tmp_path_factory, bad):
    directory = tmp_path_factory.mktemp("opencode-agents-bad")
    config = directory / "chezmoi.toml"
    config.write_text('[data]\nagentsDir = "%s"\n' % bad.replace('"', '\\"'))
    result = subprocess.run(
        ["chezmoi", "execute-template", "--source", str(REPO), "--config", str(config)],
        stdin=TMPL.open(), capture_output=True, text=True,
        env=dict(os.environ, HOME=str(directory)),
    )
    assert result.returncode != 0
    assert "data.agentsDir" in result.stderr


def test_plan_handoff_block_regenerates_over_an_older_block(tmp_path_factory):
    script, home = render_with_agents_dir(tmp_path_factory, "/srv/notes")
    src = '''\
{
  "agents": {
    "plan": {
      "permissions": [
        // Local rule above the managed block.
        { "action": "edit", "resource": "/private/before/*", "effect": "allow" },
%s
        // Local rule below the managed block.
        { "action": "edit", "resource": "/private/after/*", "effect": "allow" }
      ]
    }
  }
}
''' % older_plan_block(followed=True)
    out, err = merge(script, src)
    assert not err
    assert out.count(PLAN_START) == 1 and out.count(PLAN_END) == 1
    assert plan_block_resources(out).count("/srv/notes/plans/*") == 2
    assert_agent_notes_boundary(out, "/srv/notes")
    # The older block's exact rules are still present once, not duplicated.
    assert plan_block_resources(out).count("/opt/ai/handoffs/*") == 2
    rules = parse(out)["agents"]["plan"]["permissions"]
    assert rules[0]["resource"] == "/private/before/*"
    assert rules[-1]["resource"] == "/private/after/*"
    assert merge(script, out)[0] == out


def test_plan_handoff_block_follows_a_changed_agents_dir(tmp_path_factory):
    old_script, _ = render_with_agents_dir(tmp_path_factory, "/srv/old-notes")
    new_script, _ = render_with_agents_dir(tmp_path_factory, "/srv/new-notes")
    first, _ = merge(old_script, "")
    assert "/srv/old-notes/plans/*" in plan_block_resources(first)
    second, _ = merge(new_script, first)
    assert out_has_single_block(second)
    assert "/srv/old-notes" not in second
    assert_agent_notes_boundary(second, "/srv/new-notes")
    assert merge(new_script, second)[0] == second


def test_plan_handoff_regeneration_preserves_everything_outside_the_markers(tmp_path_factory):
    script, home = render_with_agents_dir(tmp_path_factory)
    src = '''\
{
  "instructions": ["/home/example/MEMORY.md"],

  // Local plan customization lives next to the managed block.
  "agents": {
    "plan": {
      "description": "Plan with local limits",
      "permissions": [
        // Trailing note kept with the rule below it.
        { "action": "edit", "resource": "/private/notes/*", "effect": "allow" },
%s
      ]
    },
    // A custom agent the merge must not touch.
    "reviewer": { "mode": "subagent", "color": "#112233" }
  },

  // Machine-local MCP entry.
  "mcp": { "servers": { "local": { "type": "local", "command": ["true"] } } }
}
''' % older_plan_block(followed=False)
    out, err = merge(script, src)
    assert not err
    d = parse(out)
    assert d["agents"]["plan"]["description"] == "Plan with local limits"
    assert d["agents"]["reviewer"] == {"mode": "subagent", "color": "#112233"}
    assert d["mcp"]["servers"]["local"]["command"] == ["true"]
    assert d["instructions"] == ["/home/example/MEMORY.md"]
    for comment in ("// Local plan customization lives next to the managed block.",
                    "// Trailing note kept with the rule below it.",
                    "// A custom agent the merge must not touch.",
                    "// Machine-local MCP entry."):
        assert comment in out
    rules = d["agents"]["plan"]["permissions"]
    assert rules[0] == {"action": "edit", "resource": "/private/notes/*", "effect": "allow"}
    assert_agent_notes_boundary(out, home + "/agents")
    assert merge(script, out)[0] == out


def test_plan_handoff_output_is_valid_jsonc_and_strict_json_shaped(tmp_path_factory):
    script, home = render_with_agents_dir(tmp_path_factory, "/srv/notes")
    fresh, _ = merge(script, "")
    # json5 accepts the JSONC comments; a successful parse proves the commas and
    # brackets around the longer block are still correct.
    assert parse(fresh)["agents"]["plan"]["permissions"][-1]["resource"] == "*.key"
    # Without its full-line comments the same text must also load as strict JSON.
    stripped = "\n".join(line for line in fresh.splitlines() if not line.lstrip().startswith("//"))
    assert json.loads(stripped)["agents"]["plan"]["permissions"]


# --- seeded -----------------------------------------------------------------

def test_existing_permission_is_never_overwritten(script):
    out, _ = merge(script, WORK)
    perm = parse(out)["permission"]
    assert perm["edit"] == "allow"
    assert perm["bash"]["terraform plan *"] == "allow"
    # The native seed must not leak in alongside it.
    assert "permissions" not in parse(out)
    assert "// LOCAL EDIT: loosened on this host" in out


def test_seed_only_fires_when_permission_is_absent(script):
    out, _ = merge(script, '{\n  "instructions": ["/x"]\n}\n')
    assert parse(out)["permissions"][0]["effect"] == "ask"
    out2, _ = merge(script, '{\n  "permission": { "edit": "deny" }\n}\n')
    assert parse(out2)["permission"] == {"edit": "deny"}
    assert "permissions" not in parse(out2)


def test_exact_old_seed_migrates_to_native_permissions(script):
    out, _ = merge(script, LEGACY_SEED)
    d = parse(out)
    assert "permission" not in d
    assert d["permissions"][0]["effect"] == "ask"


def test_customized_old_seed_is_preserved_byte_for_byte(script):
    customized = LEGACY_SEED.replace('"edit": "ask"', '"edit": "deny"')
    out, _ = merge(script, customized)
    d = parse(out)
    assert d["permission"]["edit"] == "deny"
    assert "permissions" not in d
    assert "// Permission model: edit asks before writing" in out


def test_existing_native_permissions_and_comments_are_preserved(script):
    src = """\
{
  // Local policy stays private and unchanged.
  "permissions": [
    { "action": "shell", "resource": "custom *", "effect": "allow" }
  ]
    }
"""
    out, _ = merge(script, src)
    assert parse(out)["permissions"][:1] == [
        {"action": "shell", "resource": "custom *", "effect": "allow"}
    ]
    assert "// Local policy stays private and unchanged." in out


def test_existing_native_permissions_migrate_the_hook_driver(script):
    src = """\
{
  // Keep this local policy comment.
  "permissions": [
    { "action": "shell", "resource": "pre-commit *", "effect": "allow" },
    { "action": "shell", "resource": "terraform plan *", "effect": "allow" }
  ]
}
"""
    out, _ = merge(script, src)
    assert '"resource": "prek *"' in out
    assert '"resource": "pre-commit *"' in out
    rules = parse(out)["permissions"]
    assert permission_effect(rules, "shell", "prek run --all-files") == "allow"
    assert permission_effect(rules, "shell", "pre-commit run --all-files") == "allow"
    assert '"resource": "terraform plan *"' in out
    assert "// Keep this local policy comment." in out
    assert merge(script, out)[0] == out


def test_existing_prek_allow_adds_pre_commit_without_changing_other_rules(script):
    src = '''{
  "permissions": [
    { "action": "shell", "resource": "prek *", "effect": "allow" },
    { "action": "shell", "resource": "terraform plan *", "effect": "ask" }
  ]
}
    '''
    out, _ = merge(script, src)
    rules = parse(out)["permissions"]
    assert [rule["resource"] for rule in rules[:3]] == [
        "prek *", "pre-commit *", "terraform plan *"
    ]
    assert merge(script, out)[0] == out


def test_existing_native_worktree_rule_narrows_without_replacing_local_policy(script):
    src = """\
{
  // Keep other local choices in their original order.
  "permissions": [
    { "action": "shell", "resource": "git worktree *", "effect": "allow" },
    { "action": "shell", "resource": "git push *", "effect": "deny" },
    { "action": "shell", "resource": "rm -rf *", "effect": "deny" }
  ]
}
"""
    out, _ = merge(script, src)
    assert '"resource": "git worktree *"' in out
    assert '"resource": "git worktree list *"' in out
    assert '// Keep other local choices in their original order.' in out
    assert permission_effect(parse(out)["permissions"], "shell", "git worktree remove old") == "ask"
    assert permission_effect(parse(out)["permissions"], "shell", "git worktree list") == "allow"
    assert parse(out)["permissions"][:4] == [
        {"action": "shell", "resource": "git worktree *", "effect": "ask"},
        {"action": "shell", "resource": "git worktree list *", "effect": "allow"},
        {"action": "shell", "resource": "git push *", "effect": "ask"},
        {"action": "shell", "resource": "rm -rf *", "effect": "deny"},
    ]


def test_openviking_global_rules_override_catchall_without_relaxing_other_actions(script):
    src = '''{
  "permissions": [
    { "action": "*", "resource": "*", "effect": "ask" },
    { "action": "edit", "resource": "*.env", "effect": "deny" }
  ]
}
'''
    out, _ = merge(script, src)
    rules = parse(out)["permissions"]
    assert rules[-3:] == [
        {"action": "openviking_*", "resource": "*", "effect": "allow"},
        {"action": "skill", "resource": "openviking-*", "effect": "allow"},
        {"action": "skill", "resource": "ov-experience-memory", "effect": "allow"},
    ]
    assert permission_effect(rules, "openviking_write", "*") == "allow"
    assert permission_effect(rules, "skill", "openviking-memory") == "allow"
    assert permission_effect(rules, "skill", "ov-experience-memory") == "allow"
    assert permission_effect(rules, "edit", "~/.agents/skills/example/SKILL.md") == "allow"
    assert permission_effect(rules, "edit", "~/.claude/hooks/local.sh") == "allow"
    assert permission_effect(rules, "edit", "secret.env") == "deny"
    assert permission_effect(rules, "edit", "~/.agents/skills/private.env") == "deny"
    assert permission_effect(rules, "shell", "git push origin main") == "ask"
    again, _ = merge(script, out)
    assert again == out
    again, _ = merge(script, out)
    assert again == out


def test_existing_native_git_denials_migrate_without_touching_private_agents(script):
    src = '''{
  "permissions": [
    { "action": "shell", "resource": "*git * commit *", "effect": "deny" },
    { "action": "shell", "resource": "git * --output=*", "effect": "deny" },
    { "action": "shell", "resource": "git clean *", "effect": "deny" },
    { "action": "shell", "resource": "rm -rf *", "effect": "deny" }
  ],
  "agents": {
    "local": { "permissions": [
      { "action": "shell", "resource": "git clean *", "effect": "deny" }
    ] }
  }
}
'''
    out, _ = merge(script, src)
    rules = parse(out)["permissions"]
    for command in ("git -C repo commit -m test", "git log --output=notes", "git clean -fd"):
        assert permission_effect(rules, "shell", command) == "ask"
    assert permission_effect(rules, "shell", "rm -rf dir") == "deny"
    assert parse(out)["agents"]["local"]["permissions"][0]["effect"] == "deny"
    assert merge(script, out)[0] == out


def test_native_seed_has_narrow_allows_and_final_denials(script):
    out, _ = merge(script, "")
    rules = parse(out)["permissions"]
    triples = [(r["action"], r["resource"], r["effect"]) for r in rules]

    for rule in (
        ("read", "*", "allow"),
        ("glob", "*", "allow"),
        ("grep", "*", "allow"),
        ("webfetch", "https://*", "allow"),
        ("websearch", "*", "allow"),
        ("question", "*", "allow"),
        ("skill", "*", "allow"),
        ("subagent", "*", "allow"),
        ("execute", "*", "allow"),
        ("external_directory", "*", "allow"),
        ("edit", "~/.agents/*", "allow"),
        ("edit", "~/.claude/*", "allow"),
        ("aws-documentation_*", "*", "allow"),
        ("aws-iam-policy-autopilot_generate_*", "*", "allow"),
        ("aws-mcp_aws___get_tasks", "*", "allow"),
        ("terraform_get_*", "*", "allow"),
        ("confluence_confluence_get_*", "*", "allow"),
        ("databricks_list_*", "*", "allow"),
        ("browser_snapshot", "*", "allow"),
        ("opencode_models", "*", "allow"),
        ("shell", "pdftotext * -", "allow"),
        ("shell", "prek *", "allow"),
        ("shell", "pre-commit *", "allow"),
        ("shell", "git worktree list *", "allow"),
        ("shell", "gh pr view *", "allow"),
    ):
        assert rule in triples

    for resource in ("git add *", "git commit *", "git rm *", "git push *", "git worktree *"):
        assert ("shell", resource, "ask") in triples
    assert ("shell", "rm -rf *", "deny") in triples
    assert triples.index(("shell", "git add *", "ask")) > triples.index(
        ("shell", "git status *", "allow")
    )
    assert triples.index(("read", "*.env", "deny")) > triples.index(
        ("read", "*", "allow")
    )

    resources = {resource for action, resource, effect in triples if action == "shell" and effect == "allow"}
    assert "gh api *" in resources
    assert "git push *" not in resources
    assert "aws *" not in resources
    assert "python *" not in resources
    assert "npm install *" not in resources


def test_read_only_tools_do_not_remove_mutation_prompts(script):
    out, _ = merge(script, "")
    rules = parse(out)["permissions"]

    for action in (
        "question",
        "skill",
        "subagent",
        "execute",
        "aws-documentation_read_documentation",
        "aws-iam-policy-autopilot_generate_application_policies",
        "aws-mcp_aws___get_tasks",
        "terraform_get_provider_details",
        "confluence_confluence_get_page",
        "databricks_list_jobs",
        "browser_snapshot",
        "opencode_models",
    ):
        assert permission_effect(rules, action, "*") == "allow", action

    # Underscore forms are the bug: OpenCode keeps hyphens in the server name.
    assert permission_effect(rules, "aws_documentation_read_documentation", "*") == "ask"
    assert permission_effect(
        rules, "aws_iam_policy_autopilot_generate_application_policies", "*"
    ) == "ask"

    for action in (
        "aws-iam-policy-autopilot_fix_access_denied",
        "aws-mcp_aws___run_script",
        "confluence_confluence_delete_page",
        "databricks_create_job",
        "browser_click",
        "opencode_session_move",
    ):
        assert permission_effect(rules, action, "*") == "ask", action

    assert permission_effect(rules, "edit", "README.md") == "ask"
    assert permission_effect(rules, "read", "/tmp/notes/design.pdf") == "allow"
    assert permission_effect(rules, "shell", "cat docs/operation.md") == "ask"
    assert permission_effect(rules, "shell", "cat .env") == "ask"
    assert permission_effect(rules, "shell", "pdftotext design.pdf -") == "allow"
    assert permission_effect(rules, "shell", "gh api repos/example/project") == "allow"
    assert permission_effect(rules, "shell", "gh api repos/example/project -f name=value") == "ask"
    assert permission_effect(
        rules, "shell", "gh api -X GET repos/example/project"
    ) == "allow"


def test_github_auth_status_never_allows_token_output(script):
    out, _ = merge(script, "")
    rules = parse(out)["permissions"]
    assert permission_effect(rules, "shell", "gh auth status") == "allow"
    assert permission_effect(
        rules, "shell", "gh auth status --hostname github.com"
    ) == "ask"
    for command in (
        "gh auth status --show-token",
        "gh auth status --show-token --hostname github.com",
        "gh auth status --hostname github.com --show-token",
        "gh auth status --show-token=true",
        "gh auth status -t",
        "gh auth status -t --hostname github.com",
        "gh auth status --hostname github.com -t",
        "gh auth status -t=true",
        "gh auth status --hostname github.com -t=true",
        "/opt/homebrew/bin/gh auth status --show-token",
        "command gh auth status -t",
    ):
        assert permission_effect(rules, "shell", command) == "deny", command

    allowed_auth_status = [
        rule["resource"]
        for rule in rules
        if rule["action"] == "shell"
        and rule["effect"] == "allow"
        and rule["resource"].startswith("gh auth status")
    ]
    assert allowed_auth_status == ["gh auth status"]


def test_git_mutations_ask_and_recursive_rm_stays_denied(script):
    out, _ = merge(script, "")
    rules = parse(out)["permissions"]
    for command in (
        "git -C repo add file",
        "git -C repo commit -m test",
        "git --git-dir=.git rm file",
        "git -C repo push origin main",
        "git -C repo reset --hard",
        "git -C repo clean -fdx",
        "git -C repo checkout -- file",
        "git -C repo restore file",
        "git --no-pager push",
        "git -c core.pager=cat commit",
        "git --work-tree=. add file",
        "/usr/bin/git -C repo add file",
        "command git -C repo commit -m test",
        "rm -f -r target",
        "rm -r -f target",
        "rm -fR target",
        "rm -Rf target",
        "rm --force --recursive target",
        "rm --recursive --force target",
        "rm --force -r target",
        "rm -f -R target",
        "command rm -f -R target",
        "/bin/rm target -r",
    ):
        expected = "deny" if "rm " in command and "git" not in command else "ask"
        assert permission_effect(rules, "shell", command) == expected, command

    assert permission_effect(rules, "shell", "git worktree list --porcelain") == "allow"
    for command in ("git worktree add ../new", "git worktree remove old", "git worktree prune"):
        assert permission_effect(rules, "shell", command) == "ask"

    shell_rules = [rule for rule in rules if rule["action"] == "shell"]
    last_allow = max(i for i, rule in enumerate(shell_rules) if rule["effect"] == "allow")
    first_destructive_rule = min(
        i
        for i, rule in enumerate(shell_rules)
        if rule["resource"] in {"git add *", "rm -r *"}
    )
    assert first_destructive_rule > last_allow


def test_seeded_block_matches_the_generic_base(script):
    """A fresh host and an existing host must converge on the same file."""
    base, _ = merge(script, "")
    again, _ = merge(script, base)
    assert base == again


# --- kept -------------------------------------------------------------------

def test_work_keys_and_their_comments_are_preserved_verbatim(script):
    out, _ = merge(script, WORK)
    d = parse(out)
    assert d["instructions"] == ["/home/example/memory/MEMORY.md"]
    assert sorted(d["mcp"]) == ["servers", "warehouse", "wiki"]
    assert d["mcp"]["wiki"]["url"] == "https://wiki.example.invalid/mcp"
    assert "// WORK-ONLY. Memory index loaded every session." in out
    assert "// WORK-ONLY. Internal servers. Note the // inside these URLs" in out


def test_double_slash_inside_a_string_is_not_treated_as_a_comment(script):
    src = (
        '{\n  "permission": { "edit": "ask" },\n'
        '  "share": "https://example.invalid//double//slash"\n}\n'
    )
    out, _ = merge(script, src)
    assert parse(out)["share"] == "https://example.invalid//double//slash"


def test_non_ascii_survives_under_a_c_locale(script):
    src = (
        '{\n  "permission": { "edit": "ask" },\n'
        '  "mcp": { "n": { "description": "caf\u00e9 \u2713 \u65e5\u672c\u8a9e" } }\n}\n'
    )
    out, _ = merge(script, src, env={"LC_ALL": "C", "LANG": "C"})
    assert parse(out)["mcp"]["n"]["description"] == "caf\u00e9 \u2713 \u65e5\u672c\u8a9e"


def test_trailing_comma_is_fixed_when_an_owned_key_was_last(script):
    """Dropping a trailing `plugin` must not leave `permission` comma-terminated."""
    src = (
        '{\n  "permission": { "edit": "deny" },\n'
        '  "plugin": [\n    "stale@0.0.1"\n  ]\n}\n'
    )
    out, _ = merge(script, src)
    assert strict_json_keys(out) == ["$schema", "agents", "mcp", "permission", "plugins"]


# --- idempotence ------------------------------------------------------------

@pytest.mark.parametrize(
    "src",
    [
        "",
        WORK,
        LEGACY_SEED,
        AGENTS_WITH_PRIVATE,
        AGENTS_WITH_BUILTIN_FIELDS,
        '{\n}\n',
        '{\n  "permission": {}\n}\n',
        '{\n  "permissions": []\n}\n',
    ],
)
def test_idempotent_across_repeated_applies(script, src):
    first, _ = merge(script, src)
    second, _ = merge(script, first)
    third, _ = merge(script, second)
    assert first == second == third


def test_output_always_ends_with_exactly_one_newline(script):
    out, _ = merge(script, '{\n  "permission": { "edit": "deny" }\n}')  # no final \n
    assert out.endswith("}\n")
    assert not out.endswith("\n\n")


# --- safety -----------------------------------------------------------------

@pytest.mark.parametrize(
    "src,reason",
    [
        ('{\n  "$schema": "x",\n  "plugin": [\n', "no complete top-level JSON object"),
        ('{ "$schema": "x", "permission": {} }\n', "single line"),
    ],
)
def test_unparseable_input_passes_through_untouched_with_a_warning(script, src, reason):
    out, err = merge(script, src)
    assert out == src, "a hand-edited target must never be destroyed"
    assert reason in err


def test_json_module_is_never_used_to_rewrite_the_file(script):
    """Guard the core design decision: a json round-trip would delete comments."""
    code = "\n".join(
        line for line in Path(script).read_text().splitlines()
        if not line.lstrip().startswith("#")
    )
    assert "json.dumps" not in code
    assert "json.dump(" not in code


def test_no_work_specific_content_in_public_opencode_merge_template():
    """The public merge template must not contain private hostnames or paths.

    Deliberately shape-based rather than a list of literal names. This test file
    is itself committed to the public repo, so spelling out an employer or vendor
    to grep for would reintroduce exactly the strings it is meant to keep out.
    Matching on the SHAPE work content takes (absolute home paths carrying a
    username, corporate/internal/LAN hostnames) is both name-free and broader
    than any fixed list.
    """
    body = TMPL.read_text().lower()
    forbidden = (
        (r"/users/[a-z]", "absolute macOS home path with a username"),
        (r"/home/[a-z]", "absolute Linux home path with a username"),
        (r"\bcorp\.", "corporate internal domain"),
        (r"\binternal\.", "internal hostname"),
        (r"\.lan\b", "private LAN hostname"),
        (r"\bwiki\.", "internal wiki hostname"),
    )
    for pattern, label in forbidden:
        assert not re.search(pattern, body), (
            f"{label} in public source, matched /{pattern}/"
        )
