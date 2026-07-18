#!/usr/bin/env bash
# Top-level installer. Driven by chezmoi: run_once_after_00-install.sh exports
# the component selection (made at `chezmoi init`) as INSTALL_* env vars and
# then calls this script. It installs base tools plus packages for the selected
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
# git sub-features (default off): copy ~/.gitconfig / ~/.gitconfig.personal from
# the repo examples. ~/.gitignore_global is chezmoi-managed (file-gated in
# .chezmoiignore), not handled here.
INSTALL_GIT_CONFIG="${INSTALL_GIT_CONFIG:-false}"
INSTALL_GIT_PERSONAL="${INSTALL_GIT_PERSONAL:-false}"
# AI tooling, opt-in and off by default. codecompanion (with neovim) installs the
# claude-agent-acp bridge and provisions the runtime sentinel init.lua checks
# (touch/rm per-host still works). The claude_hooks sub-feature is file-gated in
# .chezmoiignore, not here.
INSTALL_AI_CODECOMPANION="${INSTALL_AI_CODECOMPANION:-false}"
# statusline (opt-in, off by default). Config files are file-gated in
# .chezmoiignore; this var gates only the runtime deps (jq + python3) the
# statusline shells out to.
INSTALL_AI_STATUSLINE="${INSTALL_AI_STATUSLINE:-false}"
# Shared notify runtime. AI-hook-only hosts still need notify.yaml, lib.sh, and
# mikefarah yq even when neither Zsh nor tmux is selected as a component.
INSTALL_NOTIFY="${INSTALL_NOTIFY:-false}"
# terminal sub-features (opt-in). The CONFIG for each is file-gated in
# .chezmoiignore; these vars gate only the BINARY install.
# - ghostty: cask on macOS; no official Debian apt package, so config-only on
#   Debian (see the debian arm below).
# - iterm2: cask on macOS only; a no-op on non-macOS.
# Standalone default false for both (opt-in), like the other GUI tooling; the
# chezmoi run_once path sets them explicitly from the terminal submenu selection.
INSTALL_TERMINAL_GHOSTTY="${INSTALL_TERMINAL_GHOSTTY:-false}"
INSTALL_TERMINAL_ITERM2="${INSTALL_TERMINAL_ITERM2:-false}"
DOTFILES_INSTALL_MODE="${DOTFILES_INSTALL_MODE:-packages}"
[[ "$DOTFILES_INSTALL_MODE" == packages || "$DOTFILES_INSTALL_MODE" == configs ]] ||
    die "DOTFILES_INSTALL_MODE must be configs or packages"

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
    local resp=""
    # Non-fatal under `set -e`: a non-interactive apply (piped bootstrap, CI) has
    # no tty, so read would hit EOF and return non-zero, aborting the installer.
    # Default to "no" in that case rather than prompting into the void.
    if [[ -t 0 ]]; then
        read -r resp || resp=""
    fi
    if [[ "$resp" =~ ^[Yy]$ ]]; then
        cp "$example" "$target"
        info "copied $label -> $target"
    fi
}

