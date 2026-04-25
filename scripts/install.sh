#!/usr/bin/env bash
# Top-level installer. Invokes the three per-application scripts in order,
# after ensuring the base toolchain (git, make, curl) is present.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

main() {
    local os
    os=$(os_detect)
    info "tilde installer: platform=$os"

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

    bash "$SCRIPT_DIR/install-zsh.sh"
    bash "$SCRIPT_DIR/install-tmux.sh"
    bash "$SCRIPT_DIR/install-neovim.sh"

    info "all done. Open a new shell (zsh) and tmux/nvim to verify."
}

main "$@"
