#!/usr/bin/env bash
# Install zsh and its packages, then set zsh as the login shell.
# oh-my-zsh and the zsh-users plugins are NOT cloned here: they are chezmoi
# externals (see .chezmoiexternal.toml) fetched and refreshed by chezmoi apply.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

main() {
    local os
    os=$(os_detect)
    info "install-zsh: $os"

    # Packages are installed by the batched call in install.sh. This script
    # handles post-install steps only.

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
