#!/usr/bin/env bash
# scripts/validate-templates.sh
# Render the chezmoi templates that are gated by component and assert each
# combination produces the correct output. Catches malformed Go template
# syntax, broken TOML, and - for home/.chezmoi.toml.tmpl - any drift in the
# selection parser, which a single `chezmoi apply` would not exercise.
#
# Runs in pre-commit. Requires chezmoi (rendering) and python3 with tomllib
# (3.11+, for TOML parsing). If tomllib is missing, the render and the boolean
# assertions still run; only the structural TOML parse is skipped.

set -euo pipefail

# Force the typed-menu path in home/.chezmoi.toml.tmpl so the parser is exercised
# deterministically. Without this, a render on a machine that has gum and a
# controlling terminal would launch the interactive picker for every case.
export DOTFILES_NO_TUI=1
export DOTFILES_INSTALL_MODE=configs

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_SKILLS_VALIDATOR="$REPO_DIR/scripts/validate-agent-skills.py"
SOURCE_DIR="$REPO_DIR/home"
EXTERNAL="$SOURCE_DIR/.chezmoiexternal.toml"
IGNORE="$SOURCE_DIR/.chezmoiignore"
CONFIG_TMPL="$SOURCE_DIR/.chezmoi.toml.tmpl"
RUNONCE="$SOURCE_DIR/.chezmoiscripts/run_once_after_00-install.sh.tmpl"
NOTIFY_TMPL="$SOURCE_DIR/dot_config/notify/notify.yaml.tmpl"
NOTIFY_SOUNDS="$SOURCE_DIR/dot_config/notify/sounds"

command -v chezmoi >/dev/null 2>&1 || { echo "validate-templates: chezmoi not found" >&2; exit 1; }

have_tomllib=0
if python3 -c 'import tomllib' 2>/dev/null; then
    have_tomllib=1
fi

# mikefarah/yq, used to assert the rendered notify config. The notify component
# already depends on it at runtime, so this is not a new tool; skip the structural
# assertions rather than fail if a machine lacks it.
have_yq=0
if command -v yq >/dev/null 2>&1 && printf 'a: 1\n' | yq -e '.a' >/dev/null 2>&1; then
    have_yq=1
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

# Render home/.chezmoi.toml.tmpl with componentSelection (and optionally gitSelection
# / aiSelection / terminalSelection) pre-seeded, then echo the component booleans
# in the fixed column order:
#   zsh tmux neovim  git.config git.ignore_global  ai.codecompanion ai.claude_hooks ai.codex_hooks ai.statusline ai.opencode ai.copilot  terminal.ghostty terminal.iterm2
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
    if ! out=$(chezmoi execute-template --init --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$CONFIG_TMPL" 2>&1); then
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
    local zsh tmux neovim gconfig gignore aicc aihooks aicodex aistatus aiopencode aicopilot ghostty iterm2
    zsh=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*zsh = \(.*\)$/\1/p')
    tmux=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*tmux = \(.*\)$/\1/p')
    neovim=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*neovim = \(.*\)$/\1/p')
    gconfig=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*config = \(.*\)$/\1/p')
    gignore=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*ignore_global = \(.*\)$/\1/p')
    aicc=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*codecompanion = \(.*\)$/\1/p')
    aihooks=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*claude_hooks = \(.*\)$/\1/p')
    aicodex=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*codex_hooks = \(.*\)$/\1/p')
    aistatus=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*statusline = \(.*\)$/\1/p')
    aiopencode=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*opencode = \(.*\)$/\1/p')
    aicopilot=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*copilot = \(.*\)$/\1/p')
    ghostty=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*ghostty = \(.*\)$/\1/p')
    iterm2=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*iterm2 = \(.*\)$/\1/p')
    printf '%s %s %s %s %s %s %s %s %s %s %s %s %s' \
        "$zsh" "$tmux" "$neovim" "$gconfig" "$gignore" "$aicc" "$aihooks" "$aicodex" "$aistatus" "$aiopencode" "$aicopilot" "$ghostty" "$iterm2"
}

# bool "true" if digit d (1..5) is present in the numeric string, else "false".
has_digit() {
    case "$2" in
        *"$1"*) printf 'true' ;;
        *)      printf 'false' ;;
    esac
}

