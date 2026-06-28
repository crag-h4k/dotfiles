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

_deduped_pkgs() {
    local -a unique=()
    local pkg existing found
    for pkg in "$@"; do
        found=0
        for existing in "${unique[@]}"; do
            if [[ "$pkg" == "$existing" ]]; then
                found=1
                break
            fi
        done
        (( found )) || unique+=("$pkg")
    done
    printf '%s\n' "${unique[@]}"
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
    info "components: zsh=$INSTALL_ZSH tmux=$INSTALL_TMUX neovim=$INSTALL_NEOVIM git.config=$INSTALL_GIT_CONFIG git.personal=$INSTALL_GIT_PERSONAL ai.codecompanion=$INSTALL_AI_CODECOMPANION"

    # Base toolchain required by the installer itself and by reconfigure flows.
    # This intentionally runs before selected component packages so helpers such
    # as ensure_gh_apt_repo can rely on curl being present.
    case "$os" in
        macos)
            require_cmd brew
            brew install git make curl gum chezmoi
            ;;
        debian)
            sudo apt-get update
            pkg_install_many git make curl ca-certificates gum
            ;;
        *)
            die "unsupported OS: $(uname -s)"
            ;;
    esac

    # Build package lists for selected components and install them in one later
    # package-manager call per platform.
    local -a macos_pkgs=() debian_pkgs=()

    [[ "$INSTALL_ZSH" == true ]] && {
        macos_pkgs+=(zsh gh zoxide gnupg fzf)
        debian_pkgs+=(zsh gh zoxide gnupg command-not-found fzf)
    }
    [[ "$INSTALL_TMUX" == true ]] && {
        # coreutils/gawk + gawk/net-tools are runtime deps of the
        # tmux-network-bandwidth status plugin (numfmt; 3-arg match(); netstat).
        macos_pkgs+=(tmux reattach-to-user-namespace coreutils gawk)
        debian_pkgs+=(tmux xclip wl-clipboard mpg123 gawk net-tools)
    }
    [[ "$INSTALL_NEOVIM" == true ]] && {
        macos_pkgs+=(cmake go hadolint llvm lua@5.4 luarocks
                     markdownlint-cli2 neovim node python3 shellcheck yamllint)
        debian_pkgs+=(build-essential cmake golang jq luarocks nodejs npm
                      python3 python3-pip python3-venv shellcheck yamllint)
    }
    # yq powers the attention-notification config (~/.config/notify/notify.yaml),
    # read by BOTH the zsh process notifier and the tmux/Claude hooks - so it is
    # required whenever zsh or tmux is selected. On Debian the apt 'yq' is a
    # different tool (python kislyuk/yq) with incompatible syntax, so macOS uses
    # brew here and Debian fetches the mikefarah binary below (install_yq_debian).
    [[ "$INSTALL_ZSH" == true || "$INSTALL_TMUX" == true ]] && macos_pkgs+=(yq)
    [[ "$INSTALL_NEOVIM" == true ]] && macos_pkgs+=(terraform-linters/tap/tflint)

    case "$os" in
        macos)
            macos_pkgs=($(_deduped_pkgs "${macos_pkgs[@]}"))
            if [[ ${#macos_pkgs[@]} -gt 0 ]]; then
                brew install "${macos_pkgs[@]}"
            fi
            ;;
        debian)
            [[ "$INSTALL_ZSH" == true ]] && ensure_gh_apt_repo
            debian_pkgs=($(_deduped_pkgs "${debian_pkgs[@]}"))
            if [[ ${#debian_pkgs[@]} -gt 0 ]]; then
                sudo apt-get update
                pkg_install_many "${debian_pkgs[@]}"
            fi
            # Soft-fail: these fetch binaries over the network (GitHub releases),
            # so a rate-limit/proxy/offline blip must warn and continue, not abort
            # the whole install via set -e on the && call site.
            [[ "$INSTALL_NEOVIM" == true ]] && { install_neovim_debian || warn "neovim install failed; continuing without a neovim upgrade"; }
            [[ "$INSTALL_ZSH" == true || "$INSTALL_TMUX" == true ]] && { install_yq_debian || warn "yq install failed; notifications fall back to built-in default colors until yq is installed"; }
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

    # Post-install steps for each component (non-package work).
    [[ "$INSTALL_ZSH" == true ]]    && bash "$SCRIPT_DIR/install-zsh.sh"
    [[ "$INSTALL_NEOVIM" == true ]] && bash "$SCRIPT_DIR/install-neovim.sh"

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
