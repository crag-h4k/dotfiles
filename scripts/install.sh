#!/usr/bin/env bash
# Top-level installer. Driven by chezmoi: run_once_after_00-install.sh exports
# the component selection (made at `chezmoi init`) as INSTALL_* env vars and
# then calls this script. It installs only the packages for the selected
# components. It does NOT call `chezmoi apply` - chezmoi invokes this script,
# so applying again would recurse.
#
# Standalone use is supported too: the INSTALL_* vars default to zsh+tmux+neovim
# on, gitconfig off, when unset.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Component flags, read from the environment (set by chezmoi via
# run_once_after_00-install.sh). Defaults apply only for standalone runs.
INSTALL_ZSH="${INSTALL_ZSH:-true}"
INSTALL_TMUX="${INSTALL_TMUX:-true}"
INSTALL_NEOVIM="${INSTALL_NEOVIM:-true}"
INSTALL_GITCONFIG="${INSTALL_GITCONFIG:-false}"

# Show an existing gitconfig file then prompt to create/replace from repo example.
_setup_gitconfig_file() {
    local target="$1" example="$2" label="$3"
    if [[ -f "$target" ]]; then
        info "existing $target:"
        cat "$target"
        printf '\n%s already exists. Replace with repo example? [y/N] ' "$target"
    else
        printf 'No %s found. Create from repo example? [y/N] ' "$target"
    fi
    local resp
    read -r resp
    if [[ "$resp" =~ ^[Yy]$ ]]; then
        cp "$example" "$target"
        info "copied $label -> $target"
    fi
}

main() {
    local os
    os=$(os_detect)
    info "dotfiles installer: platform=$os"
    info "components: zsh=$INSTALL_ZSH tmux=$INSTALL_TMUX neovim=$INSTALL_NEOVIM gitconfig=$INSTALL_GITCONFIG"

    # Base toolchain - required by all per-app scripts and by ensure_chezmoi.
    case "$os" in
        macos)
            require_cmd brew
            brew install git make curl
            ;;
        debian)
            sudo apt-get update
            sudo apt-get install -y git make curl ca-certificates
            ;;
        *)
            die "unsupported OS: $(uname -s)"
            ;;
    esac

    ensure_chezmoi

    # Convenience symlink: ~/dotfiles -> ~/.local/share/chezmoi
    local chezmoi_src="$HOME/.local/share/chezmoi"
    local dotfiles_link="$HOME/dotfiles"
    if [[ -d "$chezmoi_src" && ! -e "$dotfiles_link" ]]; then
        ln -s "$chezmoi_src" "$dotfiles_link"
        info "created symlink $dotfiles_link -> $chezmoi_src"
    fi

    [[ "$INSTALL_ZSH" == true ]]    && bash "$SCRIPT_DIR/install-zsh.sh"
    [[ "$INSTALL_TMUX" == true ]]   && bash "$SCRIPT_DIR/install-tmux.sh"
    [[ "$INSTALL_NEOVIM" == true ]] && bash "$SCRIPT_DIR/install-neovim.sh"

    if [[ "$INSTALL_GITCONFIG" == true ]]; then
        _setup_gitconfig_file "$HOME/.gitconfig"          "$SCRIPT_DIR/../gitconfig.example"          "gitconfig.example"
        _setup_gitconfig_file "$HOME/.gitconfig.personal" "$SCRIPT_DIR/../gitconfig.personal.example" "gitconfig.personal.example"
    fi

    info "all done. Open a new shell (zsh) and tmux/nvim to verify."
}

main "$@"
