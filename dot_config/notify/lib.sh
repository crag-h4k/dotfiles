# ~/.config/notify/lib.sh
# shellcheck shell=bash
# Shared, array-free helpers for the attention-notification system. Sourced by:
#   - the zsh process notifier  (~/.zsh/custom/functions/notify-process.zsh)
#   - the Claude/Codex hooks     (~/.claude/hooks/notify-*.sh)
# Everything configurable lives in ONE file, ~/.config/notify/notify.yaml
# (override with $NOTIFY_CONFIG), read here via mikefarah/yq. tmux never reads
# the config: notify_fire resolves a group's appearance and pushes per-pane
# runtime options that ~/.tmux/conf.d/notify.conf renders.
#
# Only function definitions at top level, and every function keeps its working
# variables `local`, so nothing leaks into the interactive zsh that sources
# this. The only process globals are the underscore-prefixed _NOTIFY_* memo
# caches, populated lazily. Targets macOS /bin/bash (3.2), Debian dash, and zsh:
# no arrays, no bashisms beyond `local` (which all three support).

# Standard system locations, appended (not prepended) to PATH inside the few
# functions that call external tools (grep, date, wc, ...). An event hook - e.g.
# Codex's notify program - can run with a stripped PATH; appending keeps the
# user's own tools first while still guaranteeing the base tools resolve. Scoped
# via `local PATH` per function so the interactive zsh that sources this is never
# affected. This is the same intent as the absolute fallbacks in _notify_tmux /
# _notify_yq_resolve / notify_play, generalized to the coreutils they rely on.
_NOTIFY_SYSPATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin'

_notify_config() {
  printf '%s' "${NOTIFY_CONFIG:-$HOME/.config/notify/notify.yaml}"
}

# Resolve a mikefarah yq once (memoized in _NOTIFY_YQ). Prefer ~/.local/bin/yq
# (where the Debian installer puts it), then PATH, then common absolute
# locations - so the Claude hooks find it under a stripped PATH, and a stray apt
# (python/kislyuk) yq earlier on PATH cannot silently shadow it and make the
# config unreadable. mikefarah's --version string contains "mikefarah".
_notify_yq_resolve() {
  [ -n "${_NOTIFY_YQ_READY:-}" ] && return 0
  _NOTIFY_YQ_READY=1
  _NOTIFY_YQ=''
  # Augment PATH so `command -v yq` and the `grep` validation below resolve even
  # when the caller (e.g. a Codex hook) runs with a stripped PATH.
  local c path_yq PATH="$PATH:$_NOTIFY_SYSPATH"
  path_yq=$(command -v yq 2>/dev/null)
  for c in "$HOME/.local/bin/yq" "$path_yq" /opt/homebrew/bin/yq /usr/local/bin/yq /usr/bin/yq; do
    [ -n "$c" ] || continue
    [ -x "$c" ] || continue
    "$c" --version 2>/dev/null | grep -qi mikefarah || continue
    _NOTIFY_YQ="$c"
    break
  done
}

# Run a yq expression against the config. Empty output on any error (no
# mikefarah yq, or missing config), so callers degrade to built-in defaults.
_notify_yq() {
  local cfg
  cfg=$(_notify_config)
  [ -f "$cfg" ] || return 0
  _notify_yq_resolve
  [ -n "$_NOTIFY_YQ" ] || return 0
  "$_NOTIFY_YQ" "$1" "$cfg" 2>/dev/null
}

_notify_tmux() {
  # Run tmux robustly: prefer PATH (and `command` to skip the OMZ tmux function
  # in interactive zsh), else fall back to common absolute locations.
  if command -v tmux >/dev/null 2>&1; then
    command tmux "$@"
  else
    local t
    for t in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux /bin/tmux; do
      if [ -x "$t" ]; then "$t" "$@"; return; fi
    done
    return 127
  fi
}

# --- Debug log (off unless settings.debug or $NOTIFY_DEBUG). Self-caps. -------

