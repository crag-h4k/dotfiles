#!/usr/bin/env bash
# Top-level installer. Driven by chezmoi's
# home/.chezmoiscripts/run_once_after_00-install.sh.tmpl, which exports
# the component selection (made at `chezmoi init`) as INSTALL_* env vars and
# then calls this script. It installs base tools plus packages for the selected
# components. It does NOT call `chezmoi apply` - chezmoi invokes this script,
# so applying again would recurse.
#
# Standalone use is supported too: the INSTALL_* vars default to zsh+tmux+neovim
# on when unset.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Component flags, read from the environment (set by chezmoi via
# home/.chezmoiscripts/run_once_after_00-install.sh.tmpl). Defaults apply only
# for standalone runs.
INSTALL_ZSH="${INSTALL_ZSH:-true}"
INSTALL_TMUX="${INSTALL_TMUX:-true}"
INSTALL_NEOVIM="${INSTALL_NEOVIM:-true}"
# AI tooling, opt-in and off by default. codecompanion (with neovim) installs the
# claude-agent-acp bridge and provisions the runtime sentinel init.lua checks
# (touch/rm per-host still works). The claude_hooks sub-feature is file-gated in
# home/.chezmoiignore, not here.
INSTALL_AI_CODECOMPANION="${INSTALL_AI_CODECOMPANION:-false}"
# statusline (opt-in, off by default). Config files are file-gated in
# home/.chezmoiignore; this var gates only the runtime deps (jq + python3) the
# statusline shells out to.
INSTALL_AI_STATUSLINE="${INSTALL_AI_STATUSLINE:-false}"
# Installing the shared Claude/Codex workspace also installs both terminal
# clients through their official user-local standalone installers.
INSTALL_AI_SHARED_WORKSPACE="${INSTALL_AI_SHARED_WORKSPACE:-false}"
# Shared notify runtime. AI-hook-only hosts still need notify.yaml, lib.sh, and
# mikefarah yq even when neither Zsh nor tmux is selected as a component.
INSTALL_NOTIFY="${INSTALL_NOTIFY:-false}"
# terminal sub-features (opt-in). The CONFIG for each is file-gated in
# home/.chezmoiignore; these vars gate only the BINARY install.
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

