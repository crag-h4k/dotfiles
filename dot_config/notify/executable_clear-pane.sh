#!/bin/sh
# ~/.config/notify/clear-pane.sh
# Clear one tmux pane through the shared notification library.

set -eu

pane=${1:-}
[ -n "$pane" ] || exit 0

# shellcheck source=/dev/null
. "$HOME/.config/notify/lib.sh"
notify_clear "$pane"
