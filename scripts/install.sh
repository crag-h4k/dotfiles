#!/usr/bin/env bash
# Top-level installer. Invokes the three per-application scripts in order,
# after ensuring the base toolchain (git, make, curl) is present.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Show an existing gitconfig file (if present), then prompt to create/replace
# it from the repo example.
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

    bash "$SCRIPT_DIR/install-zsh.sh"
    bash "$SCRIPT_DIR/install-tmux.sh"
    bash "$SCRIPT_DIR/install-neovim.sh"

    _setup_gitconfig_file "$HOME/.gitconfig"          "$SCRIPT_DIR/../gitconfig.example"          "gitconfig.example"
    _setup_gitconfig_file "$HOME/.gitconfig.personal" "$SCRIPT_DIR/../gitconfig.personal.example" "gitconfig.personal.example"

    info "all done. Open a new shell (zsh) and tmux/nvim to verify."
}

main "$@"
