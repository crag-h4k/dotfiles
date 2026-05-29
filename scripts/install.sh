#!/usr/bin/env bash
# Top-level installer. Invokes the three per-application scripts in order,
# after ensuring the base toolchain (git, make, curl) is present.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Component flags - all enabled by default.
INSTALL_ZSH=true
INSTALL_TMUX=true
INSTALL_NEOVIM=true
INSTALL_GITCONFIG=true

# Show a numbered menu and let the user pick which components to install.
# Modifies the INSTALL_* globals. Only called when stdin is a tty.
_select_components() {
    printf '\nComponents to install:\n'
    printf '  1) zsh       oh-my-zsh, plugins, custom functions, aliases\n'
    printf '  2) tmux      tmux + plugins (tpm, resurrect, sensible, yank)\n'
    printf '  3) neovim    neovim, lazy.nvim, language servers, linters\n'
    printf '  4) gitconfig copy ~/.gitconfig* from repo examples\n'
    printf '\nEnter numbers (e.g. "1 3") or press Enter for all: '

    local resp c
    read -r resp
    [[ -z "$resp" || "$resp" == "all" ]] && return

    INSTALL_ZSH=false
    INSTALL_TMUX=false
    INSTALL_NEOVIM=false
    INSTALL_GITCONFIG=false

    for c in $resp; do
        case "$c" in
            1) INSTALL_ZSH=true ;;
            2) INSTALL_TMUX=true ;;
            3) INSTALL_NEOVIM=true ;;
            4) INSTALL_GITCONFIG=true ;;
            *) info "unknown component '$c' - ignored" ;;
        esac
    done
}

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

    # Prompt for component selection when running interactively.
    # Non-interactive runs (chezmoi apply, CI) install everything.
    if [[ -t 0 ]]; then
        _select_components
    fi

    # Prereqs required by the per-app scripts themselves.
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
