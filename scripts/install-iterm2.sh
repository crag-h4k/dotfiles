#!/usr/bin/env bash
# Point iTerm2 at the chezmoi-managed custom preferences folder
# (~/.config/iterm2). macOS only; the iTerm2 cask itself is installed by the
# batched brew call in install.sh. This is a read-only load: iTerm2 reads prefs
# from the folder on launch and the repo stays the source of truth. To update
# the committed prefs, re-export them (see README).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

main() {
    local os
    os=$(os_detect)
    if [[ "$os" != macos ]]; then
        info "install-iterm2: skipping on $os (macOS only)"
        return 0
    fi
    info "install-iterm2: $os"

    local prefs_dir="$HOME/.config/iterm2"
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$prefs_dir"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
    info "iterm2: loading prefs from $prefs_dir (restart iTerm2 to apply)"
}

main "$@"