# Resolve debug + log path once per process (memoized in _NOTIFY_* internals).
# One yq call reads both; env vars NOTIFY_DEBUG / NOTIFY_LOG override the file.
_notify_log_init() {
  [ -n "${_NOTIFY_LOG_READY:-}" ] && return 0
  _NOTIFY_LOG_READY=1
  local cfgline stripped
  cfgline=$(_notify_yq '[(.settings.debug // false), (.settings.log // "")] | join("|")')
  _NOTIFY_DEBUG="${NOTIFY_DEBUG:-${cfgline%%|*}}"
  _NOTIFY_LOGFILE="${NOTIFY_LOG:-${cfgline#*|}}"
  [ -n "$_NOTIFY_LOGFILE" ] || _NOTIFY_LOGFILE="$HOME/.config/notify/notify.log"
  # Expand a literal leading ~ from the config value (it is data, not a shell
  # word, so the shell never expands it for us). Done with parameter expansion
  # rather than a ~ glob so it reads as a literal strip.
  if [ "$_NOTIFY_LOGFILE" = "~" ]; then
    _NOTIFY_LOGFILE="$HOME"
  else
    stripped=${_NOTIFY_LOGFILE#"~/"}
    [ "$stripped" != "$_NOTIFY_LOGFILE" ] && _NOTIFY_LOGFILE="$HOME/$stripped"
  fi
}

# notify_debug_on - true when debug logging is enabled. Lets callers gate
# expensive debug-only work (e.g. parsing a hook's JSON payload).
notify_debug_on() {
  _notify_log_init
  case "$_NOTIFY_DEBUG" in 1|true|yes|on|TRUE|True) return 0 ;; *) return 1 ;; esac
}

# notify_log <message...> - append a timestamped line when debugging. Rotates
# the log to <file>.old once it passes ~1 MB, so it can never grow unbounded.
notify_log() {
  _notify_log_init
  case "$_NOTIFY_DEBUG" in 1|true|yes|on|TRUE|True) ;; *) return 0 ;; esac
  # Resolve wc/tr/mv/dirname/mkdir/date under a possibly-stripped hook PATH.
  local f="$_NOTIFY_LOGFILE" sz d PATH="$PATH:$_NOTIFY_SYSPATH"
  if [ -f "$f" ]; then
    sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    [ -n "$sz" ] && [ "$sz" -gt 1048576 ] && mv -f "$f" "$f.old" 2>/dev/null
  fi
  d=$(dirname "$f"); [ -d "$d" ] || mkdir -p "$d" 2>/dev/null
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "${NOTIFY_SRC:-notify}" "$*" \
    >> "$f" 2>/dev/null
}

# --- Appearance + firing ------------------------------------------------------

