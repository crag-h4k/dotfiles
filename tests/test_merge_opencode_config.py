# tests/test_merge_opencode_config.py
"""Tests for home/dot_config/opencode/modify_opencode.jsonc.tmpl (chezmoi modify_).

opencode.jsonc is JSONC and its comments are load-bearing (the per-plugin
supply-chain audit, the cc-safety-net fails-OPEN warning, the permission
rationale), so the merge script does line-level surgery and never round-trips
the file through json.loads/json.dumps. These tests pin that contract:

  OWNED   schema, built-in agent colors, and V1/V2 plugins are re-asserted.
  SEEDED  "permission" is written only when the incoming file has none.
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
from pathlib import Path

import pytest

TMPL = (
    Path(__file__).parent.parent
    / "home" / "dot_config" / "opencode" / "modify_opencode.jsonc.tmpl"
)

pytestmark = pytest.mark.skipif(
    shutil.which("chezmoi") is None, reason="chezmoi not installed"
)


@pytest.fixture(scope="module")
def script() -> str:
    """Render the modify_ template the way chezmoi will, return the script path."""
    out = subprocess.run(
        ["chezmoi", "execute-template"],
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


# --- owned ------------------------------------------------------------------

def test_empty_stdin_seeds_a_complete_generic_file(script):
    out, _ = merge(script, "")
    assert strict_json_keys(out) == ["$schema", "agents", "permission", "plugin", "plugins"]
    d = parse(out)
    assert d["$schema"] == "https://opencode.ai/config.json"
    assert set(d["agents"]) == {"build", "plan"}
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", d["agents"]["build"]["color"])
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", d["agents"]["plan"]["color"])
    assert d["agents"]["build"]["color"] != d["agents"]["plan"]["color"]
    assert d["plugin"] == [
        "@slkiser/opencode-quota@4.9.0",
        "@tarquinen/opencode-dcp@3.1.15",
        "cc-safety-net@2.3.4",
    ]
    assert d["plugins"] == ["opencode-copilot-statusline@1.0.0"]
    # A fresh host must not come up unguarded.
    assert d["permission"]["edit"] == "ask"
    assert d["permission"]["bash"]["*"] == "ask"


def test_owned_comments_survive_because_nothing_is_reserialized(script):
    out, _ = merge(script, "")
    for comment in (
        "// OpenCode V1 plugins, EXACT-pinned.",
        "// OpenCode V2 plugins, EXACT-pinned.",
        "// Prompt metadata uses each agent's configured color.",
        '// "@leohenon/opencode-vim-plugin@0.1.6",',
        "fails OPEN silently",
        "// Permission model: edit asks before writing",
    ):
        assert comment in out, f"lost load-bearing comment: {comment}"


def test_plugin_array_is_asserted_over_a_local_edit(script):
    out, _ = merge(script, WORK)
    assert "stale@0.0.1" not in out
    assert "stale-v2@0.0.1" not in out
    assert parse(out)["plugin"][-1] == "cc-safety-net@2.3.4"
    assert parse(out)["plugins"][-1] == "opencode-copilot-statusline@1.0.0"


# --- seeded -----------------------------------------------------------------

def test_existing_permission_is_never_overwritten(script):
    out, _ = merge(script, WORK)
    perm = parse(out)["permission"]
    assert perm["edit"] == "allow"
    assert perm["bash"]["terraform plan *"] == "allow"
    # The seed must not leak in alongside it.
    assert "prettier *" not in out
    assert "// LOCAL EDIT: loosened on this host" in out


def test_seed_only_fires_when_permission_is_absent(script):
    out, _ = merge(script, '{\n  "instructions": ["/x"]\n}\n')
    assert parse(out)["permission"]["edit"] == "ask"
    out2, _ = merge(script, '{\n  "permission": { "edit": "deny" }\n}\n')
    assert parse(out2)["permission"] == {"edit": "deny"}


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
    assert strict_json_keys(out) == ["$schema", "agents", "permission", "plugin", "plugins"]


# --- idempotence ------------------------------------------------------------

@pytest.mark.parametrize("src", ["", WORK, '{\n}\n', '{\n  "permission": {}\n}\n'])
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


def test_no_work_specific_content_in_the_public_source():
    """The source tree is a public repo; work hostnames/paths must never land.

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