main() {
    local os
    os=$(os_detect)
    info "dotfiles installer: platform=$os"
    info "components: zsh=$INSTALL_ZSH tmux=$INSTALL_TMUX neovim=$INSTALL_NEOVIM git.config=$INSTALL_GIT_CONFIG git.personal=$INSTALL_GIT_PERSONAL ai.codecompanion=$INSTALL_AI_CODECOMPANION notify=$INSTALL_NOTIFY terminal.ghostty=$INSTALL_TERMINAL_GHOSTTY terminal.iterm2=$INSTALL_TERMINAL_ITERM2"

    if [[ "$DOTFILES_INSTALL_MODE" == packages ]]; then
        local planner="$SCRIPT_DIR/package-plan.sh"
        local -a packages=() casks=()
        case "$os" in
            macos)
                require_cmd brew
                while IFS= read -r pkg; do [[ -n "$pkg" ]] && packages+=("$pkg"); done < <("$planner" --names brew-formula)
                (( ${#packages[@]} == 0 )) || brew install "${packages[@]}"
                while IFS= read -r pkg; do [[ -n "$pkg" ]] && casks+=("$pkg"); done < <("$planner" --names brew-cask)
                if (( ${#casks[@]} > 0 )); then
                    for pkg in "${casks[@]}"; do
                        if [[ "$pkg" == ghostty && -d /Applications/Ghostty.app ]]; then
                            info "ghostty: already present; skipping cask install"
                        else
                            brew list --cask "$pkg" >/dev/null 2>&1 ||
                                brew install --cask "$pkg" || warn "$pkg cask install failed; continuing"
                        fi
                    done
                fi
                ;;
            debian)
                [[ "$INSTALL_ZSH" == true ]] && ensure_gh_apt_repo
                while IFS= read -r pkg; do [[ -n "$pkg" ]] && packages+=("$pkg"); done < <("$planner" --names apt)
                if (( ${#packages[@]} > 0 )); then
                    sudo apt-get update
                    pkg_install_many "${packages[@]}"
                fi
                [[ "$INSTALL_NEOVIM" == true ]] && { install_neovim_debian || warn "neovim install failed; continuing without a neovim upgrade"; }
                [[ "$INSTALL_NOTIFY" == true ]] && { install_yq_debian || warn "yq install failed; notifications use built-in fallback colors until yq is installed"; }
                [[ "$INSTALL_TERMINAL_GHOSTTY" == true ]] && info "ghostty: config applied; skipping binary install on Debian. See README."
                ;;
            *) die "unsupported OS: $(uname -s)" ;;
        esac

        ensure_chezmoi
        [[ "$INSTALL_ZSH" == true ]] && bash "$SCRIPT_DIR/install-zsh.sh"
        [[ "$INSTALL_NEOVIM" == true ]] && bash "$SCRIPT_DIR/install-neovim.sh"
    else
        info "configs-only mode: skipped packages, login-shell changes, language packages, and Neovim plugin sync"
    fi

    # Convenience symlink: ~/dotfiles -> ~/.local/share/chezmoi
    local chezmoi_src="$HOME/.local/share/chezmoi"
    local dotfiles_link="$HOME/dotfiles"
    if [[ -d "$chezmoi_src" && ! -e "$dotfiles_link" ]]; then
        ln -s "$chezmoi_src" "$dotfiles_link"
        info "created symlink $dotfiles_link -> $chezmoi_src"
    fi

    # Post-install steps for each component (non-package work).
    [[ "$INSTALL_TERMINAL_ITERM2" == true ]] && bash "$SCRIPT_DIR/install-iterm2.sh"

    # Provision the CodeCompanion opt-in sentinel that init.lua checks at startup.
    # Only meaningful with neovim. Done here (not as a chezmoi-managed file) so a
    # later `chezmoi apply` never recreates it after you rm it to disable per-host.
    if [[ "$INSTALL_NEOVIM" == true && "$INSTALL_AI_CODECOMPANION" == true ]]; then
        mkdir -p "$HOME/.config/nvim"
        touch "$HOME/.config/nvim/.codecompanion-enabled"
        info "CodeCompanion enabled (sentinel: ~/.config/nvim/.codecompanion-enabled)"
    fi

    if [[ "$INSTALL_GIT_CONFIG" == true ]]; then
        _setup_gitconfig_file "$HOME/.gitconfig"          "$SCRIPT_DIR/../gitconfig.example"          "gitconfig.example"
    fi
    if [[ "$INSTALL_GIT_PERSONAL" == true ]]; then
        _setup_gitconfig_file "$HOME/.gitconfig.personal" "$SCRIPT_DIR/../gitconfig.personal.example" "gitconfig.personal.example"
    fi

    info "all done. Open a new shell (zsh) and tmux/nvim to verify."
}

main "$@"
