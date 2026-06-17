# ~/.zsh/custom/functions/notify-process.zsh
# Process-completion attention notifications, unified with the Claude/Codex
# hooks via ~/.tmux/notify-lib.sh. Owns only the detection logic: which binaries
# map to which notification group, and which to ignore. The per-group colors and
# sounds live in ~/.tmux.conf (@notify_<group>_bg|accent|sound); notify_fire
# reads them from there.

autoload -Uz add-zsh-hook add-zle-hook-widget
zmodload zsh/datetime 2>/dev/null

# Shared, array-free helpers: notify_fire / notify_clear / notify_play.
if ! typeset -f notify_fire >/dev/null 2>&1; then
  [[ -r ~/.tmux/notify-lib.sh ]] && source ~/.tmux/notify-lib.sh
fi

# --- Binary -> group. Named binaries fire on completion regardless of duration.
#     `sleep` -> default for easy testing (sleep 2 flashes immediately). ---
typeset -gA NOTIFY_GROUP=(
  terraform iac  terragrunt iac  tofu iac  tflint iac
  brew pkg  apt pkg  apt-get pkg  dnf pkg  yum pkg
  pip pkg  pip3 pkg  npm pkg  pnpm pkg  yarn pkg  cargo pkg
  sleep default
)

# --- Interactive / long-lived binaries that never fire the process path ---
typeset -ga NOTIFY_IGNORE=(
  vim nvim vi nano emacs less more man ssh htop top btop watch tmux fzf
  claude codex tail bat w3m lynx
)

# Catch-all: any other command running at least this many seconds fires `default`.
: ${NOTIFY_THRESHOLD:=30}

# Sets REPLY to the first "significant" word of "$@", skipping VAR=val
# assignments, command wrappers, and flags. No subshell (returns via REPLY).
_notify_first_word() {
  REPLY=''
  local w
  for w in "$@"; do
    case $w in
      (*=*) ;;                                                        # leading VAR=val
      (sudo|command|builtin|nohup|nice|time|env|exec|stdbuf|setsid) ;; # wrappers
      (-*) ;;                                                         # stray flag
      (*) REPLY=$w; return ;;
    esac
  done
}

# Resolve the "significant" binary of command line $1 into the global _notify_bin
# (no subshell, so preexec stays cheap). Expands zsh command aliases (so
# `alias tf=terraform` is detected) and prefers any pipeline segment whose binary
# is in a named group; otherwise the last segment's binary.
_notify_resolve_bin() {
  emulate -L zsh
  local line="$1" seg bin last_bin='' REPLY
  local -i i
  local -a segs
  segs=("${(@s:|:)line}")
  _notify_bin=''
  for seg in $segs; do
    _notify_first_word ${(z)seg}
    bin=$REPLY
    # follow command aliases (bounded against loops / self-aliases like ls='ls -G')
    i=0
    while [[ -n $bin && -n ${aliases[$bin]} ]] && (( i < 10 )); do
      _notify_first_word ${(z)${aliases[$bin]}}
      [[ -z $REPLY || $REPLY == $bin ]] && break
      bin=$REPLY
      (( i++ ))
    done
    bin=${bin:t}
    [[ -n $bin ]] && last_bin=$bin
    if [[ -n $bin && -n ${NOTIFY_GROUP[$bin]} ]]; then
      _notify_bin=$bin
      return
    fi
  done
  _notify_bin=$last_bin
}

typeset -g  _notify_bin=''
typeset -gi _notify_start=0
typeset -gi _notify_active=0

_notify_preexec() {
  [[ -n "$TMUX_PANE" ]] || return
  if (( _notify_active )); then
    notify_clear "$TMUX_PANE"
    _notify_active=0
  fi
  _notify_start=$EPOCHSECONDS
  _notify_resolve_bin "$1"
}

_notify_precmd() {
  local code=$?
  [[ -n "$TMUX_PANE" ]] || return
  (( _notify_start )) || return                      # no command ran (fresh shell / empty enter)
  local -i elapsed=$(( EPOCHSECONDS - _notify_start ))
  local bin=$_notify_bin
  _notify_start=0
  _notify_bin=''
  [[ -z $bin ]] && return
  (( ${NOTIFY_IGNORE[(Ie)$bin]} )) && return         # interactive / long-lived: skip
  local grp=${NOTIFY_GROUP[$bin]}
  if [[ -n $grp ]]; then
    (( code != 0 )) && grp=error
    notify_fire "$TMUX_PANE" "$grp"
    _notify_active=1
  elif (( elapsed >= NOTIFY_THRESHOLD )); then
    (( code != 0 )) && grp=error || grp=default
    notify_fire "$TMUX_PANE" "$grp"
    _notify_active=1
  fi
}

# Clear a process notification on the first keypress at the prompt (so you don't
# have to submit a whole command). Registered always; a near-free no-op unless a
# notification from this shell is active and you've started typing.
_notify_zle_clear() {
  if (( _notify_active )) && [[ -n $BUFFER ]]; then
    [[ -n "$TMUX_PANE" ]] && notify_clear "$TMUX_PANE"
    _notify_active=0
  fi
}

# Only wire up when the shared helpers actually loaded.
if typeset -f notify_fire >/dev/null 2>&1; then
  add-zsh-hook preexec _notify_preexec
  add-zsh-hook precmd  _notify_precmd
  add-zle-hook-widget line-pre-redraw _notify_zle_clear
fi
