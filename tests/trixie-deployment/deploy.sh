#!/usr/bin/env bash
# Exercise the same unattended, package-enabled chezmoi deployment used on a
# fresh Debian Trixie workstation. The image deliberately contains a pre-existing,
# active GitHub CLI apt source with an alternate Signed-By path.
set -euo pipefail

SOURCE_DIR=/home/dotfiles/source
CONFIG_DIR="$HOME/.config/chezmoi"

if [[ "$(id -u)" -eq 0 ]]; then
    printf 'trixie deployment must run as a non-root user\n' >&2
    exit 1
fi
if [[ -t 0 ]]; then
    printf 'trixie deployment must run with non-interactive stdin\n' >&2
    exit 1
fi
sudo -n true

# promptStringOnce reads existing data during init. Seed Zsh, tmux, and shared
# Git configuration so CI is fully headless and runs the real package/repository
# path without paying to install a complete Neovim workstation on every pull
# request. Personal Git identity remains deliberately disabled.
mkdir -p "$CONFIG_DIR"
printf '%s\n' \
    '[data]' \
    'componentSelection = "1 2 4"' \
    'gitSelection = "1 3"' \
    'aiSelection = ""' \
    'terminalSelection = ""' \
    'palette = "dracula"' \
    'zshTheme = "gud"' \
    'installMode = "packages"' \
    > "$CONFIG_DIR/chezmoi.toml"

export CI=true
export APT_LISTCHANGES_FRONTEND=none
export DEBIAN_FRONTEND=noninteractive
export DOTFILES_ASSUME_YES=1
export DOTFILES_INSTALL_MODE=packages
export DOTFILES_NO_TUI=1
export GIT_ASKPASS=/bin/false
export GIT_TERMINAL_PROMPT=0
export NEEDRESTART_MODE=a
export NPM_CONFIG_YES=true
export PIP_NO_INPUT=1
export SSH_ASKPASS=/bin/false
export SUDO_ASKPASS=/bin/false

# Prove the seeded external stanza is valid by itself. On the regression,
# install.sh subsequently added a second stanza and its own apt-get update
# failed because the same URI then had two different Signed-By values.
grep -Fq 'URIs: https://cli.github.com/packages/' \
    /etc/apt/sources.list.d/apt.sources
grep -Fq 'Signed-By: /usr/share/keyrings/githubcli-archive-keyring.gpg' \
    /etc/apt/sources.list.d/apt.sources
sudo -n apt-get update

chezmoi init \
    --apply \
    --no-tty \
    --source "$SOURCE_DIR" \
    </dev/null

# The apply itself has already run apt-get update and installed gh. Confirm the
# migration kept the host source, did not add the conflicting canonical file,
# and left GitHub CLI visible through APT without another network-heavy update.
test -f /etc/apt/sources.list.d/apt.sources
test ! -e /etc/apt/sources.list.d/github-cli.sources
apt-cache policy gh | grep -F 'https://cli.github.com/packages' >/dev/null

# fzf and zoxide install from Debian main for the Zsh component. Confirm APT sees
# them as installed (ghostty is no longer auto-installed on Debian).
dpkg-query -W -f='${Status}\n' fzf | grep -q 'install ok installed'
dpkg-query -W -f='${Status}\n' zoxide | grep -q 'install ok installed'

for command_name in chezmoi git gh tmux zoxide zsh fzf; do
    command -v "$command_name" >/dev/null || {
        printf 'expected deployed command missing: %s\n' "$command_name" >&2
        exit 1
    }
done

test -f "$HOME/.zshrc"
test -f "$HOME/.tmux.conf"
test -f "$HOME/.gitconfig"
test -f "$HOME/.gitignore_global"
test ! -e "$HOME/.config/nvim/init.lua"

printf 'Focused Trixie package-mode chezmoi deployment passed as uid=%s\n' "$(id -u)"
