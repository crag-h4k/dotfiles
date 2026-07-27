#!/bin/sh
# ~/.config/notify/clear-pane.sh
# Clear one tmux pane through the shared notification library.

set -eu

pane=${1:-}
[ -n "$pane" ] || exit 0
# Optional reason (logged only) so debug output shows which tmux binding cleared
# the pane. Defaults to a generic mouse/binding tag; the key binding passes "key".
reason=${2:-tmux-input}

# shellcheck source=/dev/null
. "$HOME/.config/notify/lib.sh"
notify_clear "$pane" "$reason"
