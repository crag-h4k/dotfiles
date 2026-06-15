#!/usr/bin/env bash
# ~/.claude/hooks/notify-clear.sh
# Claude Code UserPromptSubmit hook - clears the tmux notification set by notify-tmux.sh.
# Fires when the user submits a new prompt, so the red background persists until then.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
tmux set -pu -t "$TMUX_PANE" window-style
tmux set -pu -t "$TMUX_PANE" window-active-style
tmux set -p  -t "$TMUX_PANE" @notify ''
tmux set -w  -t "$TMUX_PANE" @notify ''
