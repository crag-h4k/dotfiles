#!/usr/bin/env bash
# Install tmux and the platform-specific clipboard bridge.
# tpm and the tmux-plugins are NOT cloned here: they are chezmoi externals
# (see .chezmoiexternal.toml) fetched and refreshed by chezmoi apply.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

main() {
    # Packages are installed by the batched call in install.sh. Reserved for
    # future post-install steps.
    info "install-tmux: done"
}

main "$@"
