#!/usr/bin/env bash
# macOS-only iTerm2 setup. Profiles are managed declaratively as iTerm2 Dynamic
# Profiles (JSON). The JSON is kept at a clean, chezmoi-managed path
# (~/.config/iterm2/dotfiles.json) and symlinked into the one directory iTerm2
# reads dynamic profiles from (~/Library/Application Support/iTerm2/
# DynamicProfiles/), so the repo carries no ~/Library tree. This script creates
# that symlink, pins the default-profile Guid, and sets a few app-level behavior
# toggles that Dynamic Profiles cannot express. The iTerm2 cask itself is
# installed by the batched brew call in install.sh; the AI API key lives in the
# macOS Keychain and is deliberately not managed here.
#
# A running iTerm2 rewrites its prefs domain on quit, so the `defaults write`s
# stick best when iTerm2 is not running; restart iTerm2 to pick them up.

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

    # iTerm2 only reads Dynamic Profiles from this fixed directory. Symlink the
    # chezmoi-managed JSON in, rather than committing a ~/Library tree to the repo.
    local dyn_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    mkdir -p "$dyn_dir"
    ln -sf "$HOME/.config/iterm2/dotfiles.json" "$dyn_dir/dotfiles.json"

    local domain=com.googlecode.iterm2

    # Default profile is "dotfiles". Dynamic profiles are read-only in the UI, so
    # the default is pinned by Guid in the prefs domain rather than in the JSON.
    # This is the Guid from dot_config/iterm2/dotfiles.json.tmpl (freshly minted so it
    # does not collide with any pre-existing regular profile).
    defaults write "$domain" "Default Bookmark Guid" \
        -string "F8CE7F87-BEC0-4312-92FA-B86B14B031D2"

    # App-level behavior toggles that Dynamic Profiles cannot carry (see README).
    # "key value" pairs; the key may contain spaces (e.g. "Print In Black And White").
    local -a bools=(
        "AllowClipboardAccess true"
        "AlternateMouseScroll true"
        "QuitWhenAllWindowsClosed true"
        "ShowFullScreenTabBar true"
        "SoundForEsc false"
        "VisualIndicatorForEsc false"
        "HapticFeedbackForEsc false"
        "PreventEscapeSequenceFromClearingHistory false"
        "Print In Black And White true"
    )
    local entry key val
    for entry in "${bools[@]}"; do
        val="${entry##* }"
        key="${entry% *}"
        defaults write "$domain" "$key" -bool "$val"
    done

    info "iterm2: linked ~/.config/iterm2/dotfiles.json into DynamicProfiles; restart iTerm2 to apply the global defaults"
}

main "$@"
