#!/usr/bin/env bash
# ~/.claude/hooks/notify-tmux.sh
# Claude Code Stop hook - visually flags the tmux pane when Claude finishes a
# response. Color and sound are configured via @notify_color / @notify_sound in
# ~/.tmux.conf. Cleared on next UserPromptSubmit (see notify-clear.sh).
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0

COLOR=$(tmux show-option -gqv @notify_color 2>/dev/null)
COLOR="${COLOR:-#5b1a1a}"
SOUND=$(tmux show-option -gqv @notify_sound 2>/dev/null)
SOUND="${SOUND/#\~/$HOME}"
VOLUME=$(tmux show-option -gqv @notify_volume 2>/dev/null)
VOLUME="${VOLUME:-75}"
VOLUME_FLOAT=$(awk "BEGIN { printf \"%.2f\", $VOLUME/100 }")

tmux set -p -t "$TMUX_PANE" @notify 1
tmux set -p -t "$TMUX_PANE" window-style        "bg=$COLOR"
tmux set -p -t "$TMUX_PANE" window-active-style  "bg=$COLOR"
tmux set -w -t "$TMUX_PANE" @notify 1

if [[ -n "$SOUND" && -f "$SOUND" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    afplay -v "$VOLUME_FLOAT" "$SOUND" &
  elif command -v mpg123 &>/dev/null; then
    # Linux preferred: apt install mpg123
    mpg123 -q --volume "$VOLUME" "$SOUND" &
  elif command -v ffplay &>/dev/null; then
    # Linux fallback (ffmpeg): apt install ffmpeg
    ffplay -nodisp -autoexit -loglevel quiet -volume "$VOLUME" "$SOUND" &
  fi
fi
