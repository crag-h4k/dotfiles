#!/usr/bin/env bash
# Codex attention hook. Codex passes its event payload as the first argument.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
case "${1:-}" in
  ''|*'"agent-turn-complete"'*) ;;
  *) exit 0 ;;
esac
export NOTIFY_SRC=codex-hook
# shellcheck source=/dev/null
. "$HOME/.config/notify/lib.sh"

if notify_debug_on; then
  evt=$(printf '%s' "${1:-}" \
        | yq -p=json '[.type // "?", .["turn-id"] // "-"] | join(" ")' 2>/dev/null)
  notify_log "codex event: ${evt:-unknown}"
fi

notify_fire "$TMUX_PANE" codex
