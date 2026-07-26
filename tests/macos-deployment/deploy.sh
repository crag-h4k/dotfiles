#!/usr/bin/env bash
# Run a native, fully headless macOS package-mode deployment from the clean
# source tree prepared by build.sh.
set -euo pipefail

fail() {
    printf 'macOS deployment: %s\n' "$*" >&2
    exit 1
}

[[ "$(uname -s)" == Darwin ]] || fail "must run on macOS"
[[ "$(id -u)" -ne 0 ]] || fail "must run as a non-root user"
[[ ! -t 0 ]] || fail "stdin must be non-interactive"
sudo -n true || fail "the CI runner must provide non-interactive sudo"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
default_source=$(cd "$script_dir/../.." && pwd)
source_dir="${DOTFILES_SOURCE:-$default_source}"
[[ -d "$source_dir/home" ]] ||
    fail "chezmoi source root is missing from $source_dir"

for command_name in brew chezmoi; do
    command -v "$command_name" >/dev/null ||
        fail "required command missing: $command_name"
done

config_dir="$HOME/.config/chezmoi"
mkdir -p "$config_dir"
printf '%s\n' \
    '[data]' \
    'componentSelection = "1 2 4"' \
    'gitSelection = "1 3"' \
    'aiSelection = ""' \
    'terminalSelection = ""' \
    'palette = "dracula"' \
    'zshTheme = "gud"' \
    'installMode = "packages"' \
    >"$config_dir/chezmoi.toml"

export CI=true
export DOTFILES_ASSUME_YES=1
export DOTFILES_INSTALL_MODE=packages
export DOTFILES_NO_TUI=1
export GIT_ASKPASS=/usr/bin/false
export GIT_TERMINAL_PROMPT=0
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export NONINTERACTIVE=1
export NPM_CONFIG_YES=true
export PIP_NO_INPUT=1
export SSH_ASKPASS=/usr/bin/false
export SUDO_ASKPASS=/usr/bin/false
brew_prefix=$(brew --prefix)
export PATH="$brew_prefix/bin:$PATH"

chezmoi init \
    --apply \
    --no-tty \
    --source "$source_dir" \
    </dev/null

for command_name in chezmoi gh git tmux zoxide zsh; do
    command -v "$command_name" >/dev/null ||
        fail "expected deployed command missing: $command_name"
done
for managed_file in .zshrc .tmux.conf .gitconfig .gitignore_global; do
    [[ -f "$HOME/$managed_file" ]] ||
        fail "expected managed file missing: $HOME/$managed_file"
done
[[ ! -e "$HOME/.config/nvim/init.lua" ]] ||
    fail "Neovim config was deployed despite the focused component selection"

printf 'Headless macOS package-mode chezmoi deployment passed as uid=%s\n' \
    "$(id -u)"
