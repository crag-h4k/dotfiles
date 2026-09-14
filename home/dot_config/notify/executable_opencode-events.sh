#!/usr/bin/env bash
# ~/.config/notify/opencode-events.sh
# OpenCode attention shim: flags/clears the tmux pane via the shared notifier.
# Called by the OpenCode notifier bridge plugin (~/.config/opencode/plugin/notify.ts):
#   fire  - OpenCode went idle (session.idle) or asked for permission (permission.updated)
#   clear - the pane was re-engaged / a new prompt started
# Mirrors the Claude hooks (~/.claude/hooks/notify-tmux.sh, notify-clear.sh):
# guards on $TMUX/$TMUX_PANE, sources lib.sh, and fires the 'opencode' group whose
# appearance (dark_yellow / bright_yellow, silent) lives in
# ~/.config/notify/notify.yaml. tmux never reads the config; notify_fire pushes the
# per-pane color that ~/.tmux/conf.d/notify.conf renders.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
export NOTIFY_SRC=opencode-hook
# shellcheck source=/dev/null  # resolved at runtime from $HOME
. "$HOME/.config/notify/lib.sh"

case "${1:-fire}" in
  fire)  notify_fire  "$TMUX_PANE" opencode ;;
  clear) notify_clear "$TMUX_PANE" opencode ;;
  *)     printf 'usage: opencode-events.sh {fire|clear}\n' >&2; exit 2 ;;
esac
