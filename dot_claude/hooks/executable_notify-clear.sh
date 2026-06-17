#!/usr/bin/env bash
# ~/.claude/hooks/notify-clear.sh
# Claude Code UserPromptSubmit hook: clears the tmux notification set by
# notify-tmux.sh. Fires when the user submits a new prompt, so the flag persists
# until then.
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
# shellcheck source=/dev/null  # resolved at runtime from $HOME
. "$HOME/.tmux/notify-lib.sh"
notify_clear "$TMUX_PANE"
