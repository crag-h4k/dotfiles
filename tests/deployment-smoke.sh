#!/usr/bin/env bash
# Shared runtime smoke test for a headless dotfiles deployment. This validates
# the deployed shell, Git, and tmux behavior without touching an existing tmux
# server or requiring an interactive terminal.
set -euo pipefail

fail() {
    printf 'deployment smoke test: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -ne 0 ]] || fail "must run as a non-root user"
[[ ! -t 0 ]] || fail "stdin must be non-interactive"

for command_name in chezmoi gh git tmux zoxide zsh; do
    command -v "$command_name" >/dev/null ||
        fail "expected deployed command missing: $command_name"
done

for managed_file in .zshrc .tmux.conf .gitconfig .gitignore_global; do
    [[ -f "$HOME/$managed_file" ]] ||
        fail "expected managed file missing: $HOME/$managed_file"
done
[[ ! -e "$HOME/.config/nvim/init.lua" ]] ||
    fail "Neovim config was deployed despite the focused component selection"

[[ "$(git config --global --get init.defaultBranch)" == main ]] ||
    fail "Git default branch is not main"
[[ "$(git config --global --type=bool --get user.useConfigOnly)" == true ]] ||
    fail "Git user.useConfigOnly is not enabled"
git_excludes=$(git config --global --path --get core.excludesfile)
[[ "$git_excludes" == "$HOME/.gitignore_global" ]] ||
    fail "Git excludes file did not resolve to the managed global ignore"
if git config --global --get user.email >/dev/null; then
    fail "personal Git identity was unexpectedly rendered in CI"
fi

TERM=xterm-256color zsh -ic '
    [[ "$ZSH_TMUX_CONFIG" == "$HOME/.tmux.conf" ]] || exit 21
    [[ "$ZSH_BASE" == "$HOME/.zsh" ]] || exit 22
    whence -p gh >/dev/null || exit 23
    whence -p zoxide >/dev/null || exit 24
    whence zsh_history_backup >/dev/null || exit 25
' </dev/null || fail "interactive Zsh did not load the managed runtime"

tmux_socket="dotfiles-smoke-${PPID}-$$"
cleanup() {
    tmux -L "$tmux_socket" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

zsh_bin=$(command -v zsh)
TERM=xterm-256color SHELL="$zsh_bin" \
    tmux -L "$tmux_socket" -f "$HOME/.tmux.conf" \
    new-session -d -s dotfiles-smoke

tmux_show() {
    tmux -L "$tmux_socket" show-options -gv "$1"
}

[[ "$(tmux_show mouse)" == on ]] || fail "tmux mouse support is not enabled"
[[ "$(tmux_show focus-events)" == on ]] ||
    fail "tmux focus events are not enabled"
[[ "$(tmux_show status)" == on ]] || fail "tmux status bar is not enabled"
[[ "$(tmux_show set-clipboard)" == on ]] ||
    fail "tmux OSC52 clipboard support is not enabled"
[[ "$(tmux -L "$tmux_socket" show-window-options -gv mode-keys)" == vi ]] ||
    fail "tmux copy mode is not using vi keys"
[[ "$(tmux_show default-shell)" == "$zsh_bin" ]] ||
    fail "tmux default shell is not the deployed Zsh"

# The memory-sized scrollback limit is set by an asynchronous tmux run-shell.
history_limit=0
scrollback_limit=0
attempt=0
while (( attempt < 50 )); do
    history_limit=$(tmux_show history-limit)
    scrollback_limit=$(
        tmux -L "$tmux_socket" show-options -gv @scrollback-limit 2>/dev/null ||
            printf '0\n'
    )
    if (( history_limit >= 50000 && scrollback_limit >= 50000 )); then
        break
    fi
    attempt=$(( attempt + 1 ))
    sleep 0.1
done
(( history_limit >= 50000 && scrollback_limit >= 50000 )) ||
    fail "tmux dynamic scrollback limit was not applied"

# tmux 3.7 added structured list-keys output, but its exact-key query can exit
# successfully without printing the requested binding. List the table and select
# WheelUpPane by its structured key name instead. tmux 3.5 does not support -F,
# so retain its exact-key query as the compatibility path.
if root_bindings=$(
    tmux -L "$tmux_socket" \
        list-keys -T root -F '#{key_string}|#{key_command}' 2>/dev/null
); then
    wheel_binding=$(
        awk '
            index($0, "WheelUpPane|") == 1 {
                print substr($0, length("WheelUpPane|") + 1)
                exit
            }
        ' <<<"$root_bindings"
    )
else
    wheel_binding=$(tmux -L "$tmux_socket" list-keys -T root WheelUpPane)
fi
# Command flags may be serialized in a different order between versions. Check
# the behavior and scroll-exit flag independently instead of depending on one
# presentation.
if [[ "$wheel_binding" != *"copy-mode"* ||
    "$wheel_binding" != *"-e"* ]]; then
    fail "tmux mouse wheel binding is unexpected: $wheel_binding"
fi

printf 'Headless deployment runtime smoke test passed on %s\n' "$(uname -s)"
