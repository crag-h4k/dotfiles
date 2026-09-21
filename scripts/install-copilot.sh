#!/usr/bin/env bash
# scripts/install-copilot.sh
# Opt-in GitHub Copilot CLI install (ai > copilot sub-feature). Cross-platform
# (macOS + Debian) via the @github/copilot npm package. npm is the ONLY
# distribution channel: there is no Homebrew formula or apt package for it
# (Homebrew's `copilot` is AWS's ECS/Fargate CLI, an unrelated tool). Installs
# into the repo's standard ~/.local prefix (binary lands in ~/.local/bin, already
# on PATH via dot_zshenv) - the same pattern as OpenCode V2 and claude-agent-acp.
#
# Tracks the `prerelease` dist-tag by default (COPILOT_VERSION overrides), so it
# floats forward to the newest prerelease each time this script runs. Because the
# tag floats there is no exact-version self-skip; the reinstall is a fast no-op
# when already current. Soft-fails so a fetch problem never aborts `chezmoi apply`.
# Requires Node 22+ (the neovim component provides Node via NodeSource on Debian /
# Homebrew on macOS).
#
# Only the CLI binary is installed here. Any enterprise Copilot config stays
# out of this public repo; it is unmanaged local state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Dist-tag or exact version to install. Defaults to the floating `prerelease`
# tag; set COPILOT_VERSION=x.y.z to pin, or =latest for the stable channel.
COPILOT_VERSION="${COPILOT_VERSION:-prerelease}"
NPM_PREFIX="${COPILOT_NPM_PREFIX:-$HOME/.local}"

main() {
    if [[ "${INSTALL_AI_COPILOT:-false}" != true ]]; then
        return 0
    fi
    if [[ "${DOTFILES_NODE_READY:-true}" != true ]]; then
        warn "copilot: Node.js 24 is not ready; skipped"
        return 2
    fi

    if ! command -v npm >/dev/null 2>&1; then
        warn "copilot: npm not found; skipping. Re-run approved package mode to install Node.js 22+, then retry: COPILOT_VERSION=$COPILOT_VERSION bash scripts/install-copilot.sh"
        return 1
    fi

    if command -v copilot >/dev/null 2>&1; then
        local have
        have="$(copilot --version 2>/dev/null | tr -d '[:space:]')"
        info "copilot: found ${have:-unknown}; refreshing to @$COPILOT_VERSION"
    fi

    if ! npm install -g --prefix "$NPM_PREFIX" "@github/copilot@$COPILOT_VERSION"; then
        warn "copilot install failed; continuing without it (retry: COPILOT_VERSION=$COPILOT_VERSION bash scripts/install-copilot.sh)"
        return 1
    fi
    info "copilot: installed @$COPILOT_VERSION to $NPM_PREFIX/bin"
}

main "$@"
