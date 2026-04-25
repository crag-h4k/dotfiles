#!/usr/bin/env bash
# Install binaries zsh and its OMZ plugins need.
# OMZ itself + zsh-{completions,autosuggestions,syntax-highlighting} come
# from chezmoi externals, not package managers. Don't install those here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

main() {
    local os
    os=$(os_detect)
    info "install-zsh: $os"

    case "$os" in
        macos)
            pkg_install zsh fzf gh zoxide gnupg
            ;;
        debian)
            # command-not-found on apt gives OMZ's plugin something to hook.
            pkg_install zsh fzf gh zoxide gnupg command-not-found
            ;;
        *)
            die "unsupported OS for install-zsh"
            ;;
    esac

    # Set zsh as the login shell if it isn't already.
    local zsh_bin
    zsh_bin=$(command -v zsh)
    if [[ "$SHELL" != "$zsh_bin" ]]; then
        info "setting login shell to $zsh_bin"
        # Ensure the shell is in /etc/shells (Debian wants this).
        if ! grep -qx "$zsh_bin" /etc/shells 2>/dev/null; then
            echo "$zsh_bin" | sudo tee -a /etc/shells >/dev/null || true
        fi
        sudo chsh -s "$zsh_bin" "$USER" || warn "chsh failed; set manually later"
    else
        info "login shell is already zsh"
    fi
}

main "$@"
