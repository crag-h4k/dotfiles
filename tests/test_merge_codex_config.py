# tests/test_merge_codex_config.py
"""Tests for dot_codex/modify_private_config.toml (chezmoi modify_ script).

The script is a stdin->stdout transformer: chezmoi pipes the current
~/.codex/config.toml content in and reads the merged result from stdout. It
injects the top-level `notify` (tmux hook) and `tui.notifications` (Codex's
built-in approval alert) keys WITHOUT clobbering the [projects.*] / [tui.*]
tables Codex writes at runtime. Tests pipe TOML in directly and assert on the
output.
"""
import os
import subprocess
import sys
import tomllib
from pathlib import Path

SCRIPT = Path(__file__).parent.parent / "dot_codex" / "modify_private_config.toml"
HOOK = os.path.expanduser("~/.codex/hooks/notify-tmux.sh")
NOTIFS = ["agent-turn-complete", "approval-requested"]


def run_script(config_toml: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=config_toml,
        capture_output=True,
        text=True,
    )


def test_empty_adds_both_keys():
    result = run_script("")
    assert result.returncode == 0
    data = tomllib.loads(result.stdout)
    assert data["notify"] == [HOOK]
    assert data["tui"]["notifications"] == NOTIFS


def test_idempotent_second_run():
    first = run_script("").stdout
    second = run_script(first).stdout
    assert first == second


def test_preserves_existing_tables():
    existing = (
        '[projects."/Users/dane/work"]\n'
        'trust_level = "trusted"\n\n'
        "[tui.model_availability_nux]\n"
        '"gpt-5.5" = 1\n'
    )
    result = run_script(existing)
    assert result.returncode == 0
    data = tomllib.loads(result.stdout)
    assert data["notify"] == [HOOK]
    assert data["tui"]["notifications"] == NOTIFS
    # Injected tui.notifications coexists with Codex's tui subtable.
    assert data["tui"]["model_availability_nux"]["gpt-5.5"] == 1
    assert data["projects"]["/Users/dane/work"]["trust_level"] == "trusted"


def test_replaces_stale_keys_without_duplicating():
    stale = (
        'notify = ["/old/path"]\n'
        'tui.notifications = ["agent-turn-complete"]\n'
        "other = 1\n\n"
        '[projects."/p"]\n'
        "x = true\n"
    )
    result = run_script(stale)
    assert result.returncode == 0
    data = tomllib.loads(result.stdout)
    assert data["notify"] == [HOOK]
    assert data["tui"]["notifications"] == NOTIFS
    # Stale top-level keys are replaced, not duplicated.
    assert result.stdout.count("notify =") == 1
    assert result.stdout.count("tui.notifications =") == 1
    # Unrelated top-level keys and tables are preserved.
    assert data["other"] == 1
    assert data["projects"]["/p"]["x"] is True


def test_bare_tui_table_stays_valid_toml():
    # A bare [tui] header must not collide with a top-level `tui.notifications`
    # dotted key (that would define table `tui` twice and make the file
    # unparseable). notifications must be folded INTO the [tui] table instead.
    existing = "[tui]\n" 'theme = "dark"\n'
    result = run_script(existing)
    assert result.returncode == 0
    data = tomllib.loads(result.stdout)  # must round-trip
    assert data["notify"] == [HOOK]
    assert data["tui"]["notifications"] == NOTIFS
    assert data["tui"]["theme"] == "dark"
    # Folded in, not emitted as a top-level dotted key.
    assert "tui.notifications" not in result.stdout


def test_bare_tui_idempotent_and_replaces_stale_notifications():
    existing = "[tui]\n" 'notifications = ["agent-turn-complete"]\n' 'theme = "dark"\n'
    first = run_script(existing).stdout
    data = tomllib.loads(first)
    assert data["tui"]["notifications"] == NOTIFS
    assert data["tui"]["theme"] == "dark"
    # Stale value replaced, not duplicated.
    assert first.count("notifications =") == 1
    # Re-running is a no-op.
    second = run_script(first).stdout
    assert first == second
