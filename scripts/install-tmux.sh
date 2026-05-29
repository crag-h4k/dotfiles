#!/usr/bin/env bash
# Install tmux, the platform-specific clipboard bridge, and tmux plugins.

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

    clone_plugin "https://github.com/tmux-plugins/tpm.git"            ".tmux/plugins/tpm"
    clone_plugin "https://github.com/tmux-plugins/tmux-sensible.git"  ".tmux/plugins/tmux-sensible"
    clone_plugin "https://github.com/tmux-plugins/tmux-yank.git"      ".tmux/plugins/tmux-yank"
    clone_plugin "https://github.com/tmux-plugins/tmux-cpu.git"       ".tmux/plugins/tmux-cpu"
    clone_plugin "https://github.com/tmux-plugins/tmux-net-speed.git" ".tmux/plugins/tmux-net-speed"
    clone_plugin "https://github.com/tmux-plugins/tmux-resurrect.git" ".tmux/plugins/tmux-resurrect"
}

main "$@"