# _notify_fire_attrs <group> -> "bg|accent|sound|volume" (palette names resolved
# to hex; raw #hex / 'default' pass through). Subshell keeps $_NG out of the env.
_notify_fire_attrs() (
  export _NG="$1"
  # The $g / env(_NG) below are yq syntax, not shell - intentionally unexpanded.
  # shellcheck disable=SC2016
  _notify_yq '
    (.groups[env(_NG)] // .integrations[env(_NG)] // {}) as $g
    | ($g.bg // "default") as $bgn
    | ($g.accent // "default") as $acn
    | [ (.palette[$bgn] // $bgn),
        (.palette[$acn] // $acn),
        ($g.sound // ""),
        ($g.volume // .settings.volume // 75) ]
    | join("|")
  '
)

# _notify_find <name> <abs fallback...> -> first runnable path, or empty. Mirrors
# _notify_tmux: an event hook (e.g. Codex's notify program) runs with a stripped
# PATH, so `command -v afplay` alone misses /usr/bin/afplay even though tmux still
# resolves via its own fallback - which is why the pane recolors but stays silent.
_notify_find() {
  local name="$1" p
  shift
  p=$(command -v "$name" 2>/dev/null)
  if [ -n "$p" ]; then printf '%s' "$p"; return 0; fi
  for p in "$@"; do
    if [ -x "$p" ]; then printf '%s' "$p"; return 0; fi
  done
}

# notify_play <sound-basename> <volume 0-100>. Empty/missing sound = silent.
notify_play() {
  [ -n "$1" ] || return 0
  local f="$HOME/.config/notify/sounds/$1" vol="$2" afplay_bin mpg123_bin ffplay_bin vfrac
  [ -f "$f" ] || return 0
  # Sanitize volume to an integer 0-100: reject anything non-numeric (fall back
  # to 75) and clamp the range.
  case "$vol" in ''|*[!0-9]*) vol=75 ;; esac
  [ "$vol" -gt 100 ] 2>/dev/null && vol=100
  # afplay wants a 0.0-1.0 gain. Compute it with shell arithmetic + the printf
  # builtin so notify_play needs no external (awk) on a stripped hook PATH.
  vfrac=$(printf '%d.%02d' "$((vol / 100))" "$((vol % 100))")
  afplay_bin=$(_notify_find afplay /usr/bin/afplay)
  mpg123_bin=$(_notify_find mpg123 /opt/homebrew/bin/mpg123 /usr/local/bin/mpg123 /usr/bin/mpg123)
  ffplay_bin=$(_notify_find ffplay /opt/homebrew/bin/ffplay /usr/local/bin/ffplay /usr/bin/ffplay)
  if [ -n "$afplay_bin" ]; then
    ( "$afplay_bin" -v "$vfrac" "$f" & ) >/dev/null 2>&1
    notify_log "play via $afplay_bin vol=$vol sound=$1"
  elif [ -n "$mpg123_bin" ]; then
    ( "$mpg123_bin" -q --volume "$vol" "$f" & ) >/dev/null 2>&1
    notify_log "play via $mpg123_bin vol=$vol sound=$1"
  elif [ -n "$ffplay_bin" ]; then
    ( "$ffplay_bin" -nodisp -autoexit -loglevel quiet -volume "$vol" "$f" & ) >/dev/null 2>&1
    notify_log "play via $ffplay_bin vol=$vol sound=$1"
  else
    notify_log "play NO-PLAYER-FOUND sound=$1 PATH=$PATH"
  fi
}

# notify_fire <pane id> <group name>
notify_fire() {
  local pane="$1" grp="$2" line rest bg accent snd vol
  [ -n "$pane" ] || return 0
  line=$(_notify_fire_attrs "$grp")
  # Split "bg|accent|sound|volume" via parameter expansion (no IFS, no subshell -
  # preserves an empty sound field and never disturbs the caller's IFS).
  rest="$line"
  bg=${rest%%|*};     rest=${rest#*|}
  accent=${rest%%|*}; rest=${rest#*|}
  snd=${rest%%|*};    rest=${rest#*|}
  vol=$rest
  [ -n "$bg" ] || bg='#5b1a1a'
  [ -n "$accent" ] || accent='#ff5555'
  [ -n "$vol" ] || vol=75
  # @notify drives the status-bar flag (pane + window scope); window-style
  # recolors the pane (visible on shell panes; hidden behind full-screen TUIs).
  _notify_tmux \
    set-option -p -t "$pane" @notify 1 \; \
    set-option -w -t "$pane" @notify 1 \; \
    set-option -p -t "$pane" @notify_accent "$accent" \; \
    set-option -w -t "$pane" @notify_accent "$accent" \; \
    set-option -p -t "$pane" window-style "bg=$bg" \; \
    set-option -p -t "$pane" window-active-style "bg=$bg" 2>/dev/null
  notify_log "fire pane=$pane group=$grp bg=$bg accent=$accent sound=${snd:-none} vol=$vol"
  notify_play "$snd" "$vol"
}

# notify_clear <pane id>. Idempotent (unsetting an unset option is a no-op).
notify_clear() {
  local pane="$1"
  [ -n "$pane" ] || return 0
  _notify_tmux \
    set-option -pu -t "$pane" window-style \; \
    set-option -pu -t "$pane" window-active-style \; \
    set-option -p  -t "$pane" @notify '' \; \
    set-option -w  -t "$pane" @notify '' \; \
    set-option -p  -t "$pane" @notify_accent '' \; \
    set-option -w  -t "$pane" @notify_accent '' 2>/dev/null
  notify_log "clear pane=$pane"
}
