#!/usr/bin/env bats
# tests/test_git_override.bats
# Verify the public Git config never owns identity data or private overrides.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
GIT_CONFIG="$REPO_ROOT/home/dot_gitconfig"
INSTALLER="$REPO_ROOT/scripts/install.sh"

run_config_only_install() {
  env HOME="$HOME" DOTFILES_INSTALL_MODE=configs \
    INSTALL_GIT_CONFIG=true INSTALL_ZSH=false INSTALL_TMUX=false \
    INSTALL_NEOVIM=false INSTALL_NOTIFY=false \
    INSTALL_AI_CODECOMPANION=false INSTALL_AI_STATUSLINE=false \
    INSTALL_AI_OPENCODE=false INSTALL_AI_COPILOT=false \
    INSTALL_TERMINAL_GHOSTTY=false INSTALL_TERMINAL_ITERM2=false \
    bash "$INSTALLER"
}

@test "managed Git config contains no identity or signing values" {
  run grep -Ei '^[[:space:]]*(name|email|signingkey|gpgsign)[[:space:]]*=' "$GIT_CONFIG"
  [ "$status" -eq 1 ]
  grep -Fq 'path = ~/.gitconfig.override' "$GIT_CONFIG"
  # This test intentionally searches for an unexpanded literal tilde.
  # shellcheck disable=SC2088
  run grep -F '~/.config/git/override.conf' "$GIT_CONFIG"
  [ "$status" -eq 1 ]
}

@test "config-only install creates a private override stub" {
  local test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home"

  HOME="$test_home" run run_config_only_install

  [ "$status" -eq 0 ]
  [ -f "$test_home/.gitconfig.override" ]
  [ ! -s "$test_home/.gitconfig.override" ]
  if [[ "$(uname -s)" == Darwin ]]; then
    mode=$(stat -f '%Lp' "$test_home/.gitconfig.override")
  else
    mode=$(stat -c '%a' "$test_home/.gitconfig.override")
  fi
  [ "$mode" = 600 ]
}

@test "installer never overwrites an existing private override" {
  local test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home"
  printf '[alias]\n    identity-example = status\n' >"$test_home/.gitconfig.override"

  HOME="$test_home" run run_config_only_install

  [ "$status" -eq 0 ]
  grep -Fq 'identity-example = status' "$test_home/.gitconfig.override"
}
