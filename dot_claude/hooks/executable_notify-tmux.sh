#!/usr/bin/env bash
# ~/.claude/hooks/notify-tmux.sh
# Claude Code Stop hook - visually flags the tmux pane when Claude finishes a
# response. Clears automatically when the pane gains focus (see notify.conf).
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
tmux set -p -t "$TMUX_PANE" @notify 1
tmux set -p -t "$TMUX_PANE" window-style        "bg=#5b1a1a"
tmux set -p -t "$TMUX_PANE" window-active-style  "bg=#5b1a1a"
tmux set -w -t "$TMUX_PANE" @notify 1
