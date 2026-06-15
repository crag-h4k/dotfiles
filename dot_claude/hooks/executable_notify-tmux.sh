#!/usr/bin/env bash
# ~/.claude/hooks/notify-tmux.sh
# Claude Code Stop hook - visually flags the tmux pane when Claude finishes a
# response. Color and sound are configured via @notify_color / @notify_sound in
# ~/.tmux.conf. Cleared on next UserPromptSubmit (see notify-clear.sh).
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0

COLOR=$(tmux show-option -gqv @notify_color 2>/dev/null)
COLOR="${COLOR:-#5b1a1a}"
SOUND=$(tmux show-option -gqv @notify_sound 2>/dev/null)

tmux set -p -t "$TMUX_PANE" @notify 1
tmux set -p -t "$TMUX_PANE" window-style        "bg=$COLOR"
tmux set -p -t "$TMUX_PANE" window-active-style  "bg=$COLOR"
tmux set -w -t "$TMUX_PANE" @notify 1

if [[ -n "$SOUND" && -f "$SOUND" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    afplay "$SOUND" &
  elif command -v mpg123 &>/dev/null; then
    mpg123 -q "$SOUND" &
  elif command -v mpg321 &>/dev/null; then
    mpg321 -q "$SOUND" &
  elif command -v ffplay &>/dev/null; then
    ffplay -nodisp -autoexit -loglevel quiet "$SOUND" &
  fi
fi
