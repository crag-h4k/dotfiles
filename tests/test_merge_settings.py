# tests/test_merge_settings.py
"""Tests for dot_claude/modify_settings.json (chezmoi modify_ script).

The script is a stdin->stdout transformer: chezmoi pipes the current
settings.json content in and reads the merged result from stdout. Tests
pipe JSON in directly and assert on the output.
"""
import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).parent.parent / "dot_claude" / "modify_settings.json"
HOOK = "~/.claude/hooks/notify-tmux.sh"
CLEAR = "~/.claude/hooks/notify-clear.sh"


def run_script(settings_json: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=settings_json,
        capture_output=True,
        text=True,
    )


def all_hooks_present(data: dict) -> bool:
    hooks = data.get("hooks", {})
    stop_cmds = [h.get("command") for g in hooks.get("Stop", []) for h in g.get("hooks", [])]
    notif_cmds = [h.get("command") for g in hooks.get("Notification", []) for h in g.get("hooks", [])]
    pre_cmds = [
        h.get("command")
        for g in hooks.get("PreToolUse", [])
        if g.get("matcher") == "AskUserQuestion"
        for h in g.get("hooks", [])
    ]
    clear_cmds = [
        h.get("command") for g in hooks.get("UserPromptSubmit", []) for h in g.get("hooks", [])
    ]
    return HOOK in stop_cmds and HOOK in notif_cmds and HOOK in pre_cmds and CLEAR in clear_cmds


def test_empty_settings_adds_all_four_hooks():
    result = run_script("{}\n")
    assert result.returncode == 0
    data = json.loads(result.stdout)
    assert all_hooks_present(data)


def test_idempotent_second_run():
    first_out = run_script("{}\n").stdout
    second_out = run_script(first_out).stdout
    assert json.loads(first_out) == json.loads(second_out)


def test_partial_hooks_gets_remainder():
    partial = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": HOOK}]}]}}
    result = run_script(json.dumps(partial))
    assert result.returncode == 0
    data = json.loads(result.stdout)
    assert all_hooks_present(data)


def test_preserves_unrelated_settings():
    existing = {"model": "claude-sonnet-4-6", "effortLevel": "high"}
    result = run_script(json.dumps(existing))
    assert result.returncode == 0
    data = json.loads(result.stdout)
    assert data["model"] == "claude-sonnet-4-6"
    assert data["effortLevel"] == "high"
