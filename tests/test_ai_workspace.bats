#!/usr/bin/env bats
# Shared AI workspace migration and per-entry overlay discovery.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-ai-workspace.sh"

setup() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  AI_ROOT="$BATS_TEST_TMPDIR/shared-ai"
  mkdir -p \
    "$TEST_HOME/.claude/agents" \
    "$TEST_HOME/.claude/skills" \
    "$TEST_HOME/.codex/skills/.system" \
    "$TEST_HOME/.codex/rules"
  printf 'private work agent\n' > "$TEST_HOME/.claude/agents/work-only.md"
  printf 'leave runtime state here\n' > "$TEST_HOME/.codex/history.jsonl"
  printf 'prefix_rule(pattern=["git", "status"], decision="allow")\n' \
    > "$TEST_HOME/.codex/rules/default.rules"
}

run_installer() {
  run env \
    HOME="$TEST_HOME" \
    DOTFILES_AI_DIR="$AI_ROOT" \
    INSTALL_AI_SHARED_WORKSPACE=true \
    INSTALL_AI_CLAUDE_HOOKS=true \
    INSTALL_AI_CODEX_HOOKS=true \
    bash "$INSTALLER"
}

@test "shared resources overlay both tools one entry at a time" {
  run_installer
  [ "$status" -eq 0 ]

  [ -d "$TEST_HOME/.claude/skills" ]
  [ ! -L "$TEST_HOME/.claude/skills" ]
  [ "$(readlink "$TEST_HOME/.claude/skills/interview-coach")" = \
    "$AI_ROOT/skills/interview-coach" ]
  [ "$(readlink "$TEST_HOME/.codex/skills/interview-coach")" = \
    "$AI_ROOT/skills/interview-coach" ]
  [ "$(readlink "$AI_ROOT/skills/interview-coach")" = \
    "$REPO_ROOT/ai/skills/interview-coach" ]

  [ -d "$TEST_HOME/.claude/agents" ]
  [ ! -L "$TEST_HOME/.claude/agents" ]
  [ -f "$TEST_HOME/.claude/agents/work-only.md" ]
  [ "$(readlink "$TEST_HOME/.claude/agents/dotfiles-maintainer.md")" = \
    "$AI_ROOT/agents/claude/dotfiles-maintainer.md" ]
  [ "$(readlink "$TEST_HOME/.codex/agents/dotfiles-maintainer.toml")" = \
    "$AI_ROOT/agents/codex/dotfiles-maintainer.toml" ]

  [ -d "$TEST_HOME/.claude/hooks" ]
  [ ! -L "$TEST_HOME/.claude/hooks" ]
  [ "$(readlink "$TEST_HOME/.claude/hooks/notify-tmux.sh")" = \
    "$AI_ROOT/hooks/claude/notify-tmux.sh" ]
  [ "$(readlink "$TEST_HOME/.codex/hooks/notify-tmux.sh")" = \
    "$AI_ROOT/hooks/codex/notify-tmux.sh" ]

  [ "$(readlink "$TEST_HOME/.claude/CLAUDE.md")" = "$AI_ROOT/AGENTS.md" ]
  [ "$(readlink "$TEST_HOME/.codex/AGENTS.md")" = "$AI_ROOT/AGENTS.md" ]
  grep -q "$AI_ROOT" "$AI_ROOT/AGENTS.md"
  run grep -q '@@AI_DIRECTORY@@' "$AI_ROOT/AGENTS.md"
  [ "$status" -eq 1 ]
}

@test "native rules, system skills, and runtime state stay untouched" {
  run_installer
  [ "$status" -eq 0 ]

  [ -f "$TEST_HOME/.codex/rules/default.rules" ]
  [ ! -L "$TEST_HOME/.codex/rules" ]
  [ -d "$TEST_HOME/.codex/skills/.system" ]
  [ -f "$TEST_HOME/.codex/history.jsonl" ]
}

@test "additional configured roots merge private entries without entering dotfiles" {
  WORK_ROOT="$BATS_TEST_TMPDIR/work-ai"
  mkdir -p "$AI_ROOT" "$WORK_ROOT/skills/company-skill" "$WORK_ROOT/agents/claude"
  printf '%s\n' "$WORK_ROOT" > "$AI_ROOT/overlays.conf"
  printf '%s\n' '# Company skill' > "$WORK_ROOT/skills/company-skill/SKILL.md"
  printf '%s\n' '# Company agent' > "$WORK_ROOT/agents/claude/company-agent.md"

  run_installer
  [ "$status" -eq 0 ]

  [ "$(readlink "$AI_ROOT/skills/company-skill")" = \
    "$WORK_ROOT/skills/company-skill" ]
  [ "$(readlink "$TEST_HOME/.claude/skills/company-skill")" = \
    "$AI_ROOT/skills/company-skill" ]
  [ "$(readlink "$TEST_HOME/.codex/skills/company-skill")" = \
    "$AI_ROOT/skills/company-skill" ]
  [ "$(readlink "$TEST_HOME/.claude/agents/company-agent.md")" = \
    "$AI_ROOT/agents/claude/company-agent.md" ]
}

