#!/usr/bin/env bash
# Render the chezmoi templates that are gated by component and confirm each
# combination produces valid output. Catches malformed Go template syntax and
# broken TOML in a branch that a single `chezmoi apply` would not exercise.
#
# Runs in pre-commit. Requires chezmoi (rendering) and python3 with tomllib
# (3.11+, for TOML parsing). If tomllib is missing, the render still runs and
# catches template errors; only the structural TOML check is skipped.

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

# Render .chezmoiexternal.toml under each component combination and parse it.
# Format: label zsh tmux
combos=(
    "all-on   true  true"
    "all-off  false false"
    "zsh-only true  false"
    "tmux-only false true"
)

for combo in "${combos[@]}"; do
    read -r label zsh tmux <<<"$combo"
    # chezmoi --config requires a recognized extension, so name the file chezmoi.toml.
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

# Render .chezmoi.toml.tmpl across selection strings and confirm each parses as
# TOML. --init makes promptStringOnce available; pre-seeding componentSelection
# in the config makes it return that value instead of prompting, so we exercise
# the menu-string parser deterministically.
for selection in "1 3" "all+" "2" "1 2 3 4"; do
    cfgdir=$(mktemp -d)
    printf '[data]\n    componentSelection = "%s"\n' "$selection" >"$cfgdir/chezmoi.toml"
    if ! out=$(chezmoi execute-template --init --config "$cfgdir/chezmoi.toml" <"$CONFIG_TMPL" 2>&1); then
        echo "validate-templates: render FAILED for .chezmoi.toml.tmpl (sel='$selection'):" >&2
        echo "$out" >&2
        fail=1
    elif ! printf '%s' "$out" | parse_toml; then
        echo "validate-templates: rendered .chezmoi.toml.tmpl (sel='$selection') is not valid TOML" >&2
        fail=1
    fi
    rm -rf "$cfgdir"
done

if (( fail )); then
    exit 1
fi

if (( have_tomllib )); then
    echo "validate-templates: all template combinations render and parse"
else
    echo "validate-templates: rendered all combinations (TOML parse skipped, no tomllib)"
fi
