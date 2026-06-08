# pane_notify.zsh - visual "done" notifications, no audio.
#
# Two kinds of "done":
#   - Allowlisted commands (PANE_NOTIFY_ALLOW, e.g. make/pytest/terraform):
#     flagged when they finish and return to the prompt, if they ran at least
#     PANE_NOTIFY_MIN seconds. Anything not on the allowlist is silent - so
#     interactive programs you quit (vim, less, ssh) never flag on exit.
#   - Interactive agents (claude, codex - PANE_NOTIFY_AGENTS): flagged inside tmux
#     when they go IDLE (done processing a message), via monitor-silence. They are
#     deliberately NOT flagged on exit - exiting the agent is not an event worth a
#     notification, and you are already looking at the pane.
# Channels are visual only (no bell). Inside tmux: the pane background recolors
# (window-style) plus a pane-border marker (@done) and window tab flag (@notify).
# Outside tmux: terminal title (OSC 2) + background recolor (OSC 11) + an inline
# banner line. Acknowledge by running a command, pressing Enter at an empty
# prompt, or (tmux) focusing the pane.
#
# Command matching is alias-aware: the typed command is alias-resolved to its
# underlying name (e.g. `tf` -> `terraform`) before checking the agent/allow
# lists. All tmux calls from these hooks target -t "$TMUX_PANE" so they act on the
# pane that ran the command, not whatever window tmux currently considers active.
#
# Config (override in ~/.zsh_private or before this loads):
#   PANE_NOTIFY_ALLOW="make pytest ..."  ONLY these commands flag on completion
#   PANE_NOTIFY_MIN=10            min command seconds before flagging completion
#   PANE_NOTIFY_IDLE=15           tmux: seconds of output silence -> idle flag
#   PANE_NOTIFY_AGENTS="claude codex"  commands flagged on idle, not on exit
#   PANE_NOTIFY_CHANNELS="title bg banner tmux"   channels to fire
#   PANE_NOTIFY_BG="#5b1a1a"      alert background color (OSC 11)
#   PANE_NOTIFY_REPEAT=0          re-assert every N seconds until ack; 0 = one-shot
#   PANE_NOTIFY_REPEAT_MAX=0      cap on repeats; 0 = until acknowledged

autoload -Uz add-zsh-hook

# Allowlist: only these commands raise a completion notification. Everything else
# (vim, less, ssh, git, ...) is silent. Edit in ~/.zsh_private to taste.
: ${PANE_NOTIFY_ALLOW:="make pytest tox go cargo npm pnpm yarn terraform tf tofu ansible-playbook docker docker-compose rsync gradlew mvn brew gh pre-commit"}
: ${PANE_NOTIFY_MIN:=10}
: ${PANE_NOTIFY_IDLE:=15}
: ${PANE_NOTIFY_AGENTS:="claude codex"}
: ${PANE_NOTIFY_CHANNELS:="title bg banner tmux"}
: ${PANE_NOTIFY_BG:="#5b1a1a"}
: ${PANE_NOTIFY_REPEAT:=0}
: ${PANE_NOTIFY_REPEAT_MAX:=0}

_pane_notify_dir="$HOME/.cache/pane-notify"
_pane_notify_start=0
_pane_notify_cmd=""
_pane_notify_name=""
_pane_notify_agent=0
_pane_notify_active=0
_pane_notify_watcher=0

_pane_notify_has() { [[ " $PANE_NOTIFY_CHANNELS " == *" $1 "* ]] }

# First real command word in a typed line, skipping common prefixes.
_pane_notify_firstword() {
  local -a w=(${(z)1})
  while (( $#w )); do
    case $w[1] in
      sudo|command|builtin|noglob|nocorrect|time|env|*=*) shift w ;;
      *) break ;;
    esac
  done
  print -r -- $w[1]
}

# Resolve one alias level, returning the underlying command basename. So a typed
# `tf` (alias for terraform) matches `terraform` in the lists; functions that are
# not aliases fall through to their own name.
_pane_notify_resolve() {
  local word=$1
  (( $+aliases[$word] )) && word=${aliases[$word]%% *}
  print -r -- ${word:t}
}

# Match the resolved command name against a space-padded list.
_pane_notify_is_agent() { [[ " $PANE_NOTIFY_AGENTS " == *" $1 "* ]] }
_pane_notify_is_allowed() { [[ " $PANE_NOTIFY_ALLOW " == *" $1 "* ]] }

_pane_notify_ackfile() {
  if [[ -n $TMUX ]]; then
    print -r -- "$_pane_notify_dir/$TMUX_PANE"
  else
    print -r -- "$_pane_notify_dir/tty$(tty 2>/dev/null | tr -dc 'A-Za-z0-9')"
  fi
}

# Write an escape sequence to the controlling terminal (no-op without a tty).
# Group-redirect so a failed open of /dev/tty stays quiet too.
_pane_notify_osc() { { printf '%b' "$1" >/dev/tty } 2>/dev/null; return 0 }

