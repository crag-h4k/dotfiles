# shellcheck shell=bash
# scripts/package-resolve.sh
# Resolve selected packages once; installers consume these exact decisions.

_resolve_version() {
    "$1" --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?' | head -1
}

_resolve_compare() {
    if [[ -z "$candidate" || "$candidate" == - ]]; then
        status=blocked
        reason="candidate lookup failed"
    elif [[ -z "$current" || "$current" == - ]]; then
        status=planned
        reason="missing or unhealthy"
    elif [[ "${current#v}" == "${candidate#v}" ]]; then
        status=installed
        reason=current
    else
        status=update
        reason="version differs"
    fi
}

_resolve_npm_candidate() {
    local name="$1" selector="$2" directory output result=0
    directory=$(mktemp -d) || return 1
    directory=$(cd "$directory" && pwd -P) || return 1
    if ! node -e 'console.log(JSON.stringify({private:true,dependencies:{[process.argv[1]]:process.argv[2]}}))' \
        "$name" "$selector" >"$directory/package.json"; then
        rm -f "$directory/package.json"
        rmdir "$directory"
        return 1
    fi
    # A missing dependency makes outdated resolve the tag/range with npm's own
    # release-age and before filters, without installing anything. `view` ignores
    # those filters and can preview an exact version that installation rejects.
    local -a command=(npm outdated --prefix "$directory" --long --json --fetch-retries=0 --fetch-timeout=15000)
    if [[ "$name" == @opencode/cli ]]; then
        command=(env 'NPM_CONFIG_MIN_RELEASE_AGE_EXCLUDE=@opencode/*' "${command[@]}")
    fi
    output=$("${command[@]}" 2>/dev/null) || result=$?
    rm -f "$directory/package.json"
    rmdir "$directory"
    (( result <= 1 )) || return 1
    printf '%s' "$output" | node -e '
let s=""; process.stdin.on("data", c => s += c); process.stdin.on("end", () => {
  try {
    const version=JSON.parse(s)[process.argv[1]]?.wanted
    if (typeof version !== "string") process.exit(1)
    console.log(version)
  } catch { process.exit(1) }
})' "$name"
}

_resolve_npm() {
    local prefix="$HOME/.local" selector=latest manifest
    case "$name" in
        @opencode/cli) prefix="${OPENCODE2_NPM_PREFIX:-$HOME/.local/share/opencode2}"; selector="$OPENCODE2_VERSION" ;;
        @github/copilot) prefix="${COPILOT_NPM_PREFIX:-$HOME/.local}"; selector="$COPILOT_VERSION" ;;
    esac
    manifest="$prefix/lib/node_modules/$name/package.json"
    if command -v node >/dev/null 2>&1; then
        current=$(node -e 'try { console.log(require(process.argv[1]).version) } catch { process.exit(1) }' "$manifest" 2>/dev/null) || current=-
    fi
    if [[ "$policy" == pinned:* ]]; then
        candidate="${policy#pinned:}"
    elif command -v npm >/dev/null 2>&1; then
        candidate=$(_resolve_npm_candidate "$name" "$selector") || candidate=-
    else
        status=check
        reason="resolve after Node installation"
        return
    fi
    [[ -x "$prefix/bin/$probe" ]] || current=-
    if [[ "$name" == @opencode/cli && "$current" != - ]]; then
        [[ "$(_resolve_version "$prefix/bin/opencode2")" == "$current" ]] || current=-
    fi
    if ! release_version_valid "$candidate"; then candidate=-; fi
    _resolve_compare
    if [[ "$name" == @opencode/cli && "$status" == installed ]]; then
        # The native CLI and its local SDK are one installation unit.
        if ! node - "$HOME/.config/opencode" "$current" <<'JS'
