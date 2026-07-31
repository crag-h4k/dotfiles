#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook: clear the tmux attention indicator.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
export NOTIFY_SRC=claude-hook
# shellcheck source=/dev/null
. "$HOME/.config/notify/lib.sh"
notify_clear "$TMUX_PANE" claude-prompt
