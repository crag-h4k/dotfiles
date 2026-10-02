# shellcheck shell=bash
# ~/.config/opencode/sync-runtime.sh
# Keep local OpenCode plugins on the same SDK version as the npm-owned CLI.

set -euo pipefail

binary="${1:?usage: sync-runtime.sh OPENCODE_BINARY [CONFIG_DIR]}"
config_dir="${2:-$HOME/.config/opencode}"
runtime_package="$config_dir/node_modules/@opencode/plugin/package.json"

command -v npm >/dev/null 2>&1 || {
    printf 'opencode2: npm is required to sync the local plugin runtime\n' >&2
    exit 1
}
command -v node >/dev/null 2>&1 || {
    printf 'opencode2: Node.js is required to sync the local plugin runtime\n' >&2
    exit 1
}

cli_version="$("$binary" --version 2>/dev/null | awk '{print $NF}' | tr -d '[:space:]')"
cli_version="${cli_version#v}"
[[ -n "$cli_version" ]] || {
    printf 'opencode2: could not determine the installed CLI version\n' >&2
    exit 1
}

runtime_version=""
if [[ -r "$runtime_package" ]]; then
    runtime_version="$(node -p "JSON.parse(require('node:fs').readFileSync(process.argv[1], 'utf8')).version" "$runtime_package" 2>/dev/null || true)"
fi
[[ "$runtime_version" == "$cli_version" ]] && exit 0

opentui_version="$(npm view @opentui/solid@latest version 2>/dev/null)" || {
    printf 'opencode2: could not resolve the OpenTUI Solid release\n' >&2
    exit 1
}
solid_requirement="$(npm view "@opentui/solid@$opentui_version" peerDependencies.solid-js 2>/dev/null)" || {
    printf 'opencode2: could not resolve OpenTUI Solid peer dependencies\n' >&2
    exit 1
}
[[ -n "$opentui_version" && -n "$solid_requirement" ]] || {
    printf 'opencode2: npm returned incomplete plugin runtime metadata\n' >&2
    exit 1
}

npm install --prefix "$config_dir" --ignore-scripts --package-lock=false --no-save \
    "@opencode/plugin@$cli_version" "@opentui/solid@$opentui_version" "solid-js@$solid_requirement"

runtime_version="$(node -p "JSON.parse(require('node:fs').readFileSync(process.argv[1], 'utf8')).version" "$runtime_package" 2>/dev/null || true)"
[[ "$runtime_version" == "$cli_version" ]] || {
    printf 'opencode2: plugin runtime does not match CLI version %s\n' "$cli_version" >&2
    exit 1
}
