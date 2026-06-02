#!/usr/bin/env bash
# Install tmux and the platform-specific clipboard bridge.
# tpm and the tmux-plugins are NOT cloned here: they are chezmoi externals
# (see .chezmoiexternal.toml) fetched and refreshed by chezmoi apply.
#
# claude-squad (parallel Claude Code agents in tmux + git worktrees) is opt-in:
# installed only when the `claudesquad` chezmoi component is selected, exported
# here as INSTALL_CLAUDESQUAD by run_once_after_00-install.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Off by default (and for standalone runs); turned on by the configure menu.
INSTALL_CLAUDESQUAD="${INSTALL_CLAUDESQUAD:-false}"

# Install claude-squad and expose it as `cs` on PATH, idempotently.
install_claude_squad() {
    local os="$1"
    if command -v cs >/dev/null 2>&1; then
        info "claude-squad already on PATH: $(command -v cs)"
        return 0
    fi
    info "installing claude-squad"
    case "$os" in
        macos)
            pkg_install claude-squad
            ;;
        debian)
            curl -fsSL https://raw.githubusercontent.com/smtg-ai/claude-squad/main/install.sh | bash
            ;;
    esac
    mkdir -p "$HOME/.local/bin"
    if ! command -v cs >/dev/null 2>&1 && command -v claude-squad >/dev/null 2>&1; then
        ln -sf "$(command -v claude-squad)" "$HOME/.local/bin/cs"
    fi
}

main() {
    local os
    os=$(os_detect)
    info "install-tmux: $os (claudesquad=$INSTALL_CLAUDESQUAD)"

    case "$os" in
        macos)
            pkg_install tmux reattach-to-user-namespace
            ;;
        debian)
            pkg_install tmux xclip wl-clipboard
            ;;
        *)
            die "unsupported OS for install-tmux"
            ;;
    esac

    if [[ "$INSTALL_CLAUDESQUAD" == true ]]; then
        install_claude_squad "$os"
    fi
}

main "$@"
