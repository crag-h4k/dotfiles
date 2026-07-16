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
# deterministically. Without this, a render on a machine that has gum and a
# controlling terminal would launch the interactive picker for every case.
export DOTFILES_NO_TUI=1

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL="$REPO_DIR/.chezmoiexternal.toml"
CONFIG_TMPL="$REPO_DIR/.chezmoi.toml.tmpl"
RUNONCE="$REPO_DIR/run_once_after_00-install.sh.tmpl"

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
# / aiSelection / terminalSelection) pre-seeded, then echo the component booleans
# in the fixed column order:
#   zsh tmux neovim  git.config git.personal git.ignore_global  ai.codecompanion ai.claude_hooks ai.codex_hooks ai.statusline  terminal.ghostty terminal.iterm2
# zsh/tmux/neovim are bare [data.components] bools; the rest live in the nested
# [data.components.git] / [data.components.ai] / [data.components.terminal] tables.
# terminal.ghostty/terminal.iterm2 are emitted for BOTH OSes (the .chezmoi.os gate
# lives in the file layer, not the data keys), so these assertions are
# OS-independent and match on macOS pre-commit and Linux CI alike. Pre-seeding
# makes promptStringOnce return the value instead of prompting, so the parser is
# exercised deterministically. --init makes promptStringOnce available.
render_components() {
    local selection="$1" gitsel="${2:-}" aisel="${3:-}" termsel="${4:-}" cfgdir out
    cfgdir=$(mktemp -d)
    {
        printf '[data]\n    componentSelection = "%s"\n' "$selection"
        [[ -n "$gitsel"  ]] && printf '    gitSelection = "%s"\n'      "$gitsel"
        [[ -n "$aisel"   ]] && printf '    aiSelection = "%s"\n'       "$aisel"
        [[ -n "$termsel" ]] && printf '    terminalSelection = "%s"\n' "$termsel"
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
    local zsh tmux neovim gconfig gpersonal gignore aicc aihooks aicodex aistatus ghostty iterm2
    zsh=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*zsh = \(.*\)$/\1/p')
    tmux=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*tmux = \(.*\)$/\1/p')
    neovim=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*neovim = \(.*\)$/\1/p')
    gconfig=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*config = \(.*\)$/\1/p')
    gpersonal=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*personal = \(.*\)$/\1/p')
    gignore=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*ignore_global = \(.*\)$/\1/p')
    aicc=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*codecompanion = \(.*\)$/\1/p')
    aihooks=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*claude_hooks = \(.*\)$/\1/p')
    aicodex=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*codex_hooks = \(.*\)$/\1/p')
    aistatus=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*statusline = \(.*\)$/\1/p')
    ghostty=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*ghostty = \(.*\)$/\1/p')
    iterm2=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*iterm2 = \(.*\)$/\1/p')
    printf '%s %s %s %s %s %s %s %s %s %s %s %s' \
        "$zsh" "$tmux" "$neovim" "$gconfig" "$gpersonal" "$gignore" "$aicc" "$aihooks" "$aicodex" "$aistatus" "$ghostty" "$iterm2"
}

# bool "true" if digit d (1..5) is present in the numeric string, else "false".
has_digit() {
    case "$2" in
        *"$1"*) printf 'true' ;;
        *)      printf 'false' ;;
    esac
}

COLS="zsh tmux neovim git.config git.personal git.ignore_global ai.codecompanion ai.claude_hooks ai.codex_hooks ai.statusline terminal.ghostty terminal.iterm2"

