#!/usr/bin/env bash
# ~/.config/notify/opencode-events.sh
# OpenCode attention shim: flags/clears the tmux pane via the shared notifier.
# Called by the OpenCode notifier bridge plugin (~/.config/opencode/plugin/notify.ts)
# and by the OpenCode TUI plugin:
#   fire [group]          - OpenCode wants attention; the server plugin passes the
#                           group that matches what it is waiting for (see below).
#                           Tints the pane and plays the group's sound.
#   clear [group]         - the pane was re-engaged / a new prompt started. Clears
#                           the pane's OWN tint; an elsewhere tint (below) stays.
#   tint own <group>      - the viewed tab's own alert: pane tint plus window pill.
#                           No focus gate and no sound; the TUI plugin decides.
#   tint elsewhere <group> - another tab needs attention: store a dimmed tint,
#                           show it and the pill if the pane has no own tint. Never
#                           sets @notify, so the keypress clear leaves it alone.
#   tint clear            - drop the own AND the elsewhere state and the pill.
#   describe              - print the group colors, sounds, volumes and the
#                           elsewhere dim as one line of JSON ({} if the config
#                           cannot be read). Works with or without tmux.
# Groups, all defined under `integrations:` in ~/.config/notify/notify.yaml:
#   opencode             turn finished (session.execution.succeeded)
#   opencode_permission  blocked on a permission prompt (permission.asked)
#   opencode_question    blocked on a question or auth form (v2 form.created)
# An unknown or empty group falls back to `opencode`, so an older plugin that
# passes no argument keeps working. Mirrors the Claude hooks
# (~/.claude/hooks/notify-tmux.sh, notify-clear.sh): sources lib.sh and lets
# notify_fire push the per-pane color that ~/.tmux/conf.d/notify.conf renders.
# tmux never reads the config itself.
#
# Behavior specific to this bridge; the Claude, Codex and zsh notifiers are not
# affected.
#   Outside tmux (no $TMUX or no $TMUX_PANE) every verb except `describe` exits
#   quietly. There is no pane to flag, and OpenCode's own attention.sound, which
#   the opencode2 wrapper configures from notify.yaml, covers sound there. Playing
#   it here too would double-fire.
#   Inside tmux every verb first checks that the pane is still on the live server
#   and does nothing for a stale one.
#   `fire` alone skips the visual flag when tmux positively reports that a focused
#   client is already looking at this very pane: it is the active pane of the
#   current window and the client has not reported focus-out. The sound still
#   plays. The gate only ever removes visual output. Every doubt (a failed or
#   unparsable lookup, focus reporting off, an unfocused or absent client)
#   falls back to the full tint. The tint verbs are never gated.
_verb="${1:-fire}"
if [[ "$_verb" != describe && ( -z "$TMUX" || -z "$TMUX_PANE" ) ]]; then
  exit 0
fi
export NOTIFY_SRC=opencode-hook
if [ ! -r "$HOME/.config/notify/lib.sh" ] && [ "$_verb" = describe ]; then
  printf '{}\n'
  exit 0
fi
# shellcheck source=/dev/null  # resolved at runtime from $HOME
. "$HOME/.config/notify/lib.sh"

usage() {
  printf 'usage: opencode-events.sh {fire|clear} [group] | tint {own|elsewhere} <group> | tint clear | describe\n' >&2
  exit 2
}

# fire and clear take the group second; tint takes a mode second and the group third.
_mode=""
_gin="${2:-}"
case "$_verb" in
  fire|clear|describe) ;;
  tint)
    _mode="${2:-}"
    _gin="${3:-}"
    case "$_mode" in own|elsewhere|clear) ;; *) usage ;; esac
    ;;
  *) usage ;;
esac

if [ "$_verb" = describe ]; then
  notify_describe
  exit 0
fi

case "${_gin:-opencode}" in
  opencode|opencode_permission|opencode_question) _group="${_gin:-opencode}" ;;
  *) notify_log "unknown group ${_gin:-}; falling back to opencode"; _group=opencode ;;
esac

# One tmux call answers both questions: is this pane still on the live server,
# and is a focused client looking at it. The fields are, in order: pane id, pane
# is the active pane, window is the session's current window, attached client
# count, session id, the best client's flags, and the focus-events option.
#
# A stale pane is rejected before any work. A long-lived OpenCode background
# service (opencode2 serve --service) keeps the TMUX/TMUX_PANE it was first
# started with for as long as it runs, which can be days. After a tmux server
# restart those vars are still set but name a pane that no longer exists, so every
# fire would land nowhere. tmux exits 0 with empty output for a dead target, so
# compare the resolved pane id rather than the exit status.
_probe=$(_notify_tmux display-message -p -t "$TMUX_PANE" \
  '#{pane_id}|#{pane_active}|#{window_active}|#{session_attached}|#{session_id}|#{client_flags}|#{focus-events}' 2>/dev/null)
_pane=${_probe%%|*}
if [ "$_pane" != "$TMUX_PANE" ]; then
  notify_log_always "stale pane $TMUX_PANE is not on this tmux server; skipping"
  printf 'notify: stale pane %s, restart the opencode2 background service\n' "$TMUX_PANE" >&2
  exit 0
fi

# _pane_in_view: succeed only when every signal says a focused client is looking
# at this pane. A client that has not reported focus-out counts as focused, which
# is why focus-events must be on: without it tmux never learns of a blur and every
# client would look focused forever, hiding the tint from someone who has switched
# away. The window must also be the session's current window, or the pane is not
# on screen at all. Any missing or odd field fails the test, never the shim.
_pane_in_view() {
  local rest="${_probe#*|}" active window attached sid flags events clients
  active=${rest%%|*};   rest=${rest#*|}
  window=${rest%%|*};   rest=${rest#*|}
  attached=${rest%%|*}; rest=${rest#*|}
  sid=${rest%%|*};      rest=${rest#*|}
  flags=${rest%%|*};    events=${rest#*|}
  [ "$active" = 1 ] && [ "$window" = 1 ] && [ "$events" = 1 ] || return 1
  case "$attached" in
    1) ;;
    ''|0|*[!0-9]*) return 1 ;;
    *)
      # With several clients the one display-message picked is arbitrary. The
      # pane is in view if any client of this session is focused.
      [ -n "$sid" ] || return 1
      clients=$(_notify_tmux list-clients -t "$sid" -F '#{client_flags}' 2>/dev/null) || return 1
      flags=${clients//$'\n'/,}
      ;;
  esac
  case ",$flags," in *,focused,*) return 0 ;; esac
  return 1
}

case "$_verb" in
  fire)
    if _pane_in_view; then
      notify_log "pane $TMUX_PANE is in view of a focused client; sound only"
      notify_fire "$TMUX_PANE" "$_group" sound
    else
      notify_fire "$TMUX_PANE" "$_group"
    fi
    ;;
  clear) notify_clear "$TMUX_PANE" "$_group" ;;
  tint)
    case "$_mode" in
      own)       notify_tint "$TMUX_PANE" "$_group" ;;
      elsewhere) notify_tint_elsewhere "$TMUX_PANE" "$_group" ;;
      clear)     notify_tint_clear "$TMUX_PANE" ;;
    esac
    ;;
esac
