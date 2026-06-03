#!/usr/bin/env bash
# Install tmux and the platform-specific clipboard bridge.
# tpm and the tmux-plugins are NOT cloned here: they are chezmoi externals
# (see .chezmoiexternal.toml) fetched and refreshed by chezmoi apply.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

main() {
    local os
    os=$(os_detect)
    info "install-tmux: $os"

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
}

main "$@"