const fs = require("node:fs")
const path = require("node:path")
const [config, version] = process.argv.slice(2)
try {
  for (const name of ["@opencode/plugin", "@opentui/solid", "solid-js"]) {
    const file = path.join(config, "node_modules", name, "package.json")
    const pkg = JSON.parse(fs.readFileSync(file, "utf8"))
    if (!pkg.version || (name === "@opencode/plugin" && pkg.version !== version)) process.exit(1)
    const entry = pkg.exports?.["."]?.import
    if (typeof entry === "string") fs.accessSync(path.resolve(path.dirname(file), entry))
    else require.resolve(name, { paths: [config] })
  }
} catch { process.exit(1) }
JS
        then
            status=check
            reason="matching plugin runtime needs repair"
        fi
    fi
}

_resolve_release() {
    local repository output
    if [[ "$name" != terraform ]]; then
        current=$(TENV_AUTO_INSTALL=false _resolve_version "$probe") || current=-
    fi
    case "$name" in
        neovim) repository=neovim/neovim ;;
        tenv) repository=tofuutils/tenv ;;
        yq) repository=mikefarah/yq ;;
        tree-sitter-cli) repository=tree-sitter/tree-sitter ;;
        terraform)
            local tenv_root="${TENV_ROOT:-${TFENV_ROOT:-$HOME/.tenv}}" fallback
            current=-
            if [[ -r "$tenv_root/Terraform/version" ]]; then
                fallback=$(tr -d '[:space:]' <"$tenv_root/Terraform/version")
                if release_version_valid "$fallback" && [[ -x "$tenv_root/Terraform/$fallback/terraform" ]]; then
                    current=$(TENV_AUTO_INSTALL=false _resolve_version "$tenv_root/Terraform/$fallback/terraform") || current=-
                    [[ "$current" == "$fallback" ]] || current=-
                fi
            fi
            if command -v tenv >/dev/null 2>&1; then
                if output=$(tenv --quiet tf list-remote --stable --descending 2>/dev/null); then
                    candidate=$(printf '%s\n' "$output" | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p' | head -1)
                fi
            else
                status=check
                reason="resolve after tenv installation"
                return
            fi
            if ! release_version_valid "$candidate"; then candidate=-; fi
            _resolve_compare
            return
            ;;
        *) status=blocked; reason="unsupported release source"; return ;;
    esac
    if [[ "$policy" == pinned:* ]]; then
        candidate="${policy#pinned:}"
    else
        candidate=$(github_latest_release_tag "$repository") || candidate=-
    fi
    if ! release_version_valid "$candidate"; then candidate=-; fi
    if [[ "$name" == yq ]] && ! have_mikefarah_yq; then current=-; fi
    if [[ "$name" == neovim && -n "$current" && "$current" != - ]]; then
        local root="${DOTFILES_NVIM_ROOT:-/opt/dotfiles-neovim}"
        local public_bin="${DOTFILES_NVIM_BIN:-/usr/local/bin/nvim}"
        current=$(_resolve_version "$root/current/bin/nvim") || current=-
        if ! _neovim_tree_health "$root/current" || ! _neovim_binary_health "$public_bin" \
            || [[ "$(_resolve_version "$public_bin")" != "$current" ]]; then
            current=-
        fi
    fi
    _resolve_compare
}

_resolve_python() {
    local python="$HOME/.local/share/nvim-venv/bin/python" output
    if [[ -x "$python" ]]; then
        current=$("$python" -c 'import importlib.metadata, pynvim; print(importlib.metadata.version("pynvim"))' 2>/dev/null) || current=-
    fi
    if output=$(curl -fsSL --connect-timeout 10 --max-time 30 https://pypi.org/pypi/pynvim/json); then
        if command -v python3 >/dev/null 2>&1; then
            candidate=$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["version"])' 2>/dev/null) || candidate=-
        fi
    fi
    _resolve_compare
}