COLS="zsh tmux neovim git.config git.ignore_global ai.codecompanion ai.claude_hooks ai.codex_hooks ai.statusline ai.opencode ai.copilot terminal.ghostty terminal.iterm2"

# Assert a selection WITHOUT a sub-seed renders the expected top-level state.
# The git/ai/terminal PARENTS map to their default sub-feature (git.ignore_global /
# ai.opencode / terminal.ghostty); the opt-in sub-features (config,
# claude_hooks, codex_hooks, statusline, iterm2) stay off unless explicitly selected.
# Args: selection ezsh etmux eneovim egit eai eghostty eiterm2
# (egit=git.ignore_global, eai=ai.opencode, eghostty=terminal.ghostty when the
# respective parent is on; eiterm2 stays off without an explicit sub-seed.)
assert_top() {
    local selection="$1" want="$2 $3 $4 false $5 false false false false $6 false $7 $8" got
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
# Args: selection gitSel aiSel termSel  e1..e13 (in COLS order). Pass an empty
# seed ("") for any sub-menu you are not exercising.
assert_sub() {
    local selection="$1" gitsel="$2" aisel="$3" termsel="$4"
    shift 4
    local want="$1 $2 $3 $4 $5 $6 $7 $8 $9 ${10} ${11} ${12} ${13}" got
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

# --- home/.chezmoi.toml.tmpl: exhaustive numeric matrix --------------------
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
# default = default-on set (zsh tmux neovim git); AI + terminal off. Git defaults
#           to its independent global-ignore sub-feature only.
assert_top "default" true true true true false false false
# `all` is retained only to migrate an old persisted selection to `default`.
assert_top "all"  true true true true false false false

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
# terminal is not in the default set, so it stays off for `default` and
# the default fallback. Selecting digit 6 turns the parent on at its ghostty
# sub-default (ghostty on, iterm2 off); iterm2 needs an explicit sub-seed (below).
assert_top "6"   false false false false false true  false
assert_top "1 6" true  false false false false true  false

# --- nested submenu sub-selections -----------------------------------------
# git parent on (4) with explicit sub-selection, by key and by number; overrides
# the ignore_global default. ai parent on (5) likewise; terminal parent on (6)
# below. The 4th assert_sub arg is the terminalSelection seed ("" = none). Columns
# are the full 13 in COLS order: the ai group is codecompanion claude_hooks
# codex_hooks statusline opencode copilot, ending terminal.ghostty terminal.iterm2.
assert_sub "4"   "config" "" "" false false false  true  false  false false false false false false  false false
assert_sub "4"   "1 3"    "" "" false false false  true  true   false false false false false false  false false
assert_sub "3 5" "" "codecompanion claude_hooks" ""  false false true  false false  true  true  false false false false  false false
assert_sub "3 5" "" "codecompanion codex_hooks"  ""  false false true  false false  true  false true  false false false  false false
assert_sub "3 5" "" "statusline"                 ""  false false true  false false  false false false true  false false  false false
# CodeCompanion forces Neovim on even when top-level component 3 was not selected.
assert_sub "5"   "" "codecompanion"               ""  false false true  false false  true  false false false false false  false false
# AI parent on (5) with its OpenCode V2 default.
assert_sub "5"   "" "opencode"                   ""  false false false  false false  false false false false true false  false false
# ai parent on (5) with the copilot sub-feature only: opt-in npm CLI binary like
# opencode, off by default; its dedicated on-path (codecompanion stays off).
assert_sub "5"   "" "copilot"                    ""  false false false  false false  false false false false false true  false false
assert_sub "4 5" "config" "claude_hooks"         ""  false false false  true  false  false true  false false false false  false false
# Gum submenu output is stored as the leading key plus visible label text on
# older-compatible gum builds, so resolving by key containment must keep working.
assert_sub "4 5" "config - ~/.gitconfig" "codecompanion - CodeCompanion.nvim assistant (needs neovim)" "" \
    false false true  true false  true false false false false false  false false

# terminal parent on (6) with explicit sub-selection, by key and by number.
# ghostty is the default; iterm2 is added only when explicitly selected. iterm2's
# data key is emitted on every OS (the .chezmoi.os gate lives in the file layer,
# not the data keys), so these assert identically on macOS pre-commit and Linux CI.
assert_sub "6"   "" "" "ghostty iterm2"  false false false  false false  false false false false false false  true  true
assert_sub "6"   "" "" "iterm2"          false false false  false false  false false false false false false  false true
assert_sub "6"   "" "" "1 2"             false false false  false false  false false false false false false  true  true
assert_sub "6"   "" "" "2"               false false false  false false  false false false false false false  false true
assert_sub "1 6" "" "" "ghostty"         true  false false  false false  false false false false false false  true  false

# --- AI submenu whole-token resolution and migration ------------------------
# Selecting one AI sub-feature enables exactly that one. The retired opencode2
# token migrates to the canonical OpenCode V2 key.
assert_ai_only() { # aiSelection expected_on_key
    local aisel="$1" want_key="$2" out cfgdir key val
    cfgdir=$(mktemp -d)
    printf '[data]\n    componentSelection = "5"\n    aiSelection = "%s"\n' "$aisel" >"$cfgdir/chezmoi.toml"
    if ! out=$(chezmoi execute-template --init --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$CONFIG_TMPL" 2>&1); then
        echo "validate-templates: ai-only render FAILED (ai='$aisel'): $out" >&2
        fail=1; rm -rf "$cfgdir"; return
    fi
    rm -rf "$cfgdir"
    for key in claude_hooks codex_hooks statusline opencode copilot codecompanion; do
        val=$(printf '%s\n' "$out" | sed -n "s/^[[:space:]]*${key} = \\(.*\\)\$/\\1/p")
        if [[ "$key" == "$want_key" ]]; then
            [[ "$val" == true ]] || { echo "validate-templates: ai '$aisel' expected $key=true, got '$val'" >&2; fail=1; }
        else
            [[ "$val" == false ]] || { echo "validate-templates: ai '$aisel' expected $key=false, got '$val' (substring false-match?)" >&2; fail=1; }
        fi
    done
}
assert_ai_only "opencode2"    "opencode"
assert_ai_only "opencode"     "opencode"
assert_ai_only "codex_hooks"  "codex_hooks"

# The old V2 token is rewritten in persisted data and never emitted as a child key.
cfgdir=$(mktemp -d)
printf '[data]\ncomponentSelection = "5"\naiSelection = "opencode2"\n' >"$cfgdir/chezmoi.toml"
out=$(chezmoi execute-template --init --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$CONFIG_TMPL")
rm -rf "$cfgdir"
printf '%s\n' "$out" | grep -q '^    aiSelection = "opencode"$' || {
    echo "validate-templates: old opencode2 selection was not persisted as opencode" >&2
    fail=1
}
if printf '%s\n' "$out" | grep -q '^[[:space:]]*opencode2 ='; then
    echo "validate-templates: retired opencode2 component key was emitted" >&2
    fail=1
fi

# A real old `all+` host carried resolved nested tables as well as raw submenu
# strings. The tables could be newer than those strings after a manual edit, so
# preserve their union while migrating all six current components. Do not replay
# the retired theme/package-mode action rows.
cfgdir=$(mktemp -d)
cat >"$cfgdir/chezmoi.toml" <<'EOF'
[data]
componentSelection = "all+"
gitSelection = "ignore_global"
aiSelection = "codecompanion"
terminalSelection = "ghostty"

[data.components]
zsh = true
tmux = true
neovim = true

[data.components.git]
config = true
personal = true
ignore_global = true

[data.components.ai]
claude_hooks = true
codex_hooks = true
statusline = false
opencode = false
copilot = false
codecompanion = true
opencode2 = true

[data.components.terminal]
ghostty = true
iterm2 = true
EOF
out=$(chezmoi execute-template --init --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$CONFIG_TMPL")
rm -rf "$cfgdir"
for expected in \
    'componentSelection = "1 2 3 4 5 6"' \
    'zsh = true' 'tmux = true' 'neovim = true' \
    'config = true' 'ignore_global = true' \
    'claude_hooks = true' 'codex_hooks = true' 'opencode = true' \
    'codecompanion = true' \
    'ghostty = true' 'iterm2 = true'; do
    printf '%s\n' "$out" | grep -Fq "$expected" || {
        echo "validate-templates: old all+ migration lost: $expected" >&2
        fail=1
    }
done

# Personal identity used to be independently selectable. Promote a personal-only
# old host to managed Git config, but stop persisting identity data.
cfgdir=$(mktemp -d)
cat >"$cfgdir/chezmoi.toml" <<'EOF'
[data]
componentSelection = "4"
gitSelection = "personal"
gitName = "Legacy Personal User"
gitEmail = "legacy-personal@example.invalid"

[data.components]
zsh = false
tmux = false
neovim = false

[data.components.git]
config = false
personal = true
ignore_global = false
EOF
out=$(chezmoi execute-template --init --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$CONFIG_TMPL")
rm -rf "$cfgdir"
for expected in \
    'gitSelection = "config"' \
    'config = true'; do
    printf '%s\n' "$out" | grep -Fq "$expected" || {
        echo "validate-templates: personal-only Git migration lost: $expected" >&2
        fail=1
    }
done
for removed in 'gitPersonalSelection' 'gitName' 'gitEmail' 'personal ='; do
    if printf '%s\n' "$out" | grep -Fq "$removed"; then
        echo "validate-templates: retired Git identity data was still emitted: $removed" >&2
        fail=1
    fi
done

# --- home/.chezmoiexternal.toml: render + parse under each component combo --
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
    if ! out=$(chezmoi execute-template --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$EXTERNAL" 2>&1); then
        echo "validate-templates: render FAILED for externals ($label):" >&2
        echo "$out" >&2
        fail=1
    elif ! printf '%s' "$out" | parse_toml; then
        echo "validate-templates: rendered externals ($label) is not valid TOML" >&2
        fail=1
    elif [[ "$label" == all-on ]]; then
        entries=$(printf '%s\n' "$out" | grep -c 'type = "git-repo"' || true)
        refreshes=$(printf '%s\n' "$out" | grep -c 'refreshPeriod = "0"' || true)
        fast_forwards=$(printf '%s\n' "$out" | grep -c 'args = \["--ff-only"\]' || true)
        if [[ "$entries" -ne "$refreshes" ]]; then
            echo "validate-templates: every git external must disable automatic refresh" >&2
            fail=1
        elif [[ "$entries" -ne "$fast_forwards" ]]; then
            echo "validate-templates: every git external must disable automatic refresh and declare --ff-only pull" >&2
            fail=1
        fi
    fi
    rm -rf "$cfgdir"
done

# --- notify gate: every consumer keeps config + runtime dependency together ---
assert_notify_gate() { # zsh tmux claude_hooks codex_hooks want_enabled
    local zsh="$1" tmux="$2" claude="$3" codex="$4" want="$5"
    local cfgdir ignored runout got
    cfgdir=$(mktemp -d)
    {
        printf '[data]\ninstallMode = "configs"\n'
        printf '[data.components]\nzsh = %s\ntmux = %s\n' "$zsh" "$tmux"
        printf '[data.components.ai]\nclaude_hooks = %s\ncodex_hooks = %s\nstatusline = false\ncodecompanion = false\n' "$claude" "$codex"
    } > "$cfgdir/chezmoi.toml"
    ignored=$(chezmoi execute-template --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" < "$IGNORE")
    runout=$(chezmoi execute-template --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" < "$RUNONCE")
    rm -rf "$cfgdir"
    got=$(printf '%s\n' "$runout" | sed -n 's/^export INSTALL_NOTIFY=\(.*\)$/\1/p')
    if [[ "$got" != "$want" ]]; then
        echo "validate-templates: INSTALL_NOTIFY=$got want=$want (zsh=$zsh tmux=$tmux claude=$claude codex=$codex)" >&2
        fail=1
    fi
    if [[ "$want" == true ]] && printf '%s\n' "$ignored" | grep -qx '.config/notify'; then
        echo "validate-templates: enabled notify was ignored" >&2
        fail=1
    elif [[ "$want" == false ]] && ! printf '%s\n' "$ignored" | grep -qx '.config/notify'; then
        echo "validate-templates: disabled notify was not ignored" >&2
        fail=1
    fi
}

assert_notify_gate false false false false false
assert_notify_gate true  false false false true
assert_notify_gate false true  false false true
assert_notify_gate false false true  false true
assert_notify_gate false false false true  true

# --- Git file gates + unmanaged private override ------------------------------
assert_git_gate() { # config ignore_global
    local config="$1" ignore_global="$2"
    local cfgdir ignored
    cfgdir=$(mktemp -d)
    {
        printf '[data]\n'
        printf '[data.components.git]\n'
        printf '    config = %s\n' "$config"
        printf '    ignore_global = %s\n' "$ignore_global"
    } >"$cfgdir/chezmoi.toml"
    ignored=$(chezmoi execute-template --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$IGNORE")

    if [[ "$config" == true ]] && printf '%s\n' "$ignored" | grep -qx '.gitconfig'; then
        echo "validate-templates: enabled git config was ignored" >&2
        fail=1
    elif [[ "$config" == false ]] && ! printf '%s\n' "$ignored" | grep -qx '.gitconfig'; then
        echo "validate-templates: disabled git config was not ignored" >&2
        fail=1
    fi
    for private_file in .gitconfig.override .gitconfig.personal .gitconfig.work; do
        if ! printf '%s\n' "$ignored" | grep -qx "$private_file"; then
            echo "validate-templates: private Git file was not unconditionally ignored: $private_file" >&2
            fail=1
        fi
    done
    if [[ "$ignore_global" == true ]] && printf '%s\n' "$ignored" | grep -qx '.gitignore_global'; then
        echo "validate-templates: enabled global git ignore was ignored" >&2
        fail=1
    elif [[ "$ignore_global" == false ]] && ! printf '%s\n' "$ignored" | grep -qx '.gitignore_global'; then
        echo "validate-templates: disabled global git ignore was not ignored" >&2
        fail=1
    fi
    rm -rf "$cfgdir"
}

assert_git_gate false false
assert_git_gate true  true

# --- home/.chezmoiscripts/run_once_after_00-install.sh.tmpl: install vars ---
# The terminal binary installs are gated by INSTALL_TERMINAL_* env vars dug from
# the terminal.* data keys. Prove INSTALL_TERMINAL_GHOSTTY renders true when the
# ghostty sub-feature is on and false when off (its data-key resolution is
# already asserted in the matrix above; this checks the run_once wiring on top).
assert_install_ghostty() {
    local ghostty="$1" want="$2" cfgdir out got
    cfgdir=$(mktemp -d)
    printf '[data.components.terminal]\n    ghostty = %s\n    iterm2 = false\n' "$ghostty" >"$cfgdir/chezmoi.toml"
    if ! out=$(chezmoi execute-template --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$RUNONCE" 2>&1); then
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

assert_package_run_render() {
    local cfgdir out got
    cfgdir=$(mktemp -d)
    printf '[data]\n    installMode = "packages"\n    packageRun = 17\n' >"$cfgdir/chezmoi.toml"
    out=$(chezmoi execute-template --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$RUNONCE")
    rm -rf "$cfgdir"
    got=$(printf '%s\n' "$out" | sed -n 's/^export DOTFILES_PACKAGE_RUN=\(.*\)$/\1/p')
    if [[ "$got" != 17 ]]; then
        echo "validate-templates: run_once DOTFILES_PACKAGE_RUN mismatch: expected=17 got=$got" >&2
        fail=1
    fi
}
assert_package_run_render

if grep -Fq 'git submodule update' "$RUNONCE"; then
    echo "validate-templates: palette submodule initialization must stay behind package approval" >&2
    fail=1
fi

# --- modify_ templates: gated JSON/TOML merge scripts ----------------------
# Render each modify_*.tmpl under an ai sub-feature config, run the emitted merge
# script against a representative target file, and assert the result parses. The
# required positive case is statusline ON with the notify hooks OFF; we also
# exercise both-on and the Codex bare-[tui] fold (double-table hazard). Codex TOML
# checks need tomllib; they are skipped (not failed) when it is absent.
CLAUDE_MOD="$SOURCE_DIR/dot_claude/modify_settings.json.tmpl"
CODEX_MOD="$SOURCE_DIR/dot_codex/modify_private_config.toml.tmpl"

ai_cfg() { # claude_hooks codex_hooks statusline -> path to a temp chezmoi config
    local d; d=$(mktemp -d)
    printf '[data.components.ai]\n    claude_hooks = %s\n    codex_hooks = %s\n    statusline = %s\n' \
        "$1" "$2" "$3" >"$d/chezmoi.toml"
    printf '%s' "$d/chezmoi.toml"
}

run_modify() { # tmpl cfg sample-file -> merged output on stdout, nonzero on error
    local tmpl="$1" cfg="$2" sample="$3" pyf out
    pyf=$(mktemp)
    if ! chezmoi execute-template --source "$REPO_DIR" --config "$cfg" <"$tmpl" >"$pyf" 2>/dev/null; then
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

# --- home/dot_config/notify/notify.yaml.tmpl -------------------------------
# Colors and sounds are indirect here: a group names a palette key and a sound
# file, and nothing else checks that either one exists. A typo, or a key present
# in one palette but not another, renders a config that parses fine and then
# notifies with the wrong color or in silence. Render per palette and assert
# every reference resolves.
assert_notify_yaml() { # palette
    local pal="$1" cfgdir out keys refs name bg accent sound
    cfgdir=$(mktemp -d)
    printf '[data]\n    palette = "%s"\n' "$pal" > "$cfgdir/chezmoi.toml"
    if ! out=$(chezmoi execute-template --source "$REPO_DIR" --config "$cfgdir/chezmoi.toml" <"$NOTIFY_TMPL" 2>&1); then
        echo "validate-templates: notify.yaml ($pal) failed to render" >&2
        printf '%s\n' "$out" >&2; fail=1; rm -rf "$cfgdir"; return
    fi
    rm -rf "$cfgdir"
    (( have_yq )) || return
    if ! printf '%s' "$out" | yq -e '.' >/dev/null 2>&1; then
        echo "validate-templates: notify.yaml ($pal) is not valid YAML" >&2; fail=1; return
    fi
    keys=" $(printf '%s' "$out" | yq -r '.palette | keys | .[]' | tr '\n' ' ')"
    refs=$(printf '%s' "$out" | yq -r \
        '[(.groups // {} | to_entries), (.integrations // {} | to_entries)] | flatten | .[]
         | .key + " " + (.value.bg // "") + " " + (.value.accent // "") + " " + (.value.sound // "")')
    while read -r name bg accent sound; do
        [ -n "$name" ] || continue
        for ref in "$bg" "$accent"; do
            [ -n "$ref" ] || continue
            case "$keys" in
                *" $ref "*) ;;
                *) echo "validate-templates: notify.yaml ($pal) group '$name' uses undefined palette key '$ref'" >&2; fail=1 ;;
            esac
        done
        if [ -n "$sound" ] && [ ! -f "$NOTIFY_SOUNDS/$sound" ]; then
            echo "validate-templates: notify.yaml ($pal) group '$name' names a missing sound '$sound'" >&2; fail=1
        fi
    done <<< "$refs"
}

# Two palettes, so a key that only one scheme defines is caught. The catalog is
# generated, but the template lists palette keys by hand.
assert_notify_yaml dracula
assert_notify_yaml catppuccin-frappe

# Agent skills have one compound gate across all seven AI sub-features. The
# dedicated offline validator renders every on-path, checks the matching ignore
# paths and externals, and verifies exact pins plus harness link layout.
if ! python3 "$AGENT_SKILLS_VALIDATOR"; then
    fail=1
fi

if (( fail )); then
    exit 1
fi

if (( have_tomllib )); then
    echo "validate-templates: OK - ${ncases} numeric + keyword/space/default/submenu cases assert correct booleans, externals parse, run_once install vars render"
else
    echo "validate-templates: OK - ${ncases} numeric + keyword/space/default/submenu cases assert correct booleans, run_once install vars render (TOML parse skipped, no tomllib)"
fi
