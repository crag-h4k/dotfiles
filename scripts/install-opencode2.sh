#!/usr/bin/env bash
# scripts/install-opencode2.sh
# Install OpenCode V2 in an isolated npm prefix.
#
# Chezmoi owns the wrapper and OpenCode configuration, but npm owns the installed
# release. That lets OpenCode's native /update command and package-mode updates
# operate on the same installation. Do not add a release-pointer layer here: the
# native updater can only recognize a conventional global npm installation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

OPENCODE2_VERSION="${OPENCODE2_VERSION:-latest}"
NPM_PREFIX="${OPENCODE2_NPM_PREFIX:-$HOME/.local/share/opencode2}"
WRAPPER="${OPENCODE2_WRAPPER:-$HOME/.local/bin/opencode2}"
CONFIG_DIR="${OPENCODE2_CONFIG_DIR:-$HOME/.config/opencode}"

canonical_path() {
    python3 - "$1" <<'PY'
import os
import sys

print(os.path.realpath(os.path.abspath(os.path.expanduser(sys.argv[1]))))
PY
}

main() {
    if [[ "${INSTALL_AI_OPENCODE:-false}" != true ]]; then
        return 0
    fi
    if [[ "${DOTFILES_NODE_READY:-true}" != true ]]; then
        warn "opencode2: Node.js 24+ is not ready; skipped"
        return 2
    fi
    command -v npm >/dev/null 2>&1 \
        || { warn "opencode2: npm not found; skipped"; return 1; }
    command -v python3 >/dev/null 2>&1 \
        || { warn "opencode2: python3 is required for atomic activation"; return 1; }

    NPM_PREFIX="$(canonical_path "$NPM_PREFIX")" \
        || die "opencode2: could not canonicalize npm prefix"
    WRAPPER="$(canonical_path "$WRAPPER")" \
        || die "opencode2: could not canonicalize managed wrapper"
    CONFIG_DIR="$(canonical_path "$CONFIG_DIR")" \
        || die "opencode2: could not canonicalize config directory"
    export OPENCODE2_NPM_PREFIX="$NPM_PREFIX"

    local native_link="$NPM_PREFIX/bin/opencode2"
    local resolved_native
    if [[ -x "$native_link" ]]; then
        resolved_native="$(canonical_path "$native_link")" \
            || die "opencode2: could not canonicalize isolated binary"
        [[ "$resolved_native" != "$WRAPPER" ]] \
            || die "opencode2: isolated binary resolves to the managed wrapper"
    fi
    [[ -x "$WRAPPER" ]] \
        || { warn "opencode2: managed wrapper missing at $WRAPPER"; return 1; }

    # Server plugins resolve SDK imports from this local runtime. It is refreshed
    # from the active CLI version, never pinned in the dotfiles repository.
    local legacy_runtime="$HOME/.config/opencode/node_modules"
    if [[ -L "$legacy_runtime" ]]; then
        rm -f "$legacy_runtime"
    fi

    local npm_version
    local -a cli_install_args=(install -g --prefix "$NPM_PREFIX")
    npm_version=$(npm --version)
    # npm 12 blocks the postinstall that replaces the CLI's launcher placeholder.
    if [[ "${npm_version%%.*}" -ge 12 ]]; then
        cli_install_args+=(--allow-scripts=@opencode/cli)
    fi
    if ! npm "${cli_install_args[@]}" "@opencode/cli@$OPENCODE2_VERSION"; then
        warn "opencode2: npm install failed"
        return 1
    fi
    if [[ ! -x "$native_link" ]]; then
        warn "opencode2: npm did not install an executable at $native_link"
        return 1
    fi
    local have
    have=$("$native_link" --version 2>/dev/null | awk '{print $NF}' | tr -d '[:space:]' || true)
    have="${have#v}"
    if [[ -z "$have" ]]; then
        warn "opencode2: installed CLI did not report a version"
        return 1
    fi
    if [[ "$OPENCODE2_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] \
        && [[ "$have" != "$OPENCODE2_VERSION" ]]; then
        warn "opencode2: installed CLI version ${have:-unknown} does not match pin $OPENCODE2_VERSION"
        return 1
    fi
    if [[ "$("$WRAPPER" --version 2>/dev/null || true)" != "$("$native_link" --version 2>/dev/null || true)" ]]; then
        warn "opencode2: wrapper does not resolve to the installed CLI"
        return 1
    fi

    local runtime_sync="${OPENCODE2_RUNTIME_SYNC:-$SCRIPT_DIR/../home/dot_config/opencode/executable_sync-runtime.sh}"
    if [[ ! -f "$runtime_sync" ]]; then
        warn "opencode2: plugin runtime helper missing at $runtime_sync"
        return 1
    fi
    if ! bash "$runtime_sync" "$native_link" "$CONFIG_DIR"; then
        warn "opencode2: matching plugin runtime install failed"
        return 1
    fi

    info "opencode2: installed @opencode/cli@${have:-$OPENCODE2_VERSION} and matching plugin runtime"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
