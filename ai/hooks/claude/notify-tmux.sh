#!/usr/bin/env bash
# Claude Code attention hook. The shared workspace installer links this adapter
# into the configured AI directory and settings.json registers it globally.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
export NOTIFY_SRC=claude-hook
# shellcheck source=/dev/null
. "$HOME/.config/notify/lib.sh"

if notify_debug_on; then
  evt=$(cat 2>/dev/null \
        | yq -p=json '[.hook_event_name // "?", .notification_type // .tool_name // "-"] | join(" ")' 2>/dev/null)
  notify_log "claude event: ${evt:-unknown}"
fi

notify_fire "$TMUX_PANE" claude
