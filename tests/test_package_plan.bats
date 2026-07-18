#!/usr/bin/env bats
# tests/test_package_plan.bats
# Verify the planner shared by init preview and package installation.

PLANNER="${BATS_TEST_DIRNAME}/../scripts/package-plan.sh"

@test "macOS plan dedupes overlaps and groups every package source" {
  run env DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_ZSH=true INSTALL_TMUX=true INSTALL_NEOVIM=true INSTALL_NOTIFY=true \
    INSTALL_AI_CODECOMPANION=true INSTALL_AI_STATUSLINE=true \
    INSTALL_TERMINAL_GHOSTTY=true INSTALL_TERMINAL_ITERM2=true \
    bash "$PLANNER" --records
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s\n' "$output" | awk -F '\t' 'NF != 4 || ($3 != "installed" && $3 != "planned")')" ]
  [ "$(printf '%s\n' "$output" | grep -c $'^brew-formula\tpython3\t')" -eq 1 ]
  [[ "$output" == *$'brew-cask\tghostty\tplanned\tHomebrew cask'* ]]
  [[ "$output" == *$'npm\t@agentclientprotocol/claude-agent-acp\tplanned\t'* ]]
  [[ "$output" == *$'git-external\ttmux-plugins/tpm\tplanned\t'* ]]
  [[ "$output" == *$'neovim-plugin\tlazy.nvim plugin set\tplanned\t'* ]]
}

@test "Debian AI-hook-only notify plan includes yq without Zsh or tmux externals" {
  run env DOTFILES_PLAN_OS=debian DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_NOTIFY=true bash "$PLANNER" --records
  [ "$status" -eq 0 ]
  [[ "$output" == *$'github-release\tyq\tplanned\t'* ]]
  [[ "$output" != *$'git-external\tohmyzsh/ohmyzsh\t'* ]]
  [[ "$output" != *$'git-external\ttmux-plugins/tpm\t'* ]]
}

@test "configs-only installer does not invoke package or component installers" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  run env DOTFILES_INSTALL_MODE=configs INSTALL_ZSH=true INSTALL_NEOVIM=true \
    INSTALL_TMUX=false INSTALL_NOTIFY=true INSTALL_TERMINAL_GHOSTTY=false \
    INSTALL_TERMINAL_ITERM2=false bash "${BATS_TEST_DIRNAME}/../scripts/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"configs-only mode: skipped packages"* ]]
  [[ "$output" != *"install-zsh:"* ]]
  [[ "$output" != *"install-neovim:"* ]]
}
