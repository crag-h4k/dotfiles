#!/usr/bin/env bash
# scripts/opencode-talk/build.sh
# Build the voice plugin for OpenCode V2: opencode-talk at one audited commit, four
# local patches, and a helper compiled from source. The result is installed as a
# local plugin at ~/.config/opencode/v2-plugins/talk. The run_before_20 chezmoi
# script calls this file on every apply, but only when the components.ai.voice data
# key is on. It is also safe to run by hand.
#
# Every run starts with a stamp check, so an up to date install costs a hash and a
# few file tests, with no compiler, git, or network. The stamp is a SHA-256 of this
# script (which carries the pin), the pinned commit, and every patch, and it lives at
# $DEST/.build-stamp. A run rebuilds when the stamp is missing, when it differs, or
# when tui.js or bin/opencode-talk-helper is gone. A failed build writes no stamp and
# leaves the previous install and stamp alone, so the next apply tries again.
#
# Why not the npm package: its tarball leaves out helper/main.swift, hardcodes the
# helper path to <plugin>/../bin/opencode-talk-helper, and ships a prebuilt binary
# nobody can verify. Why patches: see the header of each file next to this script.
#
# This script never runs the helper. Microphone and Speech Recognition permission
# are granted once, by hand, with `opencode-talk-helper check`; a rebuild changes
# the ad-hoc signature, so macOS asks again.
#
# Usage: build.sh [--force]    --force rebuilds even when the stamp matches.
#
# Environment (all optional):
#   OPENCODE_TALK_DEST       install directory (default ~/.config/opencode/v2-plugins/talk)
#   OPENCODE_TALK_REPO       clone URL (default the upstream GitHub repository)
#   DOTFILES_INSTALL_MODE    "configs" skips the build (configs-only keeps installs off)
#
# Exit status: 0 on success or a deliberate skip, non-zero on failure. The failed
# build leaves any previous install untouched.
set -euo pipefail

PIN_TAG="v0.1.1"
PIN_SHA="5688bae8038ddf1eba35f82f86a0b1215ef93698"
REPO_URL="${OPENCODE_TALK_REPO:-https://github.com/batuhansk/opencode-talk.git}"
DEST="${OPENCODE_TALK_DEST:-$HOME/.config/opencode/v2-plugins/talk}"
# Applied in this order. A patch missing from this list never reaches the build, so the
# list is explicit and a test pins it to the files on disk.
PATCHES=(
    0001-helper-on-device-only.patch
    0002-indicator-before-footer-status.patch
    0003-spoken-submit-send-it-only.patch
    0004-spoken-submit-needs-autosend.patch
)
STAMP_FILE=".build-stamp"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
force=0
if [ "${1:-}" = --force ]; then force=1; fi
work=""
stage=""
backup=""

say() { printf 'opencode-talk: %s\n' "$*"; }
die() { printf 'opencode-talk: %s\n' "$*" >&2; exit 1; }

cleanup() {
    [ -z "$work" ] || rm -rf "$work"
    [ -z "$stage" ] || rm -rf "$stage"
    # Only reached with a backup still set when the swap failed midway.
    if [ -n "$backup" ] && [ -e "$backup" ] && [ ! -e "$DEST" ]; then
        mv "$backup" "$DEST" || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Where the build can and should run -------------------------------------

if [ "${DOTFILES_INSTALL_MODE:-packages}" = configs ]; then
    say "configs-only mode: not building the helper. Run $0 to build it."
    exit 0
fi
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    say "skipped: the dictation helper builds for macOS on Apple silicon only"
    exit 0
fi
macos="$(sw_vers -productVersion)"
if [ "${macos%%.*}" -lt 26 ] 2>/dev/null; then
    say "skipped: macOS 26 or newer is required (this is $macos)"
    exit 0
fi

# --- Up to date? ------------------------------------------------------------

for patch in "${PATCHES[@]}"; do
    [ -f "$SCRIPT_DIR/$patch" ] || die "missing patch $patch"
done
command -v shasum >/dev/null 2>&1 || die "shasum not found"
want="$({
    printf '%s\n' "$PIN_SHA"
    cat "$SCRIPT_DIR/build.sh"
    for patch in "${PATCHES[@]}"; do cat "$SCRIPT_DIR/$patch"; done
} | shasum -a 256)"
want="${want%% *}"
if [ "$force" -eq 0 ] && [ -f "$DEST/$STAMP_FILE" ] && [ -f "$DEST/tui.js" ] &&
    [ -x "$DEST/bin/opencode-talk-helper" ] && [ "$(cat "$DEST/$STAMP_FILE")" = "$want" ]; then
    exit 0
