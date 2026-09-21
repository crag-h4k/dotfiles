#!/usr/bin/env bash
# scripts/install-opencode2.sh
# Install OpenCode V2 and its local plugin runtime transactionally.
# Chezmoi owns ~/.local/bin/opencode2 as a wrapper. This installer switches only
# the isolated native binary under ~/.local/share/opencode2 and node_modules
# under ~/.config/opencode after both staged installations pass verification.

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

verify_opencode_runtime() {
    local runtime="$1" cli_version="$2"
    node -e '
const fs = require("fs")
const path = process.argv[1]
const cliVersion = process.argv[2]
for (const name of ["@opencode/plugin", "@opentui/solid", "solid-js"]) {
  require.resolve(name, { paths: [path] })
}
const plugin = JSON.parse(fs.readFileSync(path + "/node_modules/@opencode/plugin/package.json", "utf8"))
if (plugin.version !== cliVersion) process.exit(2)
' "$runtime" "$cli_version"
}

restore_runtime_path() {
    local target="$1" old_link="$2" old_dir="$3"
    rm -f "$target"
    if [[ -n "$old_link" ]]; then
        ln -s "$old_link" "$target"
    elif [[ -n "$old_dir" ]]; then
        mv "$old_dir" "$target"
    fi
}

restore_native_link() {
    local target="$1" old_link="$2"
    rm -f "$target"
    [[ -z "$old_link" ]] || ln -s "$old_link" "$target"
}

main() {
    if [[ "${INSTALL_AI_OPENCODE:-false}" != true ]]; then
        return 0
    fi
    if [[ "${DOTFILES_NODE_READY:-true}" != true ]]; then
        warn "opencode2: Node.js 24 is not ready; skipped"
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
    resolved_native="$(canonical_path "$native_link")" \
        || die "opencode2: could not canonicalize isolated binary"
    [[ "$resolved_native" != "$WRAPPER" ]] \
        || die "opencode2: isolated binary resolves to the managed wrapper"
    if [[ -e "$native_link" && ! -L "$native_link" ]]; then
        warn "opencode2: refusing to replace non-symlink $native_link"
        return 1
    fi
    [[ -x "$WRAPPER" ]] \
        || { warn "opencode2: managed wrapper missing at $WRAPPER"; return 1; }
    local cli_releases="$NPM_PREFIX/releases"
    local runtime_releases="$NPM_PREFIX/plugin-runtime/releases"
    local cli_stage runtime_stage installed have release_id cli_release runtime_release
    local runtime_path="$CONFIG_DIR/node_modules"
    local old_native_link="" old_runtime_link="" old_runtime_dir=""
    local native_link_tmp runtime_link_tmp
    mkdir -p "$cli_releases" "$runtime_releases" "$NPM_PREFIX/bin"
    cli_stage=$(mktemp -d "$cli_releases/.stage.XXXXXX")
    runtime_stage=$(mktemp -d "$runtime_releases/.stage.XXXXXX")

    if ! npm install -g --prefix "$cli_stage" "@opencode/cli@$OPENCODE2_VERSION"; then
        warn "opencode2: staged CLI install failed; current CLI/runtime unchanged"
        rm -rf "$cli_stage" "$runtime_stage"
        return 1
    fi
    installed="$cli_stage/bin/opencode2"
    if [[ ! -x "$installed" ]]; then
        warn "opencode2: staged package has no opencode2 executable"
        rm -rf "$cli_stage" "$runtime_stage"
        return 1
    fi
    have=$("$installed" --version 2>/dev/null | awk '{print $NF}' | tr -d '[:space:]' || true)
    have="${have#v}"
    if [[ -z "$have" ]]; then
        warn "opencode2: staged CLI did not report a version"
        rm -rf "$cli_stage" "$runtime_stage"
        return 1
    fi
    if [[ "$OPENCODE2_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] \
        && [[ "$have" != "$OPENCODE2_VERSION" ]]; then
        warn "opencode2: staged CLI version ${have:-unknown} does not match pin $OPENCODE2_VERSION"
        rm -rf "$cli_stage" "$runtime_stage"
        return 1
    fi

    if ! npm install --prefix "$runtime_stage" --ignore-scripts \
        --package-lock=false --no-save \
        "@opencode/plugin@$have" "@opentui/solid@latest" "solid-js@latest" \
        || ! verify_opencode_runtime "$runtime_stage" "$have"; then
        warn "opencode2: staged plugin runtime failed; current CLI/runtime unchanged"
        rm -rf "$cli_stage" "$runtime_stage"
        return 1
    fi

    release_id="${have:-unknown}-$(date +%s).$$"
    cli_release="$cli_releases/$release_id"
    runtime_release="$runtime_releases/$release_id"
    mv "$cli_stage" "$cli_release"
    mv "$runtime_stage" "$runtime_release"

    if [[ -L "$runtime_path" ]]; then
        old_runtime_link=$(readlink "$runtime_path") || return 1
    elif [[ -e "$runtime_path" ]]; then
        old_runtime_dir="$runtime_releases/previous-$release_id"
        mv "$runtime_path" "$old_runtime_dir" || return 1
    fi
    runtime_link_tmp="$CONFIG_DIR/.node_modules-new.$$"
    rm -f "$runtime_link_tmp"
    ln -s "$runtime_release/node_modules" "$runtime_link_tmp" || return 1
    if ! atomic_replace_path "$runtime_link_tmp" "$runtime_path"; then
        restore_runtime_path "$runtime_path" "$old_runtime_link" "$old_runtime_dir"
        return 1
    fi

    [[ ! -L "$native_link" ]] || old_native_link=$(readlink "$native_link")
    native_link_tmp="$NPM_PREFIX/bin/.opencode2-new.$$"
    rm -f "$native_link_tmp"
    ln -s "$cli_release/bin/opencode2" "$native_link_tmp" || {
        restore_runtime_path "$runtime_path" "$old_runtime_link" "$old_runtime_dir"
        return 1
    }
    if ! atomic_replace_path "$native_link_tmp" "$native_link"; then
        restore_runtime_path "$runtime_path" "$old_runtime_link" "$old_runtime_dir"
        return 1
    fi

    local direct_version wrapper_version
    direct_version="$("$native_link" --version 2>/dev/null || true)"
    wrapper_version="$("$WRAPPER" --version 2>/dev/null || true)"
    if [[ -z "$direct_version" || "$wrapper_version" != "$direct_version" ]] \
        || ! verify_opencode_runtime "$CONFIG_DIR" "$have"; then
        restore_native_link "$native_link" "$old_native_link"
        restore_runtime_path "$runtime_path" "$old_runtime_link" "$old_runtime_dir"
        warn "opencode2: activated CLI/runtime verification failed; rolled back"
        return 1
    fi

    info "opencode2: activated @opencode/cli@${have:-$OPENCODE2_VERSION} and matching plugin runtime"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
