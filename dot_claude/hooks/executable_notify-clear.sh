#!/usr/bin/env bash
# ~/.claude/hooks/notify-clear.sh
# Claude Code UserPromptSubmit hook: clears the tmux notification set by
# notify-tmux.sh. Fires when you submit a new prompt, so the flag persists until
# then. Appearance/behavior come from ~/.config/notify/notify.yaml.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
export NOTIFY_SRC=claude-hook
# shellcheck source=/dev/null  # resolved at runtime from $HOME
. "$HOME/.config/notify/lib.sh"
notify_clear "$TMUX_PANE"
