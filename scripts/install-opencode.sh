#!/usr/bin/env bash
# scripts/install-opencode.sh
# Opt-in OpenCode CLI install (ai > opencode sub-feature). Cross-platform
# (macOS + Debian) via the opencode-ai npm package, which fetches the prebuilt
# platform binary on postinstall. npm is chosen over the raw install script
# because it pins an EXACT version and installs into the repo's standard
# ~/.local prefix (binary lands in ~/.local/bin, already on PATH via dot_zshenv) -
# the same pattern the repo already uses for markdownlint-cli2, prettierd, and
# claude-agent-acp. Self-skips when the pinned version is already present, and
# soft-fails so a fetch problem never aborts the wider `chezmoi apply`.
#
# The generic config (~/.config/opencode/opencode.jsonc), theme, and notifier
# bridge (~/.config/opencode/plugins/notify.ts) are chezmoi-managed; the private
# work layer (agents, mcp/instructions, work.ts) is unmanaged local files this
# script never touches.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# OpenCode release channel. Defaults to the floating `latest` dist-tag so the CLI
# stays current: an earlier exact pin (0.6.3) silently went a year stale because the
# self-skip below never re-checked npm. Set OPENCODE_VERSION=x.y.z to pin an exact
# release instead (that still self-skips on match; `latest` always reinstalls to
# pull the newest forward). NOTE: `latest` is opencode-ai's newest STABLE release;
# the beta/next/dev/snapshot-* tags are 0.0.0-* unstable feature builds, not ahead
# of it, so they are not a "prerelease" channel to prefer.
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"
NPM_PREFIX="${OPENCODE_NPM_PREFIX:-$HOME/.local}"

main() {
    if [[ "${INSTALL_AI_OPENCODE:-false}" != true ]]; then
        return 0
    fi

    # Exact pin: skip when the installed version already matches. The floating
    # `latest` tag can't be compared to `opencode --version`, so it always
    # (re)installs to pull the newest stable forward.
    if [[ "$OPENCODE_VERSION" != latest ]] && command -v opencode >/dev/null 2>&1; then
        local have
        # `|| true`: a present-but-unhealthy binary can exit nonzero, which under
        # `set -o pipefail` would make this substitution fail and (with set -e)
        # abort the installer before its soft-fail/reinstall path runs.
        have="$(opencode --version 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ "$have" == "$OPENCODE_VERSION" ]]; then
            info "opencode: v$OPENCODE_VERSION already installed; skipping"
            return 0
        fi
        info "opencode: found ${have:-unknown}, installing pinned v$OPENCODE_VERSION"
    fi

    if ! command -v npm >/dev/null 2>&1; then
        warn "opencode: npm not found; skipping. Install Node.js (the neovim component provides it) then re-run, or install opencode manually (brew install anomalyco/tap/opencode, or curl -fsSL https://opencode.ai/install | bash)."
        return 0
    fi

    if ! npm install -g --prefix "$NPM_PREFIX" "opencode-ai@$OPENCODE_VERSION"; then
        warn "opencode install failed; continuing without it (retry: OPENCODE_VERSION=$OPENCODE_VERSION bash scripts/install-opencode.sh)"
        return 0
    fi
    info "opencode: installed opencode-ai@$OPENCODE_VERSION to $NPM_PREFIX/bin"
}

main "$@"
