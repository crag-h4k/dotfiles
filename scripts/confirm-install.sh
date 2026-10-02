#!/usr/bin/env bash
# scripts/confirm-install.sh
# Refresh package metadata, show the plan, and emit the selected install mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
PLAN="$SCRIPT_DIR/package-plan.sh"
TTY_DEVICE="${DOTFILES_TTY:-/dev/tty}"

if [[ ! -e "$TTY_DEVICE" ]]; then
    printf 'confirm-install: no controlling terminal\n' >&2
    exit 2
fi

started=$SECONDS
printf 'dotfiles: refreshing package metadata...\n' >"$TTY_DEVICE"
if ! "$PLAN" --refresh >"$TTY_DEVICE" 2>&1; then
    printf 'dotfiles: package metadata refresh failed; configuration-only apply selected.\n' >"$TTY_DEVICE"
    printf 'configs\n'
    exit 0
fi
# Force color: --display stdout is captured here (a pipe, not a TTY), but it
# renders to the terminal below. A refreshed inventory lets the plan show the
# actual missing and outdated selected packages rather than a guess from PATH.
plan=$(DOTFILES_PLAN_APPROVED=1 DOTFILES_PLAN_COLOR=1 "$PLAN" --display)
elapsed=$(( SECONDS - started ))
printf 'dotfiles: package metadata refresh and inspection complete (%ss).\n\n' "$elapsed" >"$TTY_DEVICE"

# Print the plan directly, no border box, so the new/outdated items at the top
# are the first thing read.
printf '%s\n\n' "$plan" >"$TTY_DEVICE"

printf 'dotfiles: apply this package plan? [y/N] ' >"$TTY_DEVICE"
IFS= read -r choice <"$TTY_DEVICE" || choice=""

case "$choice" in
    [Yy]|[Yy][Ee][Ss])
        # One-shot handshake so the apply that immediately follows this interactive
        # init does not re-prompt. The shared resolver rejects stale inherited
        # XDG_RUNTIME_DIR values and selects an owned UID-specific fallback.
        _sentinel=""
        _sentinel=$(_pkg_confirm_sentinel) || true
        [[ -z "$_sentinel" ]] || date +%s >"$_sentinel" 2>/dev/null || true
        printf 'packages\n'
        ;;
    *) printf 'configs\n' ;;
esac
