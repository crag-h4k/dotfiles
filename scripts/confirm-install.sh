#!/usr/bin/env bash
# scripts/confirm-install.sh
# Show the package plan on the controlling TTY and emit only the selected mode.

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
printf 'dotfiles: inspecting installed packages...\n' >"$TTY_DEVICE"
# Force color: --display stdout is captured here (a pipe, not a TTY), but it
# renders to the terminal below. _display still honors NO_COLOR.
plan=$(DOTFILES_PLAN_COLOR=1 "$PLAN" --display)
elapsed=$(( SECONDS - started ))
printf 'dotfiles: package inspection complete (%ss).\n\n' "$elapsed" >"$TTY_DEVICE"

# Print the plan directly, no border box, so the new/outdated items at the top
# are the first thing read.
printf '%s\n\n' "$plan" >"$TTY_DEVICE"

if [[ -z "${DOTFILES_NO_TUI:-}" ]] && command -v gum >/dev/null 2>&1; then
    # Keep stdin on the terminal so gum can read its color/cursor replies.
    # SC2094: reading and writing the same TTY device in one command is
    # intentional (that is how a TTY works).
    # shellcheck disable=SC2094
    choice=$(gum choose \
        --header "Choose what chezmoi should apply:" \
        --selected "Install configs and packages" \
        "Install configs and packages" \
        "Install configs only" \
        "Exit" <"$TTY_DEVICE" 2>"$TTY_DEVICE" || true)
else
    printf '1) Install configs and packages\n2) Install configs only\n3) Exit\nChoice [1]: ' >"$TTY_DEVICE"
    IFS= read -r choice <"$TTY_DEVICE" || choice=3
fi

case "$choice" in
    "Install configs and packages"|1|"")
        # One-shot handshake so the apply that immediately follows this interactive
        # init does not re-prompt. The shared resolver rejects stale inherited
        # XDG_RUNTIME_DIR values and selects an owned UID-specific fallback.
        _sentinel=""
        _sentinel=$(_pkg_confirm_sentinel) || true
        [[ -z "$_sentinel" ]] || date +%s >"$_sentinel" 2>/dev/null || true
        printf 'packages\n'
        ;;
    "Install configs only"|2) printf 'configs\n' ;;
    *) printf 'exit\n' ;;
esac