# Assert a selection WITHOUT a sub-seed renders the expected top-level state.
# The git/ai/terminal PARENTS map to their default sub-feature (git.ignore_global /
# ai.codecompanion / terminal.ghostty); the opt-in sub-features (config, personal,
# claude_hooks, codex_hooks, statusline, iterm2) stay off unless explicitly selected.
# Args: selection ezsh etmux eneovim egit eai eghostty eiterm2
# (egit=git.ignore_global, eai=ai.codecompanion, eghostty=terminal.ghostty when the
# respective parent is on; eiterm2 stays off without an explicit sub-seed.)
assert_top() {
    local selection="$1" want="$2 $3 $4 false false $5 $6 false false false $7 $8" got
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

# Assert a selection WITH explicit sub-selections renders the expected booleans.
# Args: selection gitSel aiSel termSel  e1..e12 (in COLS order). Pass an empty
# seed ("") for any sub-menu you are not exercising.
assert_sub() {
    local selection="$1" gitsel="$2" aisel="$3" termsel="$4"
    shift 4
    local want="$1 $2 $3 $4 $5 $6 $7 $8 $9 ${10} ${11} ${12}" got
    got=$(render_components "$selection" "$gitsel" "$aisel" "$termsel") || {
        echo "validate-templates: FAILED to render/parse (sel='$selection' git='$gitsel' ai='$aisel' term='$termsel'): $got" >&2
        fail=1
        return
    }
    if [[ "$got" != "$want" ]]; then
        echo "validate-templates: MISMATCH (sel='$selection' git='$gitsel' ai='$aisel' term='$termsel')" >&2
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
    # terminal (digit 6) is not part of this matrix, so both its sub-features
    # (ghostty, iterm2) are off here; the terminal on-path is covered below.
    assert_top "$sel" \
        "$(has_digit 1 "$sel")" "$(has_digit 2 "$sel")" \
        "$(has_digit 3 "$sel")" "$(has_digit 4 "$sel")" \
        "$(has_digit 5 "$sel")" false false
    ncases=$((ncases + 1))
done; done; done; done; done

# --- keyword forms ---------------------------------------------------------
# all  = default-on set (zsh tmux neovim git); ai + terminal off. git defaults to
#        its ignore_global sub-feature only.
assert_top "all"  true true true true false false false
# all+ = everything: every parent on, each at its default sub-feature only
#        (git.ignore_global, ai.codecompanion, terminal.ghostty). iterm2 is NOT a
#        default sub-feature, so all+ leaves it off (select it explicitly to add it).
assert_top "all+" true true true true true true false

# --- space / order independence -------------------------------------------
# Same selections expressed with spaces and reordered must match the no-space
# forms above. "3 1" == zsh+neovim; "421" == zsh+tmux+git (digits 4,2,1, not 3);
# "1,3" proves comma separators are ignored too. "3 5" proves the ai parent
# (digit 5) parses alongside neovim.
assert_top "3 1"   true  false true  false false false false
assert_top "421"   true  true  false true  false false false
assert_top "1,3"   true  false true  false false false false
assert_top "1 2 3" true  true  true  false false false false
assert_top "3 5"   false false true  false true  false false

# --- empty / echoed-prompt fallback to default (1 2 3 4) -------------------
# Empty string falls back to the default-on set (now includes git). A value that
# begins with the menu text (non-interactive init echoing the prompt) does too.
assert_top ""                       true true true true false false false
assert_top "Components to install:" true true true true false false false

# --- terminal parent (opt-in, digit 6) -------------------------------------
# terminal is not in the default set (all=false), so it stays off for "all" and
# the default fallback. Selecting digit 6 turns the parent on at its ghostty
# sub-default (ghostty on, iterm2 off); iterm2 needs an explicit sub-seed (below).
assert_top "6"   false false false false false true  false
assert_top "1 6" true  false false false false true  false

# --- nested submenu sub-selections -----------------------------------------
# git parent on (4) with explicit sub-selection, by key and by number; overrides
# the ignore_global default. ai parent on (5) likewise; terminal parent on (6)
# below. The 4th assert_sub arg is the terminalSelection seed ("" = none). Columns
# are the full 12 in COLS order, ending terminal.ghostty terminal.iterm2.
assert_sub "4"   "config personal" "" "" false false false  true  true  false  false false false false  false false
assert_sub "4"   "1 3"             "" "" false false false  true  false true   false false false false  false false
assert_sub "3 5" "" "codecompanion claude_hooks" ""  false false true  false false false  true  true  false false  false false
assert_sub "3 5" "" "codecompanion codex_hooks"  ""  false false true  false false false  true  false true  false  false false
assert_sub "3 5" "" "statusline"                 ""  false false true  false false false  false false false true  false false
assert_sub "4 5" "config" "claude_hooks"         ""  false false false  true  false false  false true  false false  false false
# gum submenu output is stored as the leading key plus visible label text on
# older-compatible gum builds, so resolving by key containment must keep working.
assert_sub "4 5" "config - ~/.gitconfig" "codecompanion - CodeCompanion.nvim assistant (needs neovim)" "" \
    false false false  true false false  true false false false  false false

# terminal parent on (6) with explicit sub-selection, by key and by number.
# ghostty is the default; iterm2 is added only when explicitly selected. iterm2's
# data key is emitted on every OS (the .chezmoi.os gate lives in the file layer,
# not the data keys), so these assert identically on macOS pre-commit and Linux CI.
assert_sub "6"   "" "" "ghostty iterm2"  false false false  false false false  false false false false  true  true
assert_sub "6"   "" "" "iterm2"          false false false  false false false  false false false false  false true
assert_sub "6"   "" "" "1 2"             false false false  false false false  false false false false  true  true
assert_sub "6"   "" "" "2"               false false false  false false false  false false false false  false true
assert_sub "1 6" "" "" "ghostty"         true  false false  false false false  false false false false  true  false

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

# --- run_once_after_00-install.sh.tmpl: install-var flags render correctly --
# The terminal binary installs are gated by INSTALL_TERMINAL_* env vars dug from
# the terminal.* data keys. Prove INSTALL_TERMINAL_GHOSTTY renders true when the
# ghostty sub-feature is on and false when off (its data-key resolution is
# already asserted in the matrix above; this checks the run_once wiring on top).
assert_install_ghostty() {
    local ghostty="$1" want="$2" cfgdir out got
    cfgdir=$(mktemp -d)
    printf '[data.components.terminal]\n    ghostty = %s\n    iterm2 = false\n' "$ghostty" >"$cfgdir/chezmoi.toml"
    if ! out=$(chezmoi execute-template --config "$cfgdir/chezmoi.toml" <"$RUNONCE" 2>&1); then
        echo "validate-templates: run_once render FAILED (ghostty=$ghostty): $out" >&2
        fail=1
        rm -rf "$cfgdir"
        return
    fi
    rm -rf "$cfgdir"
    got=$(printf '%s\n' "$out" | sed -n 's/^export INSTALL_TERMINAL_GHOSTTY=\(.*\)$/\1/p')
    if [[ "$got" != "$want" ]]; then
        echo "validate-templates: run_once INSTALL_TERMINAL_GHOSTTY mismatch (ghostty=$ghostty): expected=$want got=$got" >&2
        fail=1
    fi
}
assert_install_ghostty true  true
assert_install_ghostty false false

# --- modify_ templates: gated JSON/TOML merge scripts ----------------------
# Render each modify_*.tmpl under an ai sub-feature config, run the emitted merge
# script against a representative target file, and assert the result parses. The
# required positive case is statusline ON with the notify hooks OFF; we also
# exercise both-on and the Codex bare-[tui] fold (double-table hazard). Codex TOML
# checks need tomllib; they are skipped (not failed) when it is absent.
CLAUDE_MOD="$REPO_DIR/dot_claude/modify_settings.json.tmpl"
CODEX_MOD="$REPO_DIR/dot_codex/modify_private_config.toml.tmpl"

ai_cfg() { # claude_hooks codex_hooks statusline -> path to a temp chezmoi config
    local d; d=$(mktemp -d)
    printf '[data.components.ai]\n    claude_hooks = %s\n    codex_hooks = %s\n    statusline = %s\n' \
        "$1" "$2" "$3" >"$d/chezmoi.toml"
    printf '%s' "$d/chezmoi.toml"
}

run_modify() { # tmpl cfg sample-file -> merged output on stdout, nonzero on error
    local tmpl="$1" cfg="$2" sample="$3" pyf out
    pyf=$(mktemp)
    if ! chezmoi execute-template --config "$cfg" <"$tmpl" >"$pyf" 2>/dev/null; then
        rm -f "$pyf"; return 1
    fi
    out=$(python3 "$pyf" <"$sample" 2>/dev/null) || { rm -f "$pyf"; return 1; }
    rm -f "$pyf"
    printf '%s' "$out"
}

CLA_SAMPLE=$(mktemp); printf '{"model":"opus","env":{"FOO":"bar"}}' >"$CLA_SAMPLE"
# Codex targets: one with NO bare [tui], one WITH a bare [tui] (fold-in path).
CODEX_PLAIN=$(mktemp); printf 'model = "x"\n\n[projects."/p"]\ntrust_level = "trusted"\n' >"$CODEX_PLAIN"
CODEX_BARE_TUI=$(mktemp); printf 'model = "x"\n\n[tui]\nfoo = 1\n\n[projects."/p"]\ntrust_level = "trusted"\n' >"$CODEX_BARE_TUI"

# Claude: statusLine present iff the statusline gate is on; output must be JSON.
assert_modify_claude() { # cfg wantStatusLine(true|false)
    local cfg="$1" want="$2" out has
    if ! out=$(run_modify "$CLAUDE_MOD" "$cfg" "$CLA_SAMPLE"); then
        echo "validate-templates: claude modify_ render/run FAILED (want statusLine=$want)" >&2; fail=1; return
    fi
    if ! printf '%s' "$out" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
        echo "validate-templates: claude modify_ output is not valid JSON" >&2; fail=1; return
    fi
    has=$(printf '%s' "$out" | python3 -c 'import sys,json;print(str("statusLine" in json.load(sys.stdin)).lower())')
    if [[ "$has" != "$want" ]]; then
        echo "validate-templates: claude modify_ statusLine=$has want=$want" >&2; fail=1
    fi
}

# Codex: output must be valid TOML (no second [tui]); status_line present iff the
# statusline gate is on, notify present iff codex_hooks.
assert_modify_codex() { # cfg sample wantStatusLine wantNotify
    local cfg="$1" sample="$2" wsl="$3" wn="$4" out
    if ! out=$(run_modify "$CODEX_MOD" "$cfg" "$sample"); then
        echo "validate-templates: codex modify_ render/run FAILED" >&2; fail=1; return
    fi
    (( have_tomllib )) || return
    if ! printf '%s' "$out" | parse_toml 2>/dev/null; then
        echo "validate-templates: codex modify_ output is not valid TOML" >&2; fail=1
        printf '%s\n' "$out" >&2; return
    fi
    local got
    got=$(printf '%s' "$out" | python3 -c 'import sys,tomllib
t=tomllib.loads(sys.stdin.read())
print(str("status_line" in t.get("tui",{})).lower(), str("notify" in t).lower())')
    if [[ "$got" != "$wsl $wn" ]]; then
        echo "validate-templates: codex modify_ (status_line notify)='$got' want='$wsl $wn'" >&2; fail=1
    fi
}

# Required positive case: statusline ON, hooks OFF.
assert_modify_claude "$(ai_cfg false false true)" true
assert_modify_codex  "$(ai_cfg false false true)" "$CODEX_PLAIN"    true false
assert_modify_codex  "$(ai_cfg false false true)" "$CODEX_BARE_TUI" true false
# Both on: injections coexist and still parse.
assert_modify_claude "$(ai_cfg true false true)" true
assert_modify_codex  "$(ai_cfg true true true)" "$CODEX_BARE_TUI" true true
# Hooks on, statusline off: no statusLine / status_line, notify hooks intact.
assert_modify_claude "$(ai_cfg true false false)" false
assert_modify_codex  "$(ai_cfg false true false)" "$CODEX_PLAIN" false true

if (( fail )); then
    exit 1
fi

if (( have_tomllib )); then
    echo "validate-templates: OK - ${ncases} numeric + keyword/space/default/submenu cases assert correct booleans, externals parse, run_once install vars render"
else
    echo "validate-templates: OK - ${ncases} numeric + keyword/space/default/submenu cases assert correct booleans, run_once install vars render (TOML parse skipped, no tomllib)"
fi
