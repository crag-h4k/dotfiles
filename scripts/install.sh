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

# Handle log access before component defaults or package work.
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install"
case "${1:-}" in
    --log|--log-path)
        [[ $# -eq 1 ]] || die "usage: install.sh [--log | --log-path]"
        [[ -f "$log_dir/latest.log" ]] || die "no install log available at $log_dir"
        if [[ "$1" == --log-path ]]; then
            printf '%s/%s\n' "$log_dir" "$(readlink "$log_dir/latest.log")"
        else
            cat "$log_dir/latest.log"
        fi
        exit
        ;;
    --help|-h)
        printf 'usage: install.sh [--log | --log-path]\nRuns are logged automatically; --log displays the latest run without installing.\n'
        exit
        ;;
    '') ;;
    *) die "unknown argument: $1" ;;
esac
if [[ "${DOTFILES_INSTALL_LOG_ACTIVE:-}" != 1 ]]; then
    mkdir -p "$log_dir"
    chmod 700 "$log_dir"
    log_file="$log_dir/$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
    (umask 077; : >"$log_file")
    ln -sfn "${log_file##*/}" "$log_dir/latest.log"
    printf 'dotfiles: install log: %s\n' "$log_file"
    # Called through EXIT for both normal completion and interrupted pipelines.
    # shellcheck disable=SC2317
    _install_log_finish() {
        local result="$1"
        trap - EXIT
        printf 'dotfiles: finished at %s; exit=%s\n' "$(date -u +%FT%TZ)" "$result" | tee -a "$log_file"
        exit "$result"
    }
    trap '_install_log_finish "$?"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # Run a fresh shell so recording PIPESTATUS does not disable its errexit.
    set +e
    DOTFILES_INSTALL_LOG_ACTIVE=1 DOTFILES_INSTALL_LOG="$log_file" bash "$0" "$@" 2>&1 | tee -a "$log_file"
    log_status=("${PIPESTATUS[@]}")
    result="${log_status[0]}"
    [[ "${log_status[1]}" -eq 0 ]] || result=1
    exit "$result"
