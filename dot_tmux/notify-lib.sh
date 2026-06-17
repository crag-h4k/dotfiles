# ~/.tmux/notify-lib.sh
# shellcheck shell=bash
# Shared, array-free tmux notification helpers. Sourced by the zsh process
# notifier (~/.zsh/custom/functions/notify-process.zsh) and by the Claude/Codex
# hooks (~/.claude/hooks/notify-*.sh).
#
# Contains ONLY function definitions - no top-level variables - so nothing leaks
# into the interactive zsh that sources it. No associative arrays (macOS
# /bin/bash is 3.2 and lacks them); per-group color/sound come from tmux options
# @notify_<group>_bg|accent|sound, which the zsh notifier publishes from its
# table on shell init. All tmux calls go through _notify_tmux, which finds the
# binary even when PATH is stripped (a GUI-launched hook env may lack
# /opt/homebrew/bin) and bypasses the oh-my-zsh tmux plugin wrapper.

_notify_tmux() {
  # Run tmux robustly: prefer PATH (and `command` to skip the OMZ tmux function
  # in interactive zsh), else fall back to common absolute locations.
  if command -v tmux >/dev/null 2>&1; then
    command tmux "$@"
  else
    local t
    for t in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux /bin/tmux; do
      if [ -x "$t" ]; then "$t" "$@"; return; fi
    done
    return 127
  fi
}

notify_play() {
  # $1 = sound basename in ~/.tmux/sounds (e.g. funk.mp3). Empty/missing = silent.
  [ -n "$1" ] || return 0
  local f="$HOME/.tmux/sounds/$1" vol
  [ -f "$f" ] || return 0
  vol=$(_notify_tmux show-option -gqv @notify_volume 2>/dev/null)
  [ -n "$vol" ] || vol=25
  if command -v afplay >/dev/null 2>&1; then
    ( afplay -v "$(awk "BEGIN { printf \"%.2f\", $vol/100 }")" "$f" & ) >/dev/null 2>&1
  elif command -v mpg123 >/dev/null 2>&1; then
    ( mpg123 -q --volume "$vol" "$f" & ) >/dev/null 2>&1
  elif command -v ffplay >/dev/null 2>&1; then
    ( ffplay -nodisp -autoexit -loglevel quiet -volume "$vol" "$f" & ) >/dev/null 2>&1
  fi
}

notify_fire() {
  # $1 = pane id, $2 = group name
  local pane="$1" grp="$2" bg accent snd
  [ -n "$pane" ] || return 0
  bg=$(_notify_tmux show-option -gqv "@notify_${grp}_bg" 2>/dev/null)
  [ -n "$bg" ] || bg='#5b1a1a'
  accent=$(_notify_tmux show-option -gqv "@notify_${grp}_accent" 2>/dev/null)
  [ -n "$accent" ] || accent='#ff5555'
  snd=$(_notify_tmux show-option -gqv "@notify_${grp}_sound" 2>/dev/null)
  # @notify drives the status-bar flag (pane + window scope); window-style
  # recolors the pane (visible on shell panes; hidden behind full-screen TUIs).
  _notify_tmux \
    set-option -p -t "$pane" @notify 1 \; \
    set-option -w -t "$pane" @notify 1 \; \
    set-option -p -t "$pane" @notify_accent "$accent" \; \
    set-option -w -t "$pane" @notify_accent "$accent" \; \
    set-option -p -t "$pane" window-style "bg=$bg" \; \
    set-option -p -t "$pane" window-active-style "bg=$bg" 2>/dev/null
  notify_play "$snd"
}

notify_clear() {
  # $1 = pane id. Idempotent (unsetting an unset option is a no-op).
  local pane="$1"
  [ -n "$pane" ] || return 0
  _notify_tmux \
    set-option -pu -t "$pane" window-style \; \
    set-option -pu -t "$pane" window-active-style \; \
    set-option -p  -t "$pane" @notify '' \; \
    set-option -w  -t "$pane" @notify '' \; \
    set-option -p  -t "$pane" @notify_accent '' \; \
    set-option -w  -t "$pane" @notify_accent '' 2>/dev/null
}