main() {
    local os
    os=$(os_detect)
    info "dotfiles installer: platform=$os"
    info "components: zsh=$INSTALL_ZSH tmux=$INSTALL_TMUX neovim=$INSTALL_NEOVIM ai.codecompanion=$INSTALL_AI_CODECOMPANION ai.shared_workspace=$INSTALL_AI_SHARED_WORKSPACE notify=$INSTALL_NOTIFY terminal.ghostty=$INSTALL_TERMINAL_GHOSTTY terminal.iterm2=$INSTALL_TERMINAL_ITERM2"

    # Confirm before any package-manager mutation. Decline degrades to the same
    # configs-only tail this function already runs for `configs` mode, for THIS
    # run only - persisted installMode is never touched, and the script never
    # aborts half-applied.
    local do_packages=false
    if [[ "$DOTFILES_INSTALL_MODE" == packages ]]; then
        if pkg_confirm "chezmoi apply"; then
            do_packages=true
        else
            info "package install declined for this run; applying configs only (installMode unchanged; re-run to install)"
        fi
    fi

    if [[ "$do_packages" == true ]]; then
        local pkg_started=$SECONDS
        local planner="$SCRIPT_DIR/package-plan.sh"
        local -a packages=() casks=()
        case "$os" in
            macos)
                require_cmd brew
                # Install only missing formulae and upgrade only outdated ones, so
                # formulae already present (many are preinstalled on the CI runner)
                # do not emit "already installed" warnings. The planner's status is
                # brew-inventory-aware (alias matching), so read it rather than
                # re-deriving install state here.
                local src name status
                local -a to_install=() to_upgrade=()
                while IFS=$'\t' read -r src name status _; do
                    [[ "$src" == brew-formula ]] || continue
                    case "$status" in
                        planned) to_install+=("$name") ;;
                        update)  to_upgrade+=("$name") ;;
                    esac
                done < <("$planner" --records)
                if (( ${#to_install[@]} > 0 )); then
                    brew install "${to_install[@]}"
                fi
                if (( ${#to_upgrade[@]} > 0 )); then
                    brew upgrade "${to_upgrade[@]}" || warn "some formula upgrades failed; continuing"
                fi
                while IFS= read -r pkg; do [[ -n "$pkg" ]] && casks+=("$pkg"); done < <("$planner" --names brew-cask)
                if (( ${#casks[@]} > 0 )); then
                    for pkg in "${casks[@]}"; do
                        if [[ "$pkg" == ghostty && -d /Applications/Ghostty.app ]]; then
                            info "ghostty: already present; skipping cask install"
                        elif brew list --cask "$pkg" >/dev/null 2>&1; then
                            brew upgrade --cask "$pkg" || warn "$pkg cask upgrade failed; continuing"
                        else
                            brew install --cask "$pkg" || warn "$pkg cask install failed; continuing"
                        fi
                    done
                fi
                ;;
            debian)
                # Third-party apt repos, each confirm-gated on Debian (bypassed by
                # DOTFILES_ASSUME_YES, which CI/containers export). Soft: a declined
                # repo warns and the run continues on the reachable packages.
                [[ "$INSTALL_ZSH" == true ]] &&
                    { ensure_gh_apt_repo || warn "GitHub CLI apt repo not added; gh may be unavailable"; }
                if [[ "$INSTALL_NEOVIM" == true ]]; then
                    ensure_nodesource_apt_repo || warn "NodeSource apt repo not added; Node.js 24 will be unavailable"
                    ensure_trivy_apt_repo || warn "Trivy apt repo not added; trivy will be unavailable"
                fi
                while IFS= read -r pkg; do [[ -n "$pkg" ]] && packages+=("$pkg"); done < <("$planner" --names apt)
                if (( ${#packages[@]} > 0 )); then
                    sudo apt-get update
                    # Batch first; on failure (a declined repo can make a package
                    # unavailable) retry individually so reachable packages still
                    # install and only the missing ones warn.
                    if ! pkg_install_many "${packages[@]}"; then
                        warn "batch apt install failed; retrying packages individually"
                        for pkg in "${packages[@]}"; do
                            pkg_install_many "$pkg" || warn "apt package unavailable, skipping: $pkg"
                        done
                    fi
                fi
                # neovim installs from Debian main (apt); this then upgrades to the
                # latest upstream build and self-skips when the installed neovim is
                # already >= 0.11 (Debian's apt version can be stale).
                [[ "$INSTALL_NEOVIM" == true ]] && { install_neovim_debian || warn "neovim install failed; continuing without a neovim upgrade"; }
                if [[ "$INSTALL_NEOVIM" == true ]]; then
                    verify_node_major 24 || die "NodeSource install did not provide Node.js 24"
                    install_tree_sitter_cli_debian || warn "tree-sitter CLI install failed; Neovim will use syntax highlighting until it is available"
                    install_tflint_debian || warn "tflint install failed; continuing without the CLI/LSP"
                    install_tenv_debian || warn "tenv install failed; the existing terraform command is unchanged"
                fi
                [[ "$INSTALL_NOTIFY" == true ]] && { install_yq_debian || warn "yq install failed; notifications use built-in fallback colors until yq is installed"; }
                ;;
            *) die "unsupported OS: $(uname -s)" ;;
        esac

        [[ "$INSTALL_NEOVIM" == true ]] \
            && { bootstrap_tenv_terraform || warn "tenv could not install/select the latest stable Terraform fallback"; }

        ensure_chezmoi
        [[ "$INSTALL_ZSH" == true ]] && bash "$SCRIPT_DIR/install-zsh.sh"
        [[ "$INSTALL_NEOVIM" == true ]] && bash "$SCRIPT_DIR/install-neovim.sh"
        [[ "$INSTALL_AI_SHARED_WORKSPACE" == true ]] &&
            { bash "$SCRIPT_DIR/install-ai-clis.sh" ||
                warn "one or more AI CLIs could not be installed; shared configuration was still applied"; }
        local pkg_elapsed=$(( SECONDS - pkg_started ))
        info "packages: installed/updated in ${pkg_elapsed}s"
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

    info "all done. Open a new shell (zsh) and tmux/nvim to verify."
}

main "$@"
