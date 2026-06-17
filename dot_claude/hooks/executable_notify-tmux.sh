#!/usr/bin/env bash
# ~/.claude/hooks/notify-tmux.sh
# Claude Code Stop + Notification hook: flags the tmux pane for attention.
# Registered globally via ~/.claude/notify-hooks.json (loaded by the `claude`
# wrapper in ~/.zsh/custom/functions/claude-wrapper.zsh using `--settings`).
# Color/sound for the `claude` group come from @notify_claude_* tmux options,
# published by ~/.zsh/custom/functions/notify-process.zsh. Cleared on the next
# UserPromptSubmit (see notify-clear.sh).
[[ -z "$TMUX" || -z "$TMUX_PANE" ]] && exit 0
# shellcheck source=/dev/null  # resolved at runtime from $HOME
. "$HOME/.tmux/notify-lib.sh"
notify_fire "$TMUX_PANE" claude