fi

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
    local os node_required=false node_ready=true package_failed=0
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
            export DOTFILES_PACKAGES_APPROVED=true
        else
            info "package install declined for this run; applying configs only (installMode unchanged; re-run to install)"
        fi
    fi

    if [[ "$do_packages" == true ]]; then
        if [[ -z "${DOTFILES_PACKAGE_PLAN:-}" ]]; then
            package_plan_create || die "could not resolve package plan"
        fi
        info "executing resolved package plan"
        "$SCRIPT_DIR/package-plan.sh" --display-file "$DOTFILES_PACKAGE_PLAN"
        local pkg_started=$SECONDS
        local source_root
        local src name status _policy origin probe _current target reason
        local -a brew_formula_install=() brew_formula_update=() brew_formula_remove=()
        local -a brew_cask_install=() brew_cask_update=()
        local -a apt_packages=()
        export DOTFILES_APT_REPO_CHANGED=false
        source_root="${DOTFILES_SOURCE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
        package_results_reset
        if [[ -f "$source_root/.gitmodules" ]]; then
            package_try "pinned palette submodule" \
                ensure_pinned_palette "$source_root" || true
        fi
        case "$os" in
            macos)
                require_cmd brew
                # nvim-treesitter compiles parsers with `tree-sitter build`, which
                # shells out to cc. A bottled-Homebrew arm64 host can run without Apple
                # Command Line Tools, and /usr/bin/cc is only a stub until they are
                # installed, so a neovim deploy would otherwise fail deep in parser
                # provisioning. Gate on the toolchain up front: `xcode-select -p`
                # succeeds only once the CLT (or Xcode) toolchain is present.
                if [[ "$INSTALL_NEOVIM" == true ]] && ! xcode-select -p >/dev/null 2>&1; then
                    die "neovim needs a C compiler (cc) to build tree-sitter parsers, but Apple Command Line Tools are not installed. Run: xcode-select --install"
                fi
                # The plan refreshes Homebrew metadata before the single approval.
                # Rebuild its status inventory from that metadata, then batch every
                # requested formula and cask by action. Homebrew would otherwise ask
                # once for every install or upgrade command.
                while IFS=$'\t' read -r src name status _policy origin probe _current target reason <&3; do
                    case "$src:$status" in
                        brew-formula:planned) brew_formula_install+=("$name") ;;
                        brew-formula:update) brew_formula_update+=("$name") ;;
                        brew-formula:remove) brew_formula_remove+=("$name") ;;
                        brew-formula:installed) package_skip "Homebrew formula $name is current" ;;
                        brew-cask:planned) brew_cask_install+=("$name") ;;
                        brew-cask:update) brew_cask_update+=("$name") ;;
                        brew-cask:installed) package_skip "Homebrew cask $name is current" ;;
                        brew-formula:blocked|brew-cask:blocked)
                            warn "Homebrew $name: $reason; skipped"
                            _package_results_failed=$((_package_results_failed + 1))
                            ;;
                    esac
                done 3< "$DOTFILES_PACKAGE_PLAN"
                ((${#brew_formula_install[@]} == 0)) ||
                    package_try "Homebrew formula install" brew install --no-ask "${brew_formula_install[@]}" || true
                ((${#brew_formula_update[@]} == 0)) ||
                    package_try "Homebrew formula update" brew upgrade --no-ask "${brew_formula_update[@]}" || true
                ((${#brew_formula_remove[@]} == 0)) ||
                    package_try "Homebrew legacy tool removal" brew uninstall "${brew_formula_remove[@]}" || true
                ((${#brew_cask_install[@]} == 0)) ||
                    package_try "Homebrew cask install" brew install --cask --no-ask "${brew_cask_install[@]}" || true
                ((${#brew_cask_update[@]} == 0)) ||
                    package_try "Homebrew cask update" brew upgrade --cask --no-ask "${brew_cask_update[@]}" || true
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
                # Adding a selected third-party repository happens only after the
                # package plan is approved. Refresh once more only in that case so
                # its selected package is available to the single batch install.
                if [[ "$DOTFILES_APT_REPO_CHANGED" == true ]]; then
                    package_try "APT metadata refresh after repository setup" sudo apt-get update || true
                fi
                while IFS=$'\t' read -r src name status _policy origin probe _current target reason <&3; do
                    [[ "$src" == apt ]] || continue
                    case "$status" in
                        planned|update|check)
                            if [[ "$target" != - ]]; then apt_packages+=("$name=$target")
                            else apt_packages+=("$name"); fi
                            ;;
                        blocked)
                            warn "APT $name: $reason; skipped"
                            _package_results_failed=$((_package_results_failed + 1))
                            ;;
                        *) package_skip "APT $name is current" ;;
                    esac
                done 3< "$DOTFILES_PACKAGE_PLAN"
                # apt-get install with several names installs missing dependencies
                # and advances only this selected set. It never performs a
                # distribution-wide upgrade.
                ((${#apt_packages[@]} == 0)) ||
                    package_try "APT selected package install/update" sudo apt-get install -y "${apt_packages[@]}" || true
                # Neovim is one checksum-verified upstream tree so its binary,
                # runtime, and libraries activate or roll back together.
                [[ "$INSTALL_NEOVIM" == true ]] && { package_action_try github-release neovim "Neovim versioned release" install_neovim_debian || true; }
                if [[ "$INSTALL_NEOVIM" == true ]]; then
                    package_action_try github-release tree-sitter-cli "tree-sitter CLI pinned v0.26.11" install_tree_sitter_cli_debian || true
                    package_action_try github-release tflint "TFLint latest release" install_tflint_debian || true
                    package_action_try github-release tenv "tenv latest release" install_tenv_debian || true
                fi
                if [[ "$node_required" == true ]]; then
                    if package_try "Node.js 24+ verification" verify_node_min_major 24; then
                        node_ready=true
                    fi
                fi
                [[ "$INSTALL_NOTIFY" == true ]] && { package_action_try github-release yq "yq latest release" install_yq_debian update || true; }
                [[ "$INSTALL_TERMINAL_GHOSTTY" == true ]] &&
                    package_skip "Ghostty has no managed Debian package; update the app manually"
                ;;
            *) die "unsupported OS: $(uname -s)" ;;
        esac

        [[ "$INSTALL_NEOVIM" == true ]] \
            && { package_action_try github-release terraform "Terraform latest stable through tenv" bootstrap_tenv_terraform || true; }

        package_try "chezmoi availability" ensure_chezmoi || true
        [[ "$INSTALL_ZSH" == true ]] && { package_try "Zsh post-install" bash "$SCRIPT_DIR/install-zsh.sh" || true; }
        [[ "$INSTALL_NEOVIM" == true ]] && {
            package_try "Neovim language and plugin packages" \
                env DOTFILES_NODE_READY="$node_ready" bash "$SCRIPT_DIR/install-neovim.sh" || true
        }
        if [[ "$INSTALL_AI_OPENCODE" == true ]]; then
            if [[ "$node_ready" == true ]]; then
                local opencode_target
                opencode_target=$(package_target npm @opencode/cli)
                package_action_try npm @opencode/cli "OpenCode V2 CLI and matching runtime" \
                    env OPENCODE2_VERSION="${opencode_target:-${OPENCODE2_VERSION:-latest}}" INSTALL_AI_OPENCODE=true DOTFILES_NODE_READY=true \
                    bash "$SCRIPT_DIR/install-opencode2.sh" || true
            else
                package_skip "OpenCode V2 CLI and matching runtime; Node.js 24+ unavailable"
            fi
        fi
        if [[ "$INSTALL_AI_COPILOT" == true ]]; then
            if [[ "$node_ready" == true ]]; then
                local copilot_target
                copilot_target=$(package_target npm @github/copilot)
                package_action_try npm @github/copilot "GitHub Copilot CLI" env COPILOT_VERSION="${copilot_target:-${COPILOT_VERSION:-prerelease}}" INSTALL_AI_COPILOT=true DOTFILES_NODE_READY=true bash "$SCRIPT_DIR/install-copilot.sh" || true
            else
                package_skip "GitHub Copilot CLI; Node.js 24+ unavailable"
            fi
        fi
        if [[ "$os" == debian ]]; then
            package_action_try uv-tool prek "prek pinned hook runner" \
                env PREK_VERSION="${PREK_VERSION:-0.5.4}" bash "$SCRIPT_DIR/install-prek.sh" || true
        fi

        package_plan_resolve_deferred_git || warn "could not resolve deferred Git packages"
        # Apply the saved commits; do not discover newer Git updates here.
        while IFS=$'\t' read -r src name status _policy origin probe _current target reason <&3; do
            [[ "$src" == git-external || "$src" == git-runtime ]] || continue
            package_action_try "$src" "$name" "$name" apply_git_package \
                "$src" "$name" "$origin" "$probe" "$_current" "$target" "$_policy" || true
        done 3< "$DOTFILES_PACKAGE_PLAN"
        local pkg_elapsed=$(( SECONDS - pkg_started ))
        package_results_summary "package run"
        package_failed=$_package_results_failed
        info "packages: checked in ${pkg_elapsed}s"
        rm -f "$DOTFILES_PACKAGE_PLAN"
        unset DOTFILES_PACKAGE_PLAN
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

    if (( package_failed > 0 )); then
        warn "$package_failed package step(s) failed; see the install log and rerun after fixing them"
        return 1
    fi
    info "all done. Open a new shell (zsh) and tmux/nvim to verify."
}

export INSTALL_ZSH INSTALL_TMUX INSTALL_NEOVIM INSTALL_NOTIFY INSTALL_AI_CODECOMPANION
export INSTALL_AI_STATUSLINE INSTALL_AI_OPENCODE INSTALL_AI_COPILOT INSTALL_TERMINAL_GHOSTTY INSTALL_TERMINAL_ITERM2
main "$@"
