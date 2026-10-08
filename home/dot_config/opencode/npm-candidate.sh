# shellcheck shell=bash
# home/dot_config/opencode/npm-candidate.sh
# Shared candidate selection for package plans and the installed plugin runtime.

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
    # Unlike `view`, `outdated` honors release-age and before filters.
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
    if (typeof version !== "string" || !/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(version)) process.exit(1)
    console.log(version)
  } catch { process.exit(1) }
})' "$name"
}
