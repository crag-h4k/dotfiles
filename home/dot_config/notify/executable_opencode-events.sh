#!/usr/bin/env bash
# ~/.config/notify/opencode-events.sh
# OpenCode attention shim: flags/clears the tmux pane via the shared notifier.
# Called by the OpenCode notifier bridge plugin (~/.config/opencode/plugin/notify.ts):
#   fire  - OpenCode wants attention: the turn finished (the v2 beta emits
#           session.execution.succeeded; it has no session.idle), or it is
#           blocked on a permission / question prompt
#   clear - the pane was re-engaged / a new prompt started
# Mirrors the Claude hooks (~/.claude/hooks/notify-tmux.sh, notify-clear.sh):
# guards on $TMUX/$TMUX_PANE, sources lib.sh, and fires the 'opencode' group whose
# appearance (dark_yellow / bright_yellow + glass.mp3) lives in
# ~/.config/notify/notify.yaml. tmux never reads the config; notify_fire pushes the
# per-pane color that ~/.tmux/conf.d/notify.conf renders.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
export NOTIFY_SRC=opencode-hook
# shellcheck source=/dev/null  # resolved at runtime from $HOME
. "$HOME/.config/notify/lib.sh"

# Reject a stale pane id before doing any work. A long-lived OpenCode background
# service (opencode2 serve --service) keeps the TMUX/TMUX_PANE it was first
# started with for as long as it runs, which can be days. After a tmux server
# restart those vars are still set but name a pane that no longer exists, so the
# guard above passes and every fire lands nowhere. tmux exits 0 with empty output
# for a dead target, so compare the resolved pane id rather than the exit status.
_pane=$(_notify_tmux display-message -p -t "$TMUX_PANE" '#{pane_id}' 2>/dev/null)
if [ "$_pane" != "$TMUX_PANE" ]; then
  notify_log "stale pane $TMUX_PANE is not on this tmux server; skipping"
  printf 'notify: stale pane %s, restart the opencode2 background service\n' "$TMUX_PANE" >&2
  exit 0
fi

case "${1:-fire}" in
  fire)  notify_fire  "$TMUX_PANE" opencode ;;
  clear) notify_clear "$TMUX_PANE" opencode ;;
  *)     printf 'usage: opencode-events.sh {fire|clear}\n' >&2; exit 2 ;;
esac
