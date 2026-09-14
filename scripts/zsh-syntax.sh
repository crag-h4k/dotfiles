#!/usr/bin/env bash
# scripts/zsh-syntax.sh
# Parse-check zsh files with `zsh -n`. ShellCheck cannot parse zsh, so
# home/dot_zsh/ is excluded from it in .pre-commit-config.yaml, which left these
# files with no syntax gate at all: a broken function would install fine and only
# surface as a parse error on the next shell start.
#
# ONE FILE PER INVOCATION, deliberately. `zsh -n a.zsh b.zsh` checks only a.zsh
# and treats the rest as positional arguments to it, so a batched call exits 0
# while silently ignoring every file after the first. Verified: a file with an
# unterminated `if` passes when it is not the first argument.
#
# This is a syntax check, not a linter. It catches parse errors, not bad logic.

set -uo pipefail

if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh-syntax: zsh not found on PATH" >&2
    exit 1
fi

fail=0
for f in "$@"; do
    if ! out=$(zsh -n "$f" 2>&1); then
        printf '%s\n' "$out" >&2
        fail=1
    fi
done

exit "$fail"
