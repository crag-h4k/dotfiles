#!/usr/bin/env bash
# Render the chezmoi templates that are gated by component and assert each
# combination produces the correct output. Catches malformed Go template
# syntax, broken TOML, and - for .chezmoi.toml.tmpl - any drift in the
# selection parser, which a single `chezmoi apply` would not exercise.
#
# Runs in pre-commit. Requires chezmoi (rendering) and python3 with tomllib
# (3.11+, for TOML parsing). If tomllib is missing, the render and the boolean
# assertions still run; only the structural TOML parse is skipped.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL="$REPO_DIR/.chezmoiexternal.toml"
CONFIG_TMPL="$REPO_DIR/.chezmoi.toml.tmpl"

command -v chezmoi >/dev/null 2>&1 || { echo "validate-templates: chezmoi not found" >&2; exit 1; }

have_tomllib=0
if python3 -c 'import tomllib' 2>/dev/null; then
    have_tomllib=1
fi

fail=0

parse_toml() {
    # Read TOML from stdin; return non-zero on parse error.
    if (( have_tomllib )); then
        python3 -c 'import sys,tomllib; tomllib.loads(sys.stdin.read())'
    else
        cat >/dev/null
    fi
}

# Render .chezmoi.toml.tmpl with componentSelection pre-seeded, then echo the
# four [data.components] booleans as "zsh tmux neovim gitconfig". Pre-seeding
# makes promptStringOnce return the value instead of prompting, so the parser
# is exercised deterministically. --init makes promptStringOnce available.
render_components() {
    local selection="$1" cfgdir out
    cfgdir=$(mktemp -d)
    printf '[data]\n    componentSelection = "%s"\n' "$selection" >"$cfgdir/chezmoi.toml"
    if ! out=$(chezmoi execute-template --init --config "$cfgdir/chezmoi.toml" <"$CONFIG_TMPL" 2>&1); then
        rm -rf "$cfgdir"
        printf 'RENDER_ERROR %s' "$out"
        return 1
    fi
    rm -rf "$cfgdir"
    if (( have_tomllib )); then
        if ! printf '%s' "$out" | parse_toml 2>/dev/null; then
            printf 'TOML_ERROR'
            return 1
        fi
    fi
    # Pull the booleans out of the rendered [data.components] block. Order is
    # fixed by the template, but key off the name so reordering the list later
    # does not silently break the assertions.
    local zsh tmux neovim gitconfig ai
    zsh=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*zsh = \(.*\)$/\1/p')
    tmux=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*tmux = \(.*\)$/\1/p')
    neovim=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*neovim = \(.*\)$/\1/p')
    gitconfig=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*gitconfig = \(.*\)$/\1/p')
    ai=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*ai = \(.*\)$/\1/p')
    printf '%s %s %s %s %s' "$zsh" "$tmux" "$neovim" "$gitconfig" "$ai"
}

# bool "1" if digit d (1..4) is present in the no-space numeric string, else "0"
has_digit() {
    case "$2" in
        *"$1"*) printf 'true' ;;
        *)      printf 'false' ;;
    esac
}

# Assert a selection string renders the expected booleans.
# Args: selection expected_zsh expected_tmux expected_neovim expected_gitconfig expected_ai
assert_case() {
    local selection="$1" want="$2 $3 $4 $5 $6" got
    got=$(render_components "$selection") || {
        echo "validate-templates: FAILED to render/parse (sel='$selection'): $got" >&2
        fail=1
        return
    }
    if [[ "$got" != "$want" ]]; then
        echo "validate-templates: MISMATCH (sel='$selection')" >&2
        echo "  expected (zsh tmux neovim gitconfig ai): $want" >&2
        echo "  got     (zsh tmux neovim gitconfig ai): $got" >&2
        fail=1
    fi
}

# --- .chezmoi.toml.tmpl: exhaustive numeric matrix -------------------------
# All 32 on/off combinations of digits 1..5, expressed with NO spaces (e.g.
# "135"). Expected booleans are derived from digit presence: number N present
# => component N on. This is the ground truth the parser must match.
ncases=0
for d1 in 0 1; do for d2 in 0 1; do for d3 in 0 1; do for d4 in 0 1; do for d5 in 0 1; do
    sel=""
    (( d1 )) && sel+="1"
    (( d2 )) && sel+="2"
    (( d3 )) && sel+="3"
    (( d4 )) && sel+="4"
    (( d5 )) && sel+="5"
    # Empty numeric string (no digits) would fall back to the default, which is
    # a different case; exercise it separately below. Skip it here.
    [[ -z "$sel" ]] && continue
    assert_case "$sel" \
        "$(has_digit 1 "$sel")" "$(has_digit 2 "$sel")" \
        "$(has_digit 3 "$sel")" "$(has_digit 4 "$sel")" \
        "$(has_digit 5 "$sel")"
    ncases=$((ncases + 1))
done; done; done; done; done

# --- keyword forms ---------------------------------------------------------
# all  = default-on set (zsh tmux neovim); gitconfig + ai off.
assert_case "all"  true true true false false
# all+ = everything including gitconfig and ai.
assert_case "all+" true true true true true

# --- space / order independence -------------------------------------------
# Same selections expressed with spaces and reordered must match the no-space
# forms above. "3 1" == zsh+neovim; "421" == zsh+tmux+gitconfig (digits 4,2,1,
# not 3); "1,3" proves comma separators are ignored too. "3 5" proves the ai
# component (digit 5) parses alongside neovim.
assert_case "3 1"   true  false true  false false
assert_case "421"   true  true  false true  false
assert_case "1,3"   true  false true  false false
assert_case "1 2 3" true  true  true  false false
assert_case "3 5"   false false true  false true

# --- empty / echoed-prompt fallback to default (1 2 3) ---------------------
# Empty string falls back to the default-on set. A value that begins with the
# menu text (non-interactive init echoing the prompt) does too.
assert_case ""                       true true true false false
assert_case "Components to install:" true true true false false

# --- .chezmoiexternal.toml: render + parse under each component combo -------
# The externals file only branches on zsh and tmux, so vary those two and pin
# neovim/gitconfig. This is a render/parse check (no per-line assertion); the
# point is that the gated TOML stays valid whether a block is present or not.
ext_combos=(
    "all-on    true  true"
    "all-off   false false"
    "zsh-only  true  false"
    "tmux-only false true"
)
for combo in "${ext_combos[@]}"; do
    read -r label zsh tmux <<<"$combo"
    cfgdir=$(mktemp -d)
    printf '[data.components]\n    zsh = %s\n    tmux = %s\n    neovim = true\n    gitconfig = false\n' \
        "$zsh" "$tmux" >"$cfgdir/chezmoi.toml"
    if ! out=$(chezmoi execute-template --config "$cfgdir/chezmoi.toml" <"$EXTERNAL" 2>&1); then
        echo "validate-templates: render FAILED for externals ($label):" >&2
        echo "$out" >&2
        fail=1
    elif ! printf '%s' "$out" | parse_toml; then
        echo "validate-templates: rendered externals ($label) is not valid TOML" >&2
        fail=1
    fi
    rm -rf "$cfgdir"
done

if (( fail )); then
    exit 1
fi

if (( have_tomllib )); then
    echo "validate-templates: OK - ${ncases} numeric + keyword/space/default cases assert correct booleans, externals parse"
else
    echo "validate-templates: OK - ${ncases} numeric + keyword/space/default cases assert correct booleans (TOML parse skipped, no tomllib)"
fi
