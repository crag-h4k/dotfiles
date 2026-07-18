#!/usr/bin/env bash
# scripts/confirm-install.sh
# Show the package plan on the controlling TTY and emit only the selected mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="$SCRIPT_DIR/package-plan.sh"
TTY_DEVICE="${DOTFILES_TTY:-/dev/tty}"

if [[ ! -e "$TTY_DEVICE" ]]; then
    printf 'confirm-install: no controlling terminal\n' >&2
    exit 2
fi

started=$SECONDS
printf 'dotfiles: inspecting installed packages...\n' >"$TTY_DEVICE"
plan=$("$PLAN" --display)
elapsed=$(( SECONDS - started ))
printf 'dotfiles: package inspection complete (%ss).\n\n' "$elapsed" >"$TTY_DEVICE"

if command -v gum >/dev/null 2>&1; then
    # Keep stdin on the terminal. Gum queries terminal color and cursor state;
    # piping the plan into stdin prevents Gum from reading those replies and
    # leaves raw OSC/CSI response bytes in the shell.
    gum style --border rounded --padding "1 2" "$plan" \
        <"$TTY_DEVICE" >"$TTY_DEVICE" 2>"$TTY_DEVICE"
    choice=$(gum choose \
        --header "Choose what chezmoi should apply:" \
        --selected "Install configs and packages" \
        "Install configs and packages" \
        "Install configs only" \
        "Exit" <"$TTY_DEVICE" 2>"$TTY_DEVICE" || true)
else
    printf '%s\n' "$plan" >"$TTY_DEVICE"
    printf '\n1) Install configs and packages\n2) Install configs only\n3) Exit\nChoice [1]: ' >"$TTY_DEVICE"
    IFS= read -r choice <"$TTY_DEVICE" || choice=3
fi

case "$choice" in
    "Install configs and packages"|1|"") printf 'packages\n' ;;
    "Install configs only"|2) printf 'configs\n' ;;
    *) printf 'exit\n' ;;
esac