_resolve_luarocks() {
    local output lua_args=() lua_dir
    if ! command -v luarocks >/dev/null 2>&1; then
        status=check
        reason="resolve after LuaRocks installation"
        return
    fi
    if [[ "$(_plan_os)" == macos ]]; then
        lua_dir=$(brew --prefix lua@5.4 2>/dev/null) || {
            status=check
            reason="resolve after Lua 5.4 installation"
            return
        }
        lua_args=(--lua-version=5.4 --lua-dir "$lua_dir")
    fi
    if output=$(luarocks "${lua_args[@]}" --tree "$HOME/.luarocks" list --porcelain "$name" 2>/dev/null); then
        current=$(printf '%s\n' "$output" | awk -v name="$name" '$1 == name { print $2; exit }')
    fi
    if output=$(luarocks "${lua_args[@]}" --tree "$HOME/.luarocks" search --porcelain "$name" 2>/dev/null); then
        candidate=$(printf '%s\n' "$output" | awk -v name="$name" '$1 == name && $2 ~ /^[0-9]/ { print $2; exit }')
    fi
    [[ -x "$HOME/.luarocks/bin/$probe" ]] || current=-
    _resolve_compare
}

_resolve_git() {
    local output remote_ref base _git_head="" _git_ref="" _git_branch="" _git_problem=""
    if ! command -v git >/dev/null 2>&1; then
        status=check reason="resolve after Git installation"
        return
    fi
    if [[ ! -e "$probe" && ! -L "$probe" ]]; then
        if [[ "$source" == git-external ]]; then
            status=check reason="resolve after chezmoi materializes the checkout"
            return
        fi
        if ! output=$(git ls-remote --symref -- "$origin" HEAD 2>/dev/null); then
            status=blocked reason="remote HEAD lookup failed"
            return
        fi
        remote_ref=$(printf '%s\n' "$output" | awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }')
        candidate=$(printf '%s\n' "$output" | awk '$2 == "HEAD" && $1 != "ref:" { print $1; exit }')
        if [[ "$remote_ref" != refs/heads/* || ! "$candidate" =~ ^[0-9a-f]{40,64}$ ]]; then
            status=blocked reason="remote HEAD is not a branch with an exact commit"
            return
        fi
        policy="branch:${remote_ref#refs/heads/}"
        status=planned reason="missing checkout"
        return
    fi
    if ! git_checkout_inspect "$origin" "$probe"; then
        status=blocked reason="$_git_problem"
        return
    fi
    current="$_git_head"
    policy="branch:$_git_branch"
    [[ "$_git_branch" == "${_git_ref#refs/heads/}" ]] || policy+=":${_git_ref#refs/heads/}"
    if ! output=$(git ls-remote --exit-code -- "$origin" "$_git_ref" 2>/dev/null); then
        status=blocked reason="tracking branch lookup failed"
        return
    fi
    candidate=$(printf '%s\n' "$output" | awk -v ref="$_git_ref" '$2 == ref { print $1; exit }')
    if [[ ! "$candidate" =~ ^[0-9a-f]{40,64}$ ]]; then
        status=blocked reason="tracking branch has no exact commit"
    elif [[ "$current" == "$candidate" ]]; then
        status=installed reason=current
    elif ! git_fetch_candidate "$probe" "$origin" "$candidate"; then
        status=blocked reason="candidate commit fetch failed"
    elif ! base=$(git -C "$probe" merge-base HEAD "$candidate" 2>/dev/null); then
        status=blocked reason="could not establish branch ancestry"
    elif [[ "$base" == "$current" ]]; then
        status=update reason="clean fast-forward"
    elif [[ "$base" == "$candidate" ]]; then
        status=blocked reason="local branch is ahead of tracking branch"
    else
        status=blocked reason="local branch diverged from tracking branch"
    fi
}

_resolve_native_records() {
    local output helper="$_COMMON_SH_DIR/plan-neovim-packages.lua"
    if ! command -v nvim >/dev/null 2>&1; then
        _native_reason="resolve individual packages after Neovim installation"
        _native_status=check
        return
    fi
    if ! output=$(nvim --headless -u NONE -i NONE -n -l "$helper"); then
        _native_reason="Neovim package discovery failed"
        _native_status=blocked
        return
    fi
    if [[ -z "$output" ]] || ! printf '%s\n' "$output" | awk -F '\t' '
        NF != 9 { exit 1 }
        $1 !~ /^(neovim-plugin|treesitter-parsers|mason-packages)$/ { exit 1 }
        $3 !~ /^(planned|update|installed|blocked|check)$/ { exit 1 }
        ($3 == "planned" || $3 == "update") && ($8 == "" || $8 == "-") { exit 1 }
    '; then
        _native_reason="Neovim package discovery returned invalid records"
        _native_status=blocked
        return
    fi
    _native_output="$output"
}

_resolve_records() {
    local record source name status policy origin probe current candidate reason output
    local -a resolved=()
    local _native_output="" _native_reason="" _native_status="" _native_loaded=false native_record
    for record in "${_records[@]}"; do
        IFS=$'\t' read -r source name status policy origin probe <<<"$record"
        current=- candidate=- reason=-
        if [[ "${DOTFILES_PLAN_ASSUME_MISSING:-0}" != 1 ]]; then
            case "$source" in
                brew-formula|brew-cask)
                    if [[ "${_brew_inventory_failed:-0}" == 1 || "${_brew_outdated_failed:-0}" == 1 ]]; then
                        status=blocked reason="Homebrew inventory failed"
                    fi
                    ;;
                apt)
                    if output=$(LC_ALL=C apt-cache policy "$name" 2>/dev/null); then
                        current=$(printf '%s\n' "$output" | awk '/Installed:/ {print $2; exit}')
                        candidate=$(printf '%s\n' "$output" | awk '/Candidate:/ {print $2; exit}')
                        [[ "$current" != '(none)' ]] || current=-
                        [[ "$candidate" != '(none)' ]] || candidate=-
                        _resolve_compare
                        if [[ "$name" == nodejs ]]; then
                            if [[ ! "$candidate" =~ ^([0-9]+)\. ]] || (( BASH_REMATCH[1] < 24 )) \
                                || [[ "$candidate" != *nodesource* ]]; then
                                status=check candidate=-
                                reason="resolve Node.js 24 and bundled npm after NodeSource setup"
                            elif [[ "$status" == installed ]] && ! verify_node_runtime; then
                                status=check
                                reason="Node.js or bundled npm needs repair"
                            fi
                        fi
                        if [[ "$status" == update ]] && dpkg --compare-versions "$current" gt "$candidate"; then
                            status=installed
                            reason="installed version is newer than repository candidate"
                        fi
                        if [[ "$status" == blocked && ( "$name" == nodejs || "$name" == gh ) ]]; then
                            status=check
                            reason="resolve after repository setup"
                        fi
                    else
                        status=blocked reason="APT inventory failed"
                    fi
                    ;;
                npm) _resolve_npm ;;
                github-release) _resolve_release ;;
                pip) _resolve_python ;;
                luarocks) _resolve_luarocks ;;
                uv-tool)
                    current=$(_resolve_version "$probe") || current=-
                    candidate="${policy#pinned:}"
                    _resolve_compare
                    ;;
                git-external|git-runtime) _resolve_git ;;
                neovim-plugin|treesitter-parsers|mason-packages)
                    if [[ "$_native_loaded" == false ]]; then
                        _resolve_native_records
                        _native_loaded=true
                        if [[ -n "$_native_output" ]]; then
                            while IFS= read -r native_record; do resolved+=("$native_record"); done <<<"$_native_output"
                        fi
                    fi
                    [[ -z "$_native_output" ]] || continue
                    status="$_native_status" reason="$_native_reason"
                    ;;
            esac
        fi
        resolved+=("$source"$'\t'"$name"$'\t'"$status"$'\t'"$policy"$'\t'"$origin"$'\t'"$probe"$'\t'"${current:--}"$'\t'"${candidate:--}"$'\t'"$reason")
    done
    _records=("${resolved[@]}")
}