fi

# --- Tools -----------------------------------------------------------------

for tool in git swiftc codesign; do
    command -v "$tool" >/dev/null 2>&1 ||
        die "$tool not found. Install the Xcode Command Line Tools (xcode-select --install) and try again."
done

# --- Fetch the pinned commit and patch it ------------------------------------

work="$(mktemp -d "${TMPDIR:-/tmp}/opencode-talk.XXXXXX")"
src="$work/src"

say "fetching opencode-talk $PIN_TAG ($PIN_SHA)"
GIT_TERMINAL_PROMPT=0 git clone --quiet --no-checkout "$REPO_URL" "$src" ||
    die "could not clone $REPO_URL"
git -C "$src" checkout --quiet --detach "$PIN_SHA" ||
    die "commit $PIN_SHA is not in $REPO_URL"
checked_out="$(git -C "$src" rev-parse HEAD)"
[ "$checked_out" = "$PIN_SHA" ] ||
    die "checked out $checked_out but the pin is $PIN_SHA; refusing to build"

for patch in "${PATCHES[@]}"; do
    file="$SCRIPT_DIR/$patch"
    git -C "$src" apply --check "$file" ||
        die "$patch does not apply to $PIN_SHA; review the upstream change before moving the pin"
    git -C "$src" apply "$file" || die "could not apply $patch"
    say "applied $patch"
done

# --- Build and sign the helper (arm64 only, never executed) -------------------

mkdir -p "$src/bin"
(
    cd "$src"
    swiftc -O -swift-version 6 -target arm64-apple-macos14 helper/main.swift \
        -o bin/opencode-talk-helper \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker helper/Info.plist
) || die "swiftc failed"
codesign --force --sign - --identifier dev.opencode-talk.helper "$src/bin/opencode-talk-helper" ||
    die "codesign failed"
codesign --verify --strict "$src/bin/opencode-talk-helper" || die "the built helper failed signature verification"

# --- Stage next to the destination, verify, then swap -------------------------

parent="$(dirname "$DEST")"
name="$(basename "$DEST")"
mkdir -p "$parent"
stage="$parent/.$name.new.$$"
mkdir "$stage" "$stage/bin"
cp "$src/tui.js" "$src/package.json" "$src/LICENSE" "$stage/"
cp -R "$src/lib" "$stage/lib"
cp "$src/bin/opencode-talk-helper" "$stage/bin/opencode-talk-helper"
printf '%s\n' "$PIN_SHA" >"$stage/PINNED_COMMIT"
printf '%s\n' "$want" >"$stage/$STAMP_FILE"
codesign --verify --strict "$stage/bin/opencode-talk-helper" || die "the staged helper failed signature verification"

if [ -e "$DEST" ]; then
    backup="$parent/.$name.old.$$"
    mv "$DEST" "$backup" || die "could not move the previous install aside"
fi
if ! mv "$stage" "$DEST"; then
    die "could not install into $DEST"
fi
stage=""
if [ -n "$backup" ]; then
    rm -rf "$backup"
    backup=""
fi

say "built $PIN_TAG into $DEST"
say "one-time step: run $DEST/bin/opencode-talk-helper check yourself to grant Microphone and Speech Recognition access"
