#!/usr/bin/env bash
# scripts/install-opencode2.sh
# Opt-in OpenCode v2 beta install (ai > opencode2 sub-feature). Side-by-side with
# v1: the @opencode/cli npm package installs an `opencode2` binary into the repo's
# standard ~/.local prefix, sharing the same ~/.config/opencode/ directory as v1.
# npm is chosen over the raw install script for the same reasons as
# install-opencode.sh (exact pinning + the ~/.local prefix). Self-skips when a
# pinned version is already present, and soft-fails so a fetch problem never aborts
# the wider `chezmoi apply`.
#
# Reachability depends on the zsh component: it puts ~/.local/bin on PATH (via
# ~/.zshenv) and defines the oc2/oc2bg aliases. With zsh deselected the binary
# still installs but is not on PATH by name and has no aliases (run by full path or
# add ~/.local/bin to PATH). Node/npm is planned by scripts/package-plan.sh for any
# Node-dependent AI feature, so opencode2 no longer needs neovim to get a runtime.
#
# The generic config (theme, notifier bridge) is chezmoi-managed and shared with
# v1; the private work layer (agents, mcp/instructions, work overlay) is unmanaged
# local files this script never touches.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# OpenCode v2 release channel. Defaults to the floating `beta` dist-tag: v2 is a
# beta rewrite and `beta` is its only live channel that moves forward. The
# `latest`/`reserved` tags are dead 0.0.0-reserved placeholders (a bare install
# gets nothing), and `dev` is an unstable feature build. Set OPENCODE2_VERSION to
# an exact version (e.g. 0.0.0-beta-19398) to pin instead; an exact pin self-skips
# on match, while the floating `beta` tag always reinstalls to pull newest forward.
OPENCODE2_VERSION="${OPENCODE2_VERSION:-beta}"
NPM_PREFIX="${OPENCODE2_NPM_PREFIX:-$HOME/.local}"

main() {
    if [[ "${INSTALL_AI_OPENCODE2:-false}" != true ]]; then
        return 0
    fi

    # Exact pin: skip when the installed version already matches. `opencode2
    # --version` prints "opencode2 v<ver>", so take the last field and strip the
    # leading v to compare against the npm version. The floating `beta` tag can't
    # be compared to a version, so it always (re)installs to pull newest forward.
    if [[ "$OPENCODE2_VERSION" != beta ]] && command -v opencode2 >/dev/null 2>&1; then
        local have
        # `|| true`: a present-but-unhealthy binary can exit nonzero, which under
        # `set -o pipefail` would make this substitution fail and (with set -e)
        # abort the installer before its soft-fail/reinstall path runs.
        have="$(opencode2 --version 2>/dev/null | awk '{print $NF}' | tr -d '[:space:]' || true)"
        have="${have#v}"
        if [[ "$have" == "$OPENCODE2_VERSION" ]]; then
            info "opencode2: v$OPENCODE2_VERSION already installed; skipping"
            return 0
        fi
        info "opencode2: found ${have:-unknown}, installing pinned v$OPENCODE2_VERSION"
    fi

    if ! command -v npm >/dev/null 2>&1; then
        warn "opencode2: npm not found; skipping. Install Node.js (the neovim component provides it) then re-run, or install opencode2 manually (curl -fsSL https://opencode.ai/v2/install | bash)."
        return 0
    fi

    if ! npm install -g --prefix "$NPM_PREFIX" "@opencode/cli@$OPENCODE2_VERSION"; then
        warn "opencode2 install failed; continuing without it (retry: OPENCODE2_VERSION=$OPENCODE2_VERSION bash scripts/install-opencode2.sh)"
        return 0
    fi
    info "opencode2: installed @opencode/cli@$OPENCODE2_VERSION to $NPM_PREFIX/bin (reachable on PATH + via the oc2/oc2bg aliases when the zsh component is enabled; otherwise run $NPM_PREFIX/bin/opencode2 directly)"
}

main "$@"
