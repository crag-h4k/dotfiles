# tests/test_merge_opencode_config.py
"""Tests for home/dot_config/opencode/modify_opencode.jsonc.tmpl (chezmoi modify_).

opencode.jsonc is JSONC and its comments are load-bearing (the per-plugin
supply-chain audit and permission rationale), so the merge script does line-level
surgery and never round-trips
the file through json.loads/json.dumps. These tests pin that contract:

  OWNED   schema, built-in agent colors, and V2 plugins are re-asserted.
  SEEDED  native "permissions" are written only when no policy exists.
  KEPT    every other top-level key survives byte-for-byte, comments included.

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
import tempfile
from fnmatch import fnmatchcase
from pathlib import Path

import pytest

REPO = Path(__file__).parent.parent
TMPL = REPO / "home" / "dot_config" / "opencode" / "modify_opencode.jsonc.tmpl"

pytestmark = pytest.mark.skipif(
    shutil.which("chezmoi") is None, reason="chezmoi not installed"
)


@pytest.fixture(scope="module")
def script() -> str:
    """Render the modify_ template the way chezmoi will, return the script path."""
    out = subprocess.run(
        ["chezmoi", "execute-template", "--source", str(REPO)],
        stdin=TMPL.open(), capture_output=True, text=True, check=True,
    ).stdout
    path = Path(tempfile.mkdtemp()) / "merge.py"
    path.write_text(out)
    return str(path)


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
    "local-helper": {
      "description": "Preserve every custom agent"
    }
  }
}
"""


# --- owned ------------------------------------------------------------------

def test_empty_stdin_seeds_a_complete_generic_file(script):
    out, _ = merge(script, "")
    assert strict_json_keys(out) == ["$schema", "agents", "permissions", "plugins"]
    d = parse(out)
    assert d["$schema"] == "https://opencode.ai/config.json"
    assert set(d["agents"]) == {"build", "plan"}
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", d["agents"]["build"]["color"])
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", d["agents"]["plan"]["color"])
    assert d["agents"]["build"]["color"] != d["agents"]["plan"]["color"]
    assert d["plugins"] == ["opencode-copilot-statusline@1.0.0"]
    # A fresh host must not come up unguarded.
    assert d["permissions"][0] == {
        "action": "*", "resource": "*", "effect": "ask",
    }


def test_owned_comments_survive_because_nothing_is_reserialized(script):
    out, _ = merge(script, "")
    for comment in (
        "// OpenCode V2 plugins, EXACT-pinned.",
        "// Prompt metadata uses each agent's configured color.",
        "// Permission model: ask by default",
        "// Final denials override saved approvals",
    ):
        assert comment in out, f"lost load-bearing comment: {comment}"


def test_v1_plugin_is_removed_and_v2_plugins_are_asserted(script):
    out, _ = merge(script, WORK)
    assert "stale@0.0.1" not in out
    assert "stale-v2@0.0.1" not in out
    assert "plugin" not in parse(out)
    assert parse(out)["plugins"][-1] == "opencode-copilot-statusline@1.0.0"


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
    assert agents["local-helper"] == {
        "description": "Preserve every custom agent"
    }
    assert "// Keep the Build entry comment too." in out
    assert "// Keep the custom Build description and request settings." in out
    assert "// Keep the color rationale while replacing only its value." in out
    assert "// Keep this inline note." in out
    assert "// Plan intentionally omitted color before the merge." in out


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
    assert parse(out)["permissions"] == [
        {"action": "shell", "resource": "custom *", "effect": "allow"}
    ]
    assert "// Local policy stays private and unchanged." in out


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
        ("aws_documentation_*", "*", "allow"),
        ("terraform_get_*", "*", "allow"),
        ("confluence_confluence_get_*", "*", "allow"),
        ("databricks_list_*", "*", "allow"),
        ("browser_snapshot", "*", "allow"),
        ("opencode_models", "*", "allow"),
        ("shell", "pdftotext * -", "allow"),
        ("shell", "pre-commit *", "allow"),
        ("shell", "gh pr view *", "allow"),
    ):
        assert rule in triples

    for resource in ("git add *", "git commit *", "git rm *", "rm -rf *"):
        assert ("shell", resource, "deny") in triples
    assert triples.index(("shell", "git add *", "deny")) > triples.index(
        ("shell", "git status *", "allow")
    )
    assert triples.index(("read", "*.env", "deny")) > triples.index(
        ("read", "*", "allow")
    )

    resources = {resource for action, resource, effect in triples if action == "shell" and effect == "allow"}
    assert "gh api *" not in resources
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
        "aws_documentation_read_documentation",
        "terraform_get_provider_details",
        "confluence_confluence_get_page",
        "databricks_list_jobs",
        "browser_snapshot",
        "opencode_models",
    ):
        assert permission_effect(rules, action, "*") == "allow", action

    for action in (
        "aws_iam_policy_autopilot_fix_access_denied",
        "aws_mcp_aws___run_script",
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
    assert permission_effect(rules, "shell", "gh api repos/example/project") == "ask"
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


def test_hard_denials_cover_git_global_options_and_recursive_rm(script):
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
        assert permission_effect(rules, "shell", command) == "deny", command

    shell_rules = [rule for rule in rules if rule["action"] == "shell"]
    last_allow = max(
        i for i, rule in enumerate(shell_rules) if rule["effect"] == "allow"
    )
    first_deny = min(
        i for i, rule in enumerate(shell_rules) if rule["effect"] == "deny"
    )
    assert first_deny > last_allow


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
    assert sorted(d["mcp"]) == ["warehouse", "wiki"]
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
    assert strict_json_keys(out) == ["$schema", "agents", "permission", "plugins"]


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
    assert "json.loads" not in code
    assert "import json" not in code


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


def test_unused_import_json_is_absent():
    assert "json" not in {
        line.split()[1] for line in TMPL.read_text().splitlines()
        if line.startswith("import ")
    }
