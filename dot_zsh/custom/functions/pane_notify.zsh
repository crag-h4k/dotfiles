# pane_notify.zsh - visual "done" notifications, no audio.
#
# Two kinds of "done":
#   - Batch commands (make, pytest, ...): flagged when they finish and return to
#     the prompt, if they ran longer than PANE_NOTIFY_MIN.
#   - Interactive agents (claude, codex - PANE_NOTIFY_AGENTS): flagged inside tmux
#     when they go IDLE (done processing a message), via monitor-silence. They are
#     deliberately NOT flagged on exit - exiting the agent is not an event worth a
#     notification, and you are already looking at the pane.
# Channels are visual only: terminal title (OSC 2), background recolor (OSC 11),
# an inline banner line, and inside tmux the pane border (@done) + window flag
# (@notify). Acknowledge by running a command, pressing Enter at an empty prompt,
# or (tmux) focusing the pane.
#
# Config (override in ~/.zsh_private or before this loads):
#   PANE_NOTIFY_MIN=10            min command seconds before flagging completion
#   PANE_NOTIFY_IDLE=15           tmux: seconds of output silence -> idle flag
#   PANE_NOTIFY_AGENTS="claude codex"  commands flagged on idle, not on exit
#   PANE_NOTIFY_CHANNELS="title bg banner tmux"   channels to fire
#   PANE_NOTIFY_BG="#5b1a1a"      alert background color (OSC 11)
#   PANE_NOTIFY_REPEAT=0          re-assert every N seconds until ack; 0 = one-shot
#   PANE_NOTIFY_REPEAT_MAX=0      cap on repeats; 0 = until acknowledged

autoload -Uz add-zsh-hook

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
_pane_notify_agent=0
_pane_notify_active=0
_pane_notify_watcher=0

_pane_notify_has() { [[ " $PANE_NOTIFY_CHANNELS " == *" $1 "* ]] }

# True if the command name (basename of its first word) is an interactive agent.
_pane_notify_is_agent() { [[ " $PANE_NOTIFY_AGENTS " == *" ${1:t} "* ]] }

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

# Re-assertable visual state (everything except the one-shot banner line).
_pane_notify_apply() {
  local dur=$1
  _pane_notify_has title && _pane_notify_osc "\033]2;● done (${dur}s) ${_pane_notify_cmd}\007"
  _pane_notify_has bg && _pane_notify_osc "\033]11;${PANE_NOTIFY_BG}\007"
  if [[ -n $TMUX ]] && _pane_notify_has tmux; then
    tmux set -p @done 1 2>/dev/null
    tmux set -w @notify 1 2>/dev/null
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
  _pane_notify_has bg && _pane_notify_osc "\033]111\007"
  _pane_notify_has title && _pane_notify_osc "\033]2;${PWD/#$HOME/~}\007"
  if [[ -n $TMUX ]] && _pane_notify_has tmux; then
    tmux set -p @done "" 2>/dev/null
    tmux set -w @notify "" 2>/dev/null
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
        _pane_notify_has bg && _pane_notify_osc "\033]11;${PANE_NOTIFY_BG}\007"
        if [[ -n $TMUX ]] && _pane_notify_has tmux; then
          tmux set -p @done 1 2>/dev/null
          tmux set -w @notify 1 2>/dev/null
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
  _pane_notify_cmd="${1%% *}"
  # Only watch for idle on interactive agents; batch commands flag on completion.
  if [[ -n $TMUX ]] && _pane_notify_is_agent "$_pane_notify_cmd"; then
    _pane_notify_agent=1
    tmux setw monitor-silence "$PANE_NOTIFY_IDLE" 2>/dev/null
  else
    _pane_notify_agent=0
  fi
}

_pane_notify_precmd() {
  local code=$?
  # Back at the prompt = you are looking at this pane: stop watching and clear any
  # idle flag (this is what suppresses the "red on claude exit").
  if [[ -n $TMUX ]]; then
    tmux setw monitor-silence 0 2>/dev/null
    tmux set -p @done "" 2>/dev/null
    tmux set -w @notify "" 2>/dev/null
  fi
  if (( _pane_notify_start > 0 )); then
    local dur=$(( SECONDS - _pane_notify_start )) was_agent=$_pane_notify_agent
    _pane_notify_start=0
    _pane_notify_agent=0
    # Agents are flagged on idle (while running), never on exit. Batch commands
    # flag on completion if they ran long enough.
    (( ! was_agent && dur >= PANE_NOTIFY_MIN )) && _pane_notify_fire "$dur" "$code"
  else
    _pane_notify_clear          # bare Enter at an idle prompt = acknowledge
  fi
}

add-zsh-hook preexec _pane_notify_preexec
add-zsh-hook precmd _pane_notify_precmd
add-zsh-hook zshexit _pane_notify_clear
