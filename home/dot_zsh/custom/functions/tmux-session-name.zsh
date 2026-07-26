# ~/.zsh/custom/functions/tmux-session-name.zsh
# Name the tmux session after its project root, unless it was named manually.
# Session name = stable identity (git toplevel basename, else cwd basename); the
# WINDOW name tracks the running command via tmux automatic-rename (see
# ~/.tmux.conf). We deliberately do NOT append the last command to the session
# name: that churns `tmux ls` / tmux-resurrect. A guarded chpwd hook does the
# work; a one-shot precmd handles session start, then removes itself so there is
# zero per-prompt cost thereafter.

_tmux_auto_session_name() {
  emulate -L zsh
  [[ -n $TMUX ]] || return
  # Use the real tmux, not the OMZ tmux-plugin wrapper: reuse the notify locator
  # if it is loaded (it strips PATH + bypasses the wrapper), else `command tmux`.
  local T
  if (( ${+functions[_notify_tmux]} )); then T=_notify_tmux; else T="command tmux"; fi

  # Manage this session only when it is auto-named. The tmux session-created hook
  # sets @auto_named (1 = auto, 0 = manual). If the marker is unset (e.g. a
  # session that predates the hook), infer it: an all-digit default name is auto.
  local an
  an=$($=T show-options -qv @auto_named 2>/dev/null)
  if [[ -z $an ]]; then
    if [[ $($=T display-message -p '#S' 2>/dev/null) == <-> ]]; then an=1; else an=0; fi
  fi
  [[ $an == 1 ]] || return

  local root name cur
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$PWD
  name=${root:t}
  name=${name//[.:]/_}          # tmux forbids '.' and ':' in session names
  [[ -n $name ]] || return
  cur=$($=T display-message -p '#S' 2>/dev/null)
  [[ $name == "$cur" ]] && return
  $=T rename-session -- "$name" 2>/dev/null
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _tmux_auto_session_name

# Run once on the first prompt (session start), then remove this precmd so there
# is no per-prompt cost; chpwd handles every later directory change.
_tmux_auto_session_name_once() {
  _tmux_auto_session_name
  add-zsh-hook -d precmd _tmux_auto_session_name_once
}
add-zsh-hook precmd _tmux_auto_session_name_once
