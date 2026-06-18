#!/usr/bin/env bash
# ~/.claude/hooks/notify-tmux.sh
# Claude Code attention hook: flags the tmux pane via the shared notifier. Wired
# globally in ~/.claude/settings.json by the chezmoi modify_ script
# dot_claude/modify_settings.json to these events:
#   Stop                         - Claude finished a turn
#   Notification                 - permission prompt / idle / MCP elicitation
#   PreToolUse:AskUserQuestion   - the interactive question tool (no Notification
#                                  event fires for it, so we catch the tool call)
# Appearance/sound for the 'claude' group come from ~/.config/notify/notify.yaml.
# Cleared on the next UserPromptSubmit (see notify-clear.sh).
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
export NOTIFY_SRC=claude-hook
# shellcheck source=/dev/null  # resolved at runtime from $HOME
. "$HOME/.config/notify/lib.sh"

# Only when debugging: record which event/notification type Claude actually sent
# (stdin is JSON). This is how we confirm what fires for permission prompts vs
# AskUserQuestion without guessing. Skipped entirely when debug is off.
if notify_debug_on; then
  evt=$(cat 2>/dev/null \
        | yq -p=json '[.hook_event_name // "?", .notification_type // .tool_name // "-"] | join(" ")' 2>/dev/null)
  notify_log "claude event: ${evt:-unknown}"
fi

notify_fire "$TMUX_PANE" claude
