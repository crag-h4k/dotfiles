# ~/.zsh/custom/functions/notify-process.zsh
# Process-completion attention notifications, unified with the Claude/Codex hooks
# via ~/.config/notify/lib.sh. This file owns only the detection LOGIC (resolve
# the significant binary of a command line, time it, decide whether to fire). All
# the data - which binaries map to which group, per-group thresholds, the ignore
# list - lives in ~/.config/notify/notify.yaml and is loaded once below with a
# single yq call at shell init. Appearance/sound for a group are resolved by
# notify_fire from the same file; nothing about colors lives here.

autoload -Uz add-zsh-hook add-zle-hook-widget
zmodload zsh/datetime 2>/dev/null

# Shared, array-free helpers: notify_fire / notify_clear / notify_play / notify_log.
if ! typeset -f notify_fire >/dev/null 2>&1; then
  [[ -r ~/.config/notify/lib.sh ]] && source ~/.config/notify/lib.sh
fi

# --- Config-driven tables, built once at init from notify.yaml ----------------
# NOTIFY_GROUP[bin]=group, NOTIFY_THRESHOLD[group]=seconds, NOTIFY_IGNORE=(...),
# NOTIFY_DEFAULT_THRESHOLD=settings.threshold. One yq call emits prefixed lines:
#   T <default-threshold> | I <ignored-binary> | B <binary> <group> | G <group> <threshold>
typeset -gA NOTIFY_GROUP NOTIFY_THRESHOLD
typeset -ga NOTIFY_IGNORE
typeset -gi NOTIFY_DEFAULT_THRESHOLD=30
NOTIFY_GROUP=() NOTIFY_THRESHOLD=() NOTIFY_IGNORE=()

_notify_load_config() {
  emulate -L zsh
  local cfg="${NOTIFY_CONFIG:-$HOME/.config/notify/notify.yaml}"
  [[ -r $cfg ]] || return
  # Use the mikefarah yq the lib resolves (prefers ~/.local/bin/yq; ignores a
  # stray apt/kislyuk yq). Warn once per interactive shell if none is available.
  typeset -f _notify_yq_resolve >/dev/null || return
  _notify_yq_resolve
  if [[ -z $_NOTIFY_YQ ]]; then
    [[ -o interactive ]] && print -u2 "notify: mikefarah yq not found - notifications disabled (install yq or run the dotfiles installer)."
    return
  fi
  local kind a b
  while read -r kind a b; do
    case $kind in
      T) NOTIFY_DEFAULT_THRESHOLD=$a ;;
      I) [[ -n $a ]] && NOTIFY_IGNORE+=($a) ;;
      B) [[ -n $a ]] && NOTIFY_GROUP[$a]=$b ;;
      G) [[ -n $a ]] && NOTIFY_THRESHOLD[$a]=$b ;;
    esac
  done < <("$_NOTIFY_YQ" '
    ( "T " + ((.settings.threshold // 0) | tostring) ),
    ( (.settings.ignore // [])[] | "I " + . ),
    ( (.integrations // {} | keys[]) | "I " + . ),
    ( .groups | to_entries[] | .key as $g | (.value.binaries // [])[] | "B " + . + " " + $g ),
    ( (.settings.threshold // 0) as $d | .groups | to_entries[] | "G " + .key + " " + ((.value.threshold // $d) | tostring) )
  ' $cfg 2>/dev/null)
}
_notify_load_config

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
  local grp=${NOTIFY_GROUP[$bin]} thr
  if [[ -n $grp ]]; then
    # Named binary: fire once it has run at least its group's threshold (0 = always).
    thr=${NOTIFY_THRESHOLD[$grp]:-$NOTIFY_DEFAULT_THRESHOLD}
    (( elapsed >= thr )) || return
    (( code != 0 )) && grp=error
  else
    # Unmatched: catch-all 'default' group, gated by the default group's threshold.
    thr=${NOTIFY_THRESHOLD[default]:-$NOTIFY_DEFAULT_THRESHOLD}
    (( elapsed >= thr )) || return
    (( code != 0 )) && grp=error || grp=default
  fi
  notify_fire "$TMUX_PANE" "$grp"
  _notify_active=1
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
