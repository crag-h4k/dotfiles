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

# Force the typed-menu path in .chezmoi.toml.tmpl so the parser is exercised
# deterministically. Without this, a render on a machine that has fzf and a
# controlling terminal would launch the interactive picker for every case.
export DOTFILES_NO_TUI=1

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

# Render .chezmoi.toml.tmpl with componentSelection (and optionally gitSelection
# / aiSelection) pre-seeded, then echo the nine component booleans in the fixed
# column order:
#   zsh tmux neovim  git.config git.personal git.ignore_global  ai.codecompanion ai.claude_hooks ai.statusline
# zsh/tmux/neovim are bare [data.components] bools; the rest live in the nested
# [data.components.git] / [data.components.ai] tables. Pre-seeding makes
# promptStringOnce return the value instead of prompting, so the parser is
# exercised deterministically. --init makes promptStringOnce available.
render_components() {
    local selection="$1" gitsel="${2:-}" aisel="${3:-}" cfgdir out
    cfgdir=$(mktemp -d)
    {
        printf '[data]\n    componentSelection = "%s"\n' "$selection"
        [[ -n "$gitsel" ]] && printf '    gitSelection = "%s"\n' "$gitsel"
        [[ -n "$aisel"  ]] && printf '    aiSelection = "%s"\n'  "$aisel"
    } >"$cfgdir/chezmoi.toml"
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
    # Pull the booleans out by key name (each is unique across the rendered
    # config), so reordering the lists later does not silently break assertions.
    local zsh tmux neovim gconfig gpersonal gignore aicc aihooks aistatus
    zsh=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*zsh = \(.*\)$/\1/p')
    tmux=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*tmux = \(.*\)$/\1/p')
    neovim=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*neovim = \(.*\)$/\1/p')
    gconfig=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*config = \(.*\)$/\1/p')
    gpersonal=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*personal = \(.*\)$/\1/p')
    gignore=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*ignore_global = \(.*\)$/\1/p')
    aicc=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*codecompanion = \(.*\)$/\1/p')
    aihooks=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*claude_hooks = \(.*\)$/\1/p')
    aistatus=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*statusline = \(.*\)$/\1/p')
    printf '%s %s %s %s %s %s %s %s %s' \
        "$zsh" "$tmux" "$neovim" "$gconfig" "$gpersonal" "$gignore" "$aicc" "$aihooks" "$aistatus"
}

# bool "true" if digit d (1..5) is present in the numeric string, else "false".
has_digit() {
    case "$2" in
        *"$1"*) printf 'true' ;;
        *)      printf 'false' ;;
    esac
}

COLS="zsh tmux neovim git.config git.personal git.ignore_global ai.codecompanion ai.claude_hooks ai.statusline"

# Assert a selection WITHOUT a sub-seed renders the expected top-level state.
# The git/ai PARENTS map to their default sub-feature (git.ignore_global /
# ai.codecompanion); the opt-in sub-features (config, personal, claude_hooks,
# statusline) stay off unless explicitly selected.
# Args: selection ezsh etmux eneovim egit eai
assert_top() {
    local selection="$1" want="$2 $3 $4 false false $5 $6 false false" got
    got=$(render_components "$selection") || {
        echo "validate-templates: FAILED to render/parse (sel='$selection'): $got" >&2
        fail=1
        return
    }
    if [[ "$got" != "$want" ]]; then
        echo "validate-templates: MISMATCH (sel='$selection')" >&2
        echo "  cols:     $COLS" >&2
        echo "  expected: $want" >&2
        echo "  got:      $got" >&2
        fail=1
    fi
}

# Assert a selection WITH explicit sub-selections renders the expected nine
# booleans. Args: selection gitSel aiSel  e1..e9 (in COLS order)
assert_sub() {
    local selection="$1" gitsel="$2" aisel="$3"
    shift 3
    local want="$1 $2 $3 $4 $5 $6 $7 $8 $9" got
    got=$(render_components "$selection" "$gitsel" "$aisel") || {
        echo "validate-templates: FAILED to render/parse (sel='$selection' git='$gitsel' ai='$aisel'): $got" >&2
        fail=1
        return
    }
    if [[ "$got" != "$want" ]]; then
        echo "validate-templates: MISMATCH (sel='$selection' git='$gitsel' ai='$aisel')" >&2
        echo "  cols:     $COLS" >&2
        echo "  expected: $want" >&2
        echo "  got:      $got" >&2
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
    # No sub-seed: parent on (digit 4 / 5) maps to its default sub-feature.
    assert_top "$sel" \
        "$(has_digit 1 "$sel")" "$(has_digit 2 "$sel")" \
        "$(has_digit 3 "$sel")" "$(has_digit 4 "$sel")" \
        "$(has_digit 5 "$sel")"
    ncases=$((ncases + 1))
done; done; done; done; done

# --- keyword forms ---------------------------------------------------------
# all  = default-on set (zsh tmux neovim git); ai off. git defaults to its
#        ignore_global sub-feature only.
assert_top "all"  true true true true false
# all+ = everything: both parents on, each at its default sub-feature.
assert_top "all+" true true true true true

# --- space / order independence -------------------------------------------
# Same selections expressed with spaces and reordered must match the no-space
# forms above. "3 1" == zsh+neovim; "421" == zsh+tmux+git (digits 4,2,1, not 3);
# "1,3" proves comma separators are ignored too. "3 5" proves the ai parent
# (digit 5) parses alongside neovim.
assert_top "3 1"   true  false true  false false
assert_top "421"   true  true  false true  false
assert_top "1,3"   true  false true  false false
assert_top "1 2 3" true  true  true  false false
assert_top "3 5"   false false true  false true

# --- empty / echoed-prompt fallback to default (1 2 3 4) -------------------
# Empty string falls back to the default-on set (now includes git). A value that
# begins with the menu text (non-interactive init echoing the prompt) does too.
assert_top ""                       true true true true false
assert_top "Components to install:" true true true true false

# --- nested submenu sub-selections -----------------------------------------
# git parent on (4) with explicit sub-selection, by key and by number; overrides
# the ignore_global default. ai parent on (5) likewise. Columns are
# (zsh tmux neovim  git.config git.personal git.ignore_global  ai.cc ai.hooks ai.statusline).
assert_sub "4"   "config personal" "" false false false  true  true  false  false false false
assert_sub "4"   "1 3"             "" false false false  true  false true   false false false
assert_sub "3 5" "" "codecompanion claude_hooks"  false false true  false false false  true  true  false
assert_sub "3 5" "" "statusline"                  false false true  false false false  false false true
assert_sub "4 5" "config" "claude_hooks"          false false false  true  false false  false true  false

# --- .chezmoiexternal.toml: render + parse under each component combo -------
# The externals file only branches on zsh and tmux, so vary those two and pin
# neovim. This is a render/parse check (no per-line assertion); the point is
# that the gated TOML stays valid whether a block is present or not.
ext_combos=(
    "all-on    true  true"
    "all-off   false false"
    "zsh-only  true  false"
    "tmux-only false true"
)
for combo in "${ext_combos[@]}"; do
    read -r label zsh tmux <<<"$combo"
    cfgdir=$(mktemp -d)
    printf '[data.components]\n    zsh = %s\n    tmux = %s\n    neovim = true\n' \
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
    echo "validate-templates: OK - ${ncases} numeric + keyword/space/default/submenu cases assert correct booleans, externals parse"
else
    echo "validate-templates: OK - ${ncases} numeric + keyword/space/default/submenu cases assert correct booleans (TOML parse skipped, no tomllib)"
fi
