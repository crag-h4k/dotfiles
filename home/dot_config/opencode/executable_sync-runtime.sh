# shellcheck shell=bash
# ~/.config/opencode/sync-runtime.sh
# Keep local OpenCode plugins on the same SDK version as the npm-owned CLI.

set -euo pipefail

# A fresh SDK can require OpenTUI released the same day. Other packages keep aging.
export NPM_CONFIG_MIN_RELEASE_AGE_EXCLUDE='@opencode/*,@opentui/*'

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
runtime_healthy() {
    node - "$config_dir" <<'JS'
const fs = require("node:fs")
const path = require("node:path")
for (const name of ["@opencode/plugin", "@opentui/core", "@opentui/solid", "solid-js"]) {
  const file = path.join(process.argv[2], "node_modules", name, "package.json")
  const pkg = JSON.parse(fs.readFileSync(file, "utf8"))
  if (!pkg.version) process.exit(1)
  const entry = pkg.exports?.["."]?.import
  if (typeof entry === "string") fs.accessSync(path.resolve(path.dirname(file), entry))
  else require.resolve(name, { paths: [process.argv[2]] })
}
JS
}
if [[ "$runtime_version" == "$cli_version" ]] && runtime_healthy >/dev/null 2>&1; then
    exit 0
fi

runtime_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=npm-candidate.sh
source "$runtime_dir/npm-candidate.sh"

sdk_peers="$(npm view "@opencode/plugin@$cli_version" peerDependencies --json 2>/dev/null)" || {
    printf 'opencode2: could not read the SDK peer requirements\n' >&2
    exit 1
}
opentui_requirement="$(node -e '
try {
  const value=JSON.parse(process.argv[1])["@opentui/solid"]
  if (typeof value !== "string" || !value.trim()) process.exit(1)
  console.log(value)
} catch { process.exit(1) }' "$sdk_peers")" || {
    printf 'opencode2: SDK does not declare an OpenTUI Solid requirement\n' >&2
    exit 1
}
opentui_version="$(_resolve_npm_candidate @opentui/solid "$opentui_requirement")" || {
    printf 'opencode2: could not resolve an eligible OpenTUI Solid release\n' >&2
    exit 1
}
tui_requirements="$(npm view "@opentui/solid@$opentui_version" dependencies peerDependencies --json 2>/dev/null)" || {
    printf 'opencode2: could not read OpenTUI Solid dependency requirements\n' >&2
    exit 1
}
peer_ranges="$(node -e '
try {
  const [sdk,tui]=process.argv.slice(1).map(JSON.parse)
  const ranges=["@opentui/core","solid-js"].map(name => {
    const left=sdk[name]
    const constraints=[tui.dependencies?.[name],tui.peerDependencies?.[name]].filter(value => value !== undefined)
    if (typeof left !== "string" || !left.trim() || !constraints.length) process.exit(1)
    return constraints.reduce((range,right) => {
      if (typeof right !== "string" || !right.trim()) process.exit(1)
      return range.split("||").flatMap(a => right.split("||").map(b => a.trim()+" "+b.trim())).join(" || ")
    },left)
  })
  console.log(ranges.join("\t"))
} catch { process.exit(1) }' "$sdk_peers" "$tui_requirements")" || {
    printf 'opencode2: incomplete SDK or OpenTUI dependency requirements\n' >&2
    exit 1
}
IFS=$'\t' read -r core_requirement solid_requirement <<<"$peer_ranges"

core_version="$(_resolve_npm_candidate @opentui/core "$core_requirement")" || {
    printf 'opencode2: could not resolve a compatible OpenTUI Core release\n' >&2
    exit 1
}

solid_version="$(_resolve_npm_candidate solid-js "$solid_requirement")" || {
    printf 'opencode2: could not resolve an eligible Solid.js peer release\n' >&2
    exit 1
}

npm install --prefix "$config_dir" --ignore-scripts --package-lock=false --no-save \
    "@opencode/plugin@$cli_version" "@opentui/core@$core_version" \
    "@opentui/solid@$opentui_version" "solid-js@$solid_version"

node - "$config_dir" "$cli_version" "$core_version" "$opentui_version" "$solid_version" <<'JS'
const fs = require("node:fs")
const path = require("node:path")
const [config,...versions] = process.argv.slice(2)
const names = ["@opencode/plugin", "@opentui/core", "@opentui/solid", "solid-js"]
for (const [index,name] of names.entries()) {
  const file = path.join(config, "node_modules", name, "package.json")
  if (JSON.parse(fs.readFileSync(file, "utf8")).version !== versions[index]) {
    console.error("opencode2: installed runtime version differs from its resolved candidate: " + name)
    process.exit(1)
  }
}
JS

runtime_version="$(node -p "JSON.parse(require('node:fs').readFileSync(process.argv[1], 'utf8')).version" "$runtime_package" 2>/dev/null || true)"
[[ "$runtime_version" == "$cli_version" ]] || {
    printf 'opencode2: plugin runtime does not match CLI version %s\n' "$cli_version" >&2
    exit 1
}
runtime_healthy || {
    printf 'opencode2: plugin runtime dependencies are incomplete\n' >&2
    exit 1
}