# Mark / unmark THIS pane inside tmux: border (@done) + tab flag (@notify) and,
# when the bg channel is on, recolor the pane background. Both window-style
# (inactive panes, i.e. splits) and window-active-style (the active/lone pane)
# are set so the recolor shows in every layout. All targeted at $TMUX_PANE.
_pane_notify_tmux_mark() {
  tmux set -t "$TMUX_PANE" -p @done 1 2>/dev/null
  tmux set -t "$TMUX_PANE" -w @notify 1 2>/dev/null
  if _pane_notify_has bg; then
    tmux set -t "$TMUX_PANE" -p window-style "bg=${PANE_NOTIFY_BG}" 2>/dev/null
    tmux set -t "$TMUX_PANE" -p window-active-style "bg=${PANE_NOTIFY_BG}" 2>/dev/null
  fi
}
_pane_notify_tmux_unmark() {
  tmux set -t "$TMUX_PANE" -p @done "" 2>/dev/null
  tmux set -t "$TMUX_PANE" -w @notify "" 2>/dev/null
  tmux set -t "$TMUX_PANE" -pu window-style 2>/dev/null
  tmux set -t "$TMUX_PANE" -pu window-active-style 2>/dev/null
}

# Re-assertable visual state (everything except the one-shot banner line).
# Inside tmux: pane border (@done) + tab flag (@notify) + pane background recolor
# (window-style), all targeted at this pane. Outside tmux: OSC title + background.
_pane_notify_apply() {
  local dur=$1
  if [[ -n $TMUX ]]; then
    _pane_notify_has tmux && _pane_notify_tmux_mark
  else
    _pane_notify_has title && _pane_notify_osc "\033]2;● done (${dur}s) ${_pane_notify_cmd}\007"
    _pane_notify_has bg && _pane_notify_osc "\033]11;${PANE_NOTIFY_BG}\007"
  fi
}

_pane_notify_clear() {
  (( _pane_notify_active )) || return 0
  _pane_notify_active=0
  rm -f "$(_pane_notify_ackfile)" 2>/dev/null
  if (( _pane_notify_watcher )); then
    kill "$_pane_notify_watcher" 2>/dev/null
    _pane_notify_watcher=0
  fi
  if [[ -n $TMUX ]]; then
    _pane_notify_has tmux && _pane_notify_tmux_unmark
  else
    _pane_notify_has bg && _pane_notify_osc "\033]111\007"
    _pane_notify_has title && _pane_notify_osc "\033]2;${PWD/#$HOME/~}\007"
  fi
}

_pane_notify_fire() {
  local dur=$1 code=$2
  _pane_notify_active=1
  if _pane_notify_has banner; then
    if (( code == 0 )); then
      print -P "%F{green}✓ done in ${dur}s%f %F{8}(${_pane_notify_cmd})%f"
    else
      print -P "%F{red}✗ failed (exit ${code}) after ${dur}s%f %F{8}(${_pane_notify_cmd})%f"
    fi
  fi
  _pane_notify_apply "$dur"
  # Opt-in repeat: a disowned watcher re-asserts until the ack-file is removed.
  if (( PANE_NOTIFY_REPEAT > 0 )); then
    mkdir -p "$_pane_notify_dir" 2>/dev/null
    local ack; ack=$(_pane_notify_ackfile)
    : >"$ack"
    (
      local n=0
      while [[ -e $ack ]]; do
        sleep "$PANE_NOTIFY_REPEAT"
        [[ -e $ack ]] || break
        if [[ -n $TMUX ]]; then
          _pane_notify_has tmux && _pane_notify_tmux_mark
        else
          _pane_notify_has bg && _pane_notify_osc "\033]11;${PANE_NOTIFY_BG}\007"
        fi
        (( n++ ))
        (( PANE_NOTIFY_REPEAT_MAX > 0 && n >= PANE_NOTIFY_REPEAT_MAX )) && break
      done
    ) &!
    _pane_notify_watcher=$!
  fi
}

_pane_notify_preexec() {
  _pane_notify_clear            # starting a command acknowledges any prior signal
  _pane_notify_start=$SECONDS
  local first; first=$(_pane_notify_firstword "$1")
  _pane_notify_cmd=$first                          # typed name (for display)
  _pane_notify_name=$(_pane_notify_resolve "$first")  # alias-resolved (for matching)
  # Only watch for idle on interactive agents; batch commands flag on completion.
  if [[ -n $TMUX ]] && _pane_notify_is_agent "$_pane_notify_name"; then
    _pane_notify_agent=1
    tmux setw -t "$TMUX_PANE" monitor-silence "$PANE_NOTIFY_IDLE" 2>/dev/null
  else
    _pane_notify_agent=0
  fi
}

_pane_notify_precmd() {
  local code=$?
  # Back at the prompt = you are looking at this pane: stop watching and clear any
  # idle flag (this is what suppresses the "red on claude exit").
  if [[ -n $TMUX ]]; then
    tmux setw -t "$TMUX_PANE" monitor-silence 0 2>/dev/null
    _pane_notify_tmux_unmark
  fi
  if (( _pane_notify_start > 0 )); then
    local dur=$(( SECONDS - _pane_notify_start )) was_agent=$_pane_notify_agent
    _pane_notify_start=0
    _pane_notify_agent=0
    # Agents flag on idle (while running), never on exit. Everything else flags on
    # completion only if it is allowlisted and ran long enough.
    if (( ! was_agent && dur >= PANE_NOTIFY_MIN )) && _pane_notify_is_allowed "$_pane_notify_name"; then
      _pane_notify_fire "$dur" "$code"
    fi
  else
    _pane_notify_clear          # bare Enter at an idle prompt = acknowledge
  fi
}

add-zsh-hook preexec _pane_notify_preexec
add-zsh-hook precmd _pane_notify_precmd
add-zsh-hook zshexit _pane_notify_clear
