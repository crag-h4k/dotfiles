#!/usr/bin/env bash
# Install tmux + the platform-specific clipboard bridge. TPM and the
# tmux-* plugins come from chezmoi externals; don't install them here.

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

    info "TPM plugins install inside tmux via: prefix + I  (capital i)"
}

main "$@"
