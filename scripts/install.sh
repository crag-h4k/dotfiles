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
INSTALL_GIT_CONFIG="${INSTALL_GIT_CONFIG:-false}"
# AI tooling, opt-in and off by default. codecompanion (with neovim) installs the
# claude-agent-acp bridge and provisions the runtime sentinel init.lua checks
# (touch/rm per-host still works). The claude_hooks sub-feature is file-gated in
# home/.chezmoiignore, not here.
INSTALL_AI_CODECOMPANION="${INSTALL_AI_CODECOMPANION:-false}"
[[ "$INSTALL_AI_CODECOMPANION" == true ]] && INSTALL_NEOVIM=true
export INSTALL_NEOVIM
# statusline (opt-in, off by default). Config files are file-gated in
# home/.chezmoiignore; this var gates only the runtime deps (jq + python3) the
# statusline shells out to.
INSTALL_AI_STATUSLINE="${INSTALL_AI_STATUSLINE:-false}"
# OpenCode V2 CLI (opt-in, off by default). The config, wrapper, and notifier are
# file-gated in home/.chezmoiignore; this var gates the isolated binary install.
INSTALL_AI_OPENCODE="${INSTALL_AI_OPENCODE:-false}"
# GitHub Copilot CLI (opt-in, off by default). npm @github/copilot into the
# ~/.local prefix (scripts/install-copilot.sh). No config to file-gate; this var
# gates only the binary install.
INSTALL_AI_COPILOT="${INSTALL_AI_COPILOT:-false}"
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
    local os node_required=false node_ready=true
    os=$(os_detect)
    if node_runtime_selected; then
        node_required=true
        node_ready=false
    fi
    info "dotfiles installer: platform=$os"
    info "components: zsh=$INSTALL_ZSH tmux=$INSTALL_TMUX neovim=$INSTALL_NEOVIM git.config=$INSTALL_GIT_CONFIG ai.codecompanion=$INSTALL_AI_CODECOMPANION ai.opencode=$INSTALL_AI_OPENCODE ai.copilot=$INSTALL_AI_COPILOT notify=$INSTALL_NOTIFY terminal.ghostty=$INSTALL_TERMINAL_GHOSTTY terminal.iterm2=$INSTALL_TERMINAL_ITERM2"

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
        local source_root
        local src name status _policy origin probe
        source_root="${DOTFILES_SOURCE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
        package_results_reset
        if [[ -f "$source_root/.gitmodules" ]]; then
            package_try "pinned palette submodule" \
                git -C "$source_root" submodule update --init --depth 1 vendor/tinted-schemes || true
        fi
        case "$os" in
            macos)
                require_cmd brew
                # Metadata refresh happens only after the user approves the plan.
                # Rebuild manager-aware records afterward, then mutate only the
                # selected formulae and casks.
                package_try "Homebrew metadata refresh" brew update || true
                # Read records on FD 3 so a mutating command in the loop body
                # (e.g. a brew upgrade that touches stdin) cannot consume the
                # record stream and silently drop every later formula.
                while IFS=$'\t' read -r src name status _policy origin probe <&3; do
                    [[ "$src" == brew-formula ]] || continue
                    case "$status" in
                        planned)
                            package_try "Homebrew formula $name install" brew install "$name" || true
                            ;;
                        update)
                            package_try "Homebrew formula $name update" brew upgrade "$name" || true
                            ;;
                        installed)
                            package_skip "Homebrew formula $name is current"
                            ;;
                    esac
                done 3< <(DOTFILES_PLAN_APPROVED=1 "$planner" --records)
                while IFS=$'\t' read -r src name status _policy origin probe <&3; do
                    [[ "$src" == brew-cask ]] || continue
                    if [[ "$name" == ghostty && -d /Applications/Ghostty.app ]] \
                        && ! brew list --cask ghostty >/dev/null 2>&1; then
                        package_skip "Ghostty is unmanaged by Homebrew; update the app manually"
                        continue
                    fi
                    case "$status" in
                        planned) package_try "Homebrew cask $name install" brew install --cask "$name" || true ;;
                        update) package_try "Homebrew cask $name update" brew upgrade --cask "$name" || true ;;
                        installed) package_skip "Homebrew cask $name is current" ;;
                    esac
                done 3< <(DOTFILES_PLAN_APPROVED=1 "$planner" --records)
                if [[ "$node_required" == true ]]; then
                    if package_try "Node.js 24+ verification" verify_node_min_major 24; then
                        node_ready=true
                    fi
                fi
                ;;
            debian)
                # Third-party apt repos, each confirm-gated on Debian (bypassed by
                # DOTFILES_ASSUME_YES, which CI/containers export). Soft: a declined
                # repo warns and the run continues on the reachable packages.
                [[ "$INSTALL_ZSH" == true ]] &&
                    { package_try "GitHub CLI APT repository" ensure_gh_apt_repo || true; }
                if node_runtime_selected; then
                    package_try "NodeSource APT repository" ensure_nodesource_apt_repo || true
                fi
                if [[ "$INSTALL_NEOVIM" == true ]]; then
                    package_try "Trivy APT repository" ensure_trivy_apt_repo || true
                fi
                package_try "APT metadata refresh" sudo apt-get update || true
                # apt-get install is intentionally scoped to each selected package.
                # It installs missing dependencies and advances installed ones to
                # their candidate version without running a distro-wide upgrade.
                while IFS= read -r name <&3; do
                    [[ -n "$name" ]] || continue
                    package_try "APT package $name install/update" sudo apt-get install -y "$name" || true
                done 3< <(DOTFILES_PLAN_APPROVED=1 "$planner" --names apt)
                # Neovim is one checksum-verified upstream tree so its binary,
                # runtime, and libraries activate or roll back together.
                [[ "$INSTALL_NEOVIM" == true ]] && { package_try "Neovim versioned release" install_neovim_debian || true; }
                if [[ "$INSTALL_NEOVIM" == true ]]; then
                    package_try "tree-sitter CLI pinned v0.26.11" install_tree_sitter_cli_debian || true
                    package_try "TFLint latest release" install_tflint_debian || true
                    package_try "tenv latest release" install_tenv_debian || true
                fi
                if [[ "$node_required" == true ]]; then
                    if package_try "Node.js 24+ verification" verify_node_min_major 24; then
                        node_ready=true
                    fi
                fi
                [[ "$INSTALL_NOTIFY" == true ]] && { package_try "yq latest release" install_yq_debian update || true; }
                [[ "$INSTALL_TERMINAL_GHOSTTY" == true ]] &&
                    package_skip "Ghostty has no managed Debian package; update the app manually"
                ;;
            *) die "unsupported OS: $(uname -s)" ;;
        esac

        [[ "$INSTALL_NEOVIM" == true ]] \
            && { package_try "Terraform latest stable through tenv" bootstrap_tenv_terraform || true; }

        package_try "chezmoi availability" ensure_chezmoi || true
        [[ "$INSTALL_ZSH" == true ]] && { package_try "Zsh post-install" bash "$SCRIPT_DIR/install-zsh.sh" || true; }
        [[ "$INSTALL_NEOVIM" == true ]] && {
            package_try "Neovim language and plugin packages" \
                env DOTFILES_NODE_READY="$node_ready" bash "$SCRIPT_DIR/install-neovim.sh" || true
        }
        if [[ "$INSTALL_AI_OPENCODE" == true ]]; then
            if [[ "$node_ready" == true ]]; then
                package_try "OpenCode V2 CLI and matching runtime" \
                    env INSTALL_AI_OPENCODE=true DOTFILES_NODE_READY=true \
                    bash "$SCRIPT_DIR/install-opencode2.sh" || true
            else
                package_skip "OpenCode V2 CLI and matching runtime; Node.js 24+ unavailable"
            fi
        fi
        if [[ "$INSTALL_AI_COPILOT" == true ]]; then
            if [[ "$node_ready" == true ]]; then
                package_try "GitHub Copilot CLI" env INSTALL_AI_COPILOT=true DOTFILES_NODE_READY=true bash "$SCRIPT_DIR/install-copilot.sh" || true
            else
                package_skip "GitHub Copilot CLI; Node.js 24+ unavailable"
            fi
        fi

        # Chezmoi clones missing externals while applying. Package mode also
        # refreshes every selected checkout, but only by a clean fast-forward.
        # Missing checkouts remain chezmoi's responsibility.
        while IFS=$'\t' read -r src name status _policy origin probe; do
            local git_rc=0
            [[ "$src" == git-external || "$src" == git-runtime ]] || continue
            if [[ "$src" == git-runtime ]]; then
                install_or_update_git_runtime "$name" "$origin" "$probe" || git_rc=$?
            else
                update_git_external "$name" "$origin" "$probe" || git_rc=$?
            fi
            if [[ "$git_rc" -eq 0 ]]; then
                _package_results_ok=$((_package_results_ok + 1))
            else
                case "$git_rc" in
                    2) _package_results_skipped=$((_package_results_skipped + 1)) ;;
                    *) _package_results_failed=$((_package_results_failed + 1)) ;;
                esac
            fi
        done < <(DOTFILES_PLAN_APPROVED=1 "$planner" --records)
        local pkg_elapsed=$(( SECONDS - pkg_started ))
        package_results_summary "package run"
        info "packages: installed/updated in ${pkg_elapsed}s"
    else
        info "configs-only mode: skipped packages, login-shell changes, language packages, and Neovim plugin sync"
    fi

    # Keep identity and signing data out of the public source. The managed
    # ~/.gitconfig includes this private file last; create it only when absent.
    if [[ "$INSTALL_GIT_CONFIG" == true ]]; then
        local git_override="$HOME/.gitconfig.override"
        if [[ ! -e "$git_override" && ! -L "$git_override" ]]; then
            (umask 077; : >"$git_override")
            info "created private Git override stub at $git_override"
        fi
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
