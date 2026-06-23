#!/usr/bin/env bash
# ~/.codex/hooks/notify-tmux.sh
# Codex CLI attention hook: flags the tmux pane via the shared notifier. Wired in
# ~/.codex/config.toml by the chezmoi modify_ script dot_codex/modify_private_config.toml,
# which sets:
#   notify = ["~/.codex/hooks/notify-tmux.sh"]
# Codex appends ONE JSON argument and execs the program directly (no shell), so the
# event payload arrives as $1 (not on stdin like Claude) and the path must be
# absolute. The only event Codex emits today is agent-turn-complete - the analog of
# Claude's Stop. Appearance/sound for the 'codex' group come from
# ~/.config/notify/notify.yaml. There is no Codex clear event; the flag clears via
# the generic focus-in auto-clear in ~/.tmux/conf.d/notify.conf when you select the
# pane.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
# Only fire on turn completion. Guards against future Codex event types firing the
# notifier unexpectedly; a cheap string match avoids parsing the payload on the hot
# path. Empty arg (manual test) falls through and fires.
case "${1:-}" in
  ''|*'"agent-turn-complete"'*) ;;
  *) exit 0 ;;
esac
export NOTIFY_SRC=codex-hook
# shellcheck source=/dev/null  # resolved at runtime from $HOME
. "$HOME/.config/notify/lib.sh"

# Only when debugging: record the event type / turn id Codex actually sent (the
# JSON payload is $1). Skipped entirely when debug is off.
if notify_debug_on; then
  evt=$(printf '%s' "${1:-}" \
        | yq -p=json '[.type // "?", .["turn-id"] // "-"] | join(" ")' 2>/dev/null)
  notify_log "codex event: ${evt:-unknown}"
fi

notify_fire "$TMUX_PANE" codex