@test "removing a configured root removes only its recorded overlay links" {
  WORK_ROOT="$BATS_TEST_TMPDIR/removable-work-ai"
  mkdir -p "$AI_ROOT" "$WORK_ROOT/skills/removable-skill"
  printf '%s\n' "$WORK_ROOT" > "$AI_ROOT/overlays.conf"
  printf '%s\n' '# Removable skill' > "$WORK_ROOT/skills/removable-skill/SKILL.md"

  run_installer
  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.claude/skills/removable-skill" ]
  [ -f "$TEST_HOME/.claude/agents/work-only.md" ]

  printf '%s\n' '# No additional roots.' > "$AI_ROOT/overlays.conf"
  run_installer
  [ "$status" -eq 0 ]
  [ ! -e "$AI_ROOT/skills/removable-skill" ]
  [ ! -L "$TEST_HOME/.claude/skills/removable-skill" ]
  [ -f "$TEST_HOME/.claude/agents/work-only.md" ]
}

@test "same-named native entries win overlay collisions" {
  printf 'private override\n' > "$TEST_HOME/.claude/agents/dotfiles-maintainer.md"

  run_installer
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/.claude/agents/dotfiles-maintainer.md")" = \
    "private override" ]
  [ ! -L "$TEST_HOME/.claude/agents/dotfiles-maintainer.md" ]
  [[ "$output" == *"keeping existing entry"* ]]
}

@test "legacy whole-directory links migrate to per-entry overlays" {
  mkdir -p "$AI_ROOT/agents/claude"
  printf 'legacy private agent\n' > "$AI_ROOT/agents/claude/legacy.md"
  mv "$TEST_HOME/.claude/agents/work-only.md" "$AI_ROOT/agents/claude/work-only.md"
  rmdir "$TEST_HOME/.claude/agents"
  ln -s "$AI_ROOT/agents/claude" "$TEST_HOME/.claude/agents"

  run_installer
  [ "$status" -eq 0 ]
  [ -d "$TEST_HOME/.claude/agents" ]
  [ ! -L "$TEST_HOME/.claude/agents" ]
  [ "$(readlink "$TEST_HOME/.claude/agents/legacy.md")" = \
    "$AI_ROOT/agents/claude/legacy.md" ]
}

@test "installer creates an editable private overlay config and sync helper" {
  run_installer
  [ "$status" -eq 0 ]
  [ -f "$AI_ROOT/overlays.conf" ]
  [ "$(stat -c '%a' "$AI_ROOT/overlays.conf" 2>/dev/null || stat -f '%Lp' "$AI_ROOT/overlays.conf")" = "600" ]
  [ "$(readlink "$AI_ROOT/scripts/sync-overlays")" = \
    "$REPO_ROOT/scripts/sync-ai-overlays.sh" ]
}

@test "sync helper discovers entries added after the initial apply" {
  run_installer
  [ "$status" -eq 0 ]

  WORK_ROOT="$BATS_TEST_TMPDIR/later-work-ai"
  STUB_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$WORK_ROOT/skills/later-skill" "$STUB_DIR"
  printf '%s\n' '# Later skill' > "$WORK_ROOT/skills/later-skill/SKILL.md"
  printf '%s\n' "$WORK_ROOT" >> "$AI_ROOT/overlays.conf"
  cat > "$STUB_DIR/chezmoi" <<STUB
#!/bin/sh
printf '%s\n' "$REPO_ROOT/home"
STUB
  chmod +x "$STUB_DIR/chezmoi"

  run env HOME="$TEST_HOME" PATH="$STUB_DIR:/usr/bin:/bin" \
    "$AI_ROOT/scripts/sync-overlays"
  [ "$status" -eq 0 ]
  [ "$(readlink "$TEST_HOME/.claude/skills/later-skill")" = \
    "$AI_ROOT/skills/later-skill" ]
  [ "$(readlink "$TEST_HOME/.codex/skills/later-skill")" = \
    "$AI_ROOT/skills/later-skill" ]
}

@test "installer is idempotent" {
  run_installer
  [ "$status" -eq 0 ]
  first_target="$(readlink "$TEST_HOME/.codex/skills/chezmoi-dotfiles")"

  run_installer
  [ "$status" -eq 0 ]
  [ "$(readlink "$TEST_HOME/.codex/skills/chezmoi-dotfiles")" = "$first_target" ]
  [ "$(find "$AI_ROOT/.dotfiles-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" -le 1 ]
}

@test "relative AI roots are rejected" {
  run env \
    HOME="$TEST_HOME" \
    DOTFILES_AI_DIR="relative/ai" \
    INSTALL_AI_SHARED_WORKSPACE=true \
    bash "$INSTALLER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be absolute"* ]]
}
