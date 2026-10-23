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
  return 0
}

# notify_debug_on - true when debug logging is enabled. Lets callers gate
# expensive debug-only work (e.g. parsing a hook's JSON payload).
notify_debug_on() {
  _notify_log_init
  case "$_NOTIFY_DEBUG" in 1|true|yes|on|TRUE|True) return 0 ;; *) return 1 ;; esac
}

# _notify_log_write <message...> - append and rotate without checking debug.
_notify_log_write() {
  _notify_log_init
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

# notify_log <message...> - append only when debug logging is enabled.
notify_log() {
  _notify_log_init
  case "$_NOTIFY_DEBUG" in 1|true|yes|on|TRUE|True) ;; *) return 0 ;; esac
  _notify_log_write "$@"
}

# notify_log_always <message...> - record operational warnings even when a
# detached caller has no terminal and debug logging is disabled.
notify_log_always() {
  _notify_log_write "$@"
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
# $NOTIFY_SOUNDS overrides the sound directory, mirroring how $NOTIFY_CONFIG
# overrides the config path. Unset (the normal case) resolves to the installed
# ~/.config/notify/sounds. scripts/audition-sounds.sh points it at the chezmoi
# source tree so candidate sounds can be previewed through this exact code path
# - same player chain, same gain math - before they are applied.
notify_play() {
  [ -n "$1" ] || return 0
  local f="${NOTIFY_SOUNDS:-$HOME/.config/notify/sounds}/$1" vol="$2" afplay_bin mpg123_bin ffplay_bin vfrac
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

# --- OpenCode's own attention sound (used outside tmux) ------------------------

# _notify_json_str <string> -> the string as a JSON string literal. Escapes the
# only two characters a file path can plausibly need escaped.
_notify_json_str() {
  local s="$1" PATH="$PATH:$_NOTIFY_SYSPATH"
  case "$s" in
    *\\*|*\"*) s=$(printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g') ;;
  esac
  printf '"%s"' "$s"
}

# notify_attention_config
# Print the inline JSON that turns on OpenCode's native attention sound from
# notify.yaml, or print nothing (fail open) when it cannot be built. The tmux
# notifier is silent outside tmux, and OpenCode's own sound is what fills that gap,
# so the same groups and sound files apply:
#   done, default                 -> integrations.opencode.sound
#   subagent_done                 -> silence (the tmux notifier ignores child sessions
#                                    too, and a DAG run would chime per sub-agent)
#   permission, error             -> integrations.opencode_permission.sound
#   question                      -> integrations.opencode_question.sound
# Native sound paths are read as written (no ~ expansion), so they are absolute.
# A path that is missing or empty falls back to a SOUND BUNDLED with OpenCode, so
# silence cannot be expressed by leaving one out. An empty `sound:` therefore maps
# to the silent file shipped beside the other sounds, and so does a named file
# that does not exist, exactly as notify_play would stay quiet. If that file is
# missing the whole config is dropped, because silence could no longer be kept.
# Native volume is one global 0-1 value, not per event; it is the opencode
# integration's volume, else settings.volume, else 75 (0-100 scaled to 0-1).
# Notifications (system popups) are never touched.
notify_attention_config() {
  local dir="${NOTIFY_SOUNDS:-$HOME/.config/notify/sounds}" line rest done_s perm_s ques_s vol
  local silence p_done p_perm p_ques
  silence="$dir/silence.mp3"
  [ -f "$silence" ] || return 0
  line=$(_notify_yq '[ (.integrations.opencode.sound // ""),
    (.integrations.opencode_permission.sound // ""),
    (.integrations.opencode_question.sound // ""),
    (.integrations.opencode.volume // .settings.volume // 75) ] | join("|")')
  [ -n "$line" ] || return 0
  rest="$line"
  done_s=${rest%%|*}; rest=${rest#*|}
  perm_s=${rest%%|*}; rest=${rest#*|}
  ques_s=${rest%%|*}; vol=${rest#*|}
  case "$vol" in ''|*[!0-9]*) vol=75 ;; esac
  [ "$vol" -gt 100 ] 2>/dev/null && vol=100
  p_done="$dir/$done_s"; [ -n "$done_s" ] && [ -f "$p_done" ] || p_done="$silence"
  p_perm="$dir/$perm_s"; [ -n "$perm_s" ] && [ -f "$p_perm" ] || p_perm="$silence"
  p_ques="$dir/$ques_s"; [ -n "$ques_s" ] && [ -f "$p_ques" ] || p_ques="$silence"
  printf '{"attention":{"sound":true,"volume":%d.%02d,"sounds":{' "$((vol / 100))" "$((vol % 100))"
  printf '"default":%s,"done":%s,"subagent_done":%s,' \
    "$(_notify_json_str "$p_done")" "$(_notify_json_str "$p_done")" "$(_notify_json_str "$silence")"
  printf '"permission":%s,"error":%s,"question":%s' \
    "$(_notify_json_str "$p_perm")" "$(_notify_json_str "$p_perm")" "$(_notify_json_str "$p_ques")"
  printf '}}}\n'
}

# _notify_tint_apply <pane> <bg> <accent>
# The tmux writes that tint a pane: the @notify flag, the pane color, and the
# window-tab pill. Shared by notify_fire and notify_tint, so they cannot drift.
# Pane and window flags stay separate: pane options inherit window values, so
# writing @notify at window scope would mark every pane in a split layout.
_notify_tint_apply() {
  _notify_tmux \
    set-option -p -t "$1" @notify 1 \; \
    set-option -p -t "$1" @notify_accent "$3" \; \
    set-option -p -t "$1" window-style "bg=$2" \; \
    set-option -p -t "$1" window-active-style "bg=$2" \; \
    set-option -w -t "$1" @notify_window 1 \; \
    set-option -w -t "$1" @notify_window_accent "$3" 2>/dev/null
}

# notify_fire <pane id> <group name> [sound]
# A third argument of "sound" plays the group's sound and leaves tmux alone: no
# pane flag, no tint, no window flag, and no pane is needed. A caller uses it when
# the user is already looking at the pane. Any other third argument is ignored, so
# the two-argument call that the zsh notifier and the Claude and Codex hooks make
# is unchanged.
notify_fire() {
  local pane="$1" grp="$2" mode="${3:-}" line rest bg accent snd vol
  [ -n "$pane" ] || [ "$mode" = sound ] || return 0
  line=$(_notify_fire_attrs "$grp")
  # Split "bg|accent|sound|volume" via parameter expansion (no IFS, no subshell -
  # preserves an empty sound field and never disturbs the caller's IFS).
  rest="$line"
  bg=${rest%%|*};     rest=${rest#*|}
  accent=${rest%%|*}; rest=${rest#*|}
  snd=${rest%%|*};    rest=${rest#*|}
  vol=$rest
  [ -n "$vol" ] || vol=75
  if [ "$mode" = sound ]; then
    notify_log "sound-only group=$grp pane=${pane:-none} sound=${snd:-none} vol=$vol"
    notify_play "$snd" "$vol"
    return 0
  fi
  [ -n "$bg" ] || bg='#5b1a1a'
  [ -n "$accent" ] || accent='#ff5555'
  _notify_tint_apply "$pane" "$bg" "$accent"
  notify_log "fire pane=$pane group=$grp bg=$bg accent=$accent sound=${snd:-none} vol=$vol"
  notify_play "$snd" "$vol"
}

# --- Own and elsewhere tints (driven by the OpenCode TUI plugin) -----------------
# A pane can hold two independent states. The OWN tint is the viewed tab's own
# alert: the full group color, with @notify set, which is the flag the keypress
# binding tests before it clears. The ELSEWHERE tint means a different tab in this
# pane's OpenCode needs attention: a dimmed group color kept in
# @notify_elsewhere_bg/@notify_elsewhere_accent and shown on the window-tab pill.
# It never sets @notify, so a keypress, which clears only a pane whose @notify is
# set, cannot drop it. notify_clear re-applies it after an own clear. Claude,
# Codex and the zsh notifier never set either elsewhere option, so for them
# notify_clear is unchanged.

# _notify_ratio_permille <ratio> -> a 0..1000 integer. "0" is 0, "1" or more is
# 1000, a decimal in between keeps three places, and anything that is not a plain
# decimal means 0.5. Leading zeros are stripped so no shell reads the digits as octal.
_notify_ratio_permille() {
  local v="$1" ip fp
  case "$v" in
    ''|.|*[!0-9.]*|*.*.*) printf '500'; return 0 ;;
    *.*) ip=${v%%.*}; fp=${v#*.} ;;
    *) ip=$v; fp='' ;;
  esac
  while [ "${ip#0}" != "$ip" ]; do ip=${ip#0}; done
  [ -n "$ip" ] || ip=0
  if [ "${#ip}" -gt 1 ] || [ "$ip" != 0 ]; then printf '1000'; return 0; fi
  fp=$(printf '%.3s' "${fp}000")
  while [ "${fp#0}" != "$fp" ]; do fp=${fp#0}; done
  [ -n "$fp" ] || fp=0
  printf '%d' "$fp"
}

# _notify_permille_json <0..1000> -> a JSON number: 500 is 0.5, 1000 is 1, 0 is 0.
_notify_permille_json() {
  local p="$1" frac
  if [ "$p" -ge 1000 ]; then printf '1'; return 0; fi
  frac=$(printf '%03d' "$p")
  while [ "${frac%0}" != "$frac" ]; do frac=${frac%0}; done
  if [ -n "$frac" ]; then printf '0.%s' "$frac"; else printf '0'; fi
}

# notify_blend_hex <bg> <base> <ratio>
# Blend bg toward base. Ratio 0 is bg, 1 is base. Integer shell arithmetic only,
# so it gives the same answer in macOS /bin/bash 3.2, current bash, dash and zsh.
# A bg or base that is not #rrggbb (for example "default") returns bg unchanged.
notify_blend_hex() {
  local bg="$1" base="$2" p h1 h2 r1 g1 b1 r2 g2 b2
  case "$bg" in
    \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
    *) printf '%s' "$bg"; return 0 ;;
  esac
  case "$base" in
    \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
    *) printf '%s' "$bg"; return 0 ;;
  esac
  p=$(_notify_ratio_permille "$3")
  h1=${bg#\#}; h2=${base#\#}
  r1=${h1%????}; g1=${h1#??}; g1=${g1%??}; b1=${h1#????}
  r2=${h2%????}; g2=${h2#??}; g2=${g2%??}; b2=${h2#????}
  printf '#%02x%02x%02x' \
    "$(( (0x$r1 * (1000 - p) + 0x$r2 * p + 500) / 1000 ))" \
    "$(( (0x$g1 * (1000 - p) + 0x$g2 * p + 500) / 1000 ))" \
    "$(( (0x$b1 * (1000 - p) + 0x$b2 * p + 500) / 1000 ))"
}

# _notify_elsewhere_inputs -> "background|dim" as the config states them, either
# part empty when absent (an unreadable config gives an empty string).
_notify_elsewhere_inputs() {
  _notify_yq '[(.palette.background // ""), (.settings.elsewhere_dim // "")] | join("|")'
}

# _notify_elsewhere_attrs <group> -> "dimmed bg|accent". The dimmed bg is the group
# bg blended toward the palette background by settings.elsewhere_dim (default
# 0.5). With no config it is the same built-in fallback colors notify_fire uses,
# undimmed, so the tint still shows.
_notify_elsewhere_attrs() {
  local line rest bg accent inputs base dim
  line=$(_notify_fire_attrs "$1")
  bg=${line%%|*}; rest=${line#*|}; accent=${rest%%|*}
  [ -n "$bg" ] || bg='#5b1a1a'
  [ -n "$accent" ] || accent='#ff5555'
  inputs=$(_notify_elsewhere_inputs)
  base=${inputs%%|*}; dim=${inputs#*|}
  printf '%s|%s' "$(notify_blend_hex "$bg" "$base" "${dim:-0.5}")" "$accent"
}

# notify_tint <pane id> <group name>: the own tint. The tint half of notify_fire
# with no sound, and it leaves any stored elsewhere state as it is.
notify_tint() {
  local pane="$1" line rest bg accent
  [ -n "$pane" ] || return 0
  line=$(_notify_fire_attrs "$2")
  bg=${line%%|*}; rest=${line#*|}; accent=${rest%%|*}
  [ -n "$bg" ] || bg='#5b1a1a'
  [ -n "$accent" ] || accent='#ff5555'
  _notify_tint_apply "$pane" "$bg" "$accent"
  notify_log "tint own pane=$pane group=$2 bg=$bg accent=$accent"
}

# notify_tint_elsewhere <pane id> <group name>: another tab needs attention. Store
# the dimmed color and accent. If the pane has no own tint, show the dimmed color
# and set the window pill. An own tint already on screen is left alone, and
# @notify is never set.
notify_tint_elsewhere() {
  local pane="$1" line dim accent own
  [ -n "$pane" ] || return 0
  line=$(_notify_elsewhere_attrs "$2")
  dim=${line%%|*}; accent=${line#*|}
  _notify_tmux \
    set-option -p -t "$pane" @notify_elsewhere_bg "$dim" \; \
    set-option -p -t "$pane" @notify_elsewhere_accent "$accent" 2>/dev/null
  own=$(_notify_tmux display-message -p -t "$pane" '#{@notify}' 2>/dev/null)
  if [ -z "$own" ]; then
    _notify_tmux \
      set-option -p -t "$pane" window-style "bg=$dim" \; \
      set-option -p -t "$pane" window-active-style "bg=$dim" \; \
      set-option -w -t "$pane" @notify_window 1 \; \
      set-option -w -t "$pane" @notify_window_accent "$accent" 2>/dev/null
  fi
  notify_log "tint elsewhere pane=$pane group=$2 bg=$dim accent=$accent own=${own:-no}"
}

# notify_tint_clear <pane id>: drop the own AND the elsewhere state, restore the
# default pane color, and clear the pill unless another pane still needs it.
notify_tint_clear() {
  local pane="$1"
  [ -n "$pane" ] || return 0
  _notify_tmux \
    set-option -pu -t "$pane" @notify_elsewhere_bg \; \
    set-option -pu -t "$pane" @notify_elsewhere_accent 2>/dev/null
  notify_clear "$pane" tint-clear
}

# notify_describe: print, as one line of JSON, what the TUI plugin needs to draw
# its own indicators with the same colors: each OpenCode group's resolved colors,
# sound and volume, the elsewhere dim ratio and base color, and each group's
# dimmed background. Prints {} (and succeeds) when the config cannot be read.
notify_describe() {
  local inputs base dim p g line rest bg accent snd vol sep out_groups="" out_dim=""
  inputs=$(_notify_elsewhere_inputs)
  if [ -z "$inputs" ]; then printf '{}\n'; return 0; fi
  base=${inputs%%|*}; dim=${inputs#*|}
  p=$(_notify_ratio_permille "${dim:-0.5}")
  sep=""
  for g in opencode opencode_permission opencode_question; do
    line=$(_notify_fire_attrs "$g")
    rest="$line"
    bg=${rest%%|*};     rest=${rest#*|}
    accent=${rest%%|*}; rest=${rest#*|}
    snd=${rest%%|*};    vol=${rest#*|}
    case "$vol" in ''|*[!0-9]*) vol=75 ;; esac
    [ "$vol" -gt 100 ] 2>/dev/null && vol=100
    out_groups="$out_groups$sep\"$g\":{\"bg\":$(_notify_json_str "$bg"),\"accent\":$(_notify_json_str "$accent"),\"sound\":$(_notify_json_str "$snd"),\"volume\":$vol}"
    out_dim="$out_dim$sep\"$g\":$(_notify_json_str "$(notify_blend_hex "$bg" "$base" "${dim:-0.5}")")"
    sep=","
  done
  printf '{"groups":{%s},"elsewhere":{"dim":%s,"base":%s},"elsewhereBg":{%s}}\n' \
    "$out_groups" "$(_notify_permille_json "$p")" "$(_notify_json_str "$base")" "$out_dim"
}

# notify_clear <pane id> [reason]. Idempotent (unsetting an unset option is a
# no-op). The optional reason is only logged (debug), so we can tell which path
# cleared a pane - key, mouse, zle-keypress, preexec, claude-prompt, ...
# This clears the OWN tint. If the pane holds an elsewhere tint (see above), that
# one is put back as the pane color and keeps the pill. Claude, Codex and zsh never
# set one, so for them nothing changes.
notify_clear() {
  local pane="$1" reason="${2:-}" accent elbg PATH="$PATH:$_NOTIFY_SYSPATH"
  [ -n "$pane" ] || return 0
  elbg=$(_notify_tmux display-message -p -t "$pane" '#{@notify_elsewhere_bg}' 2>/dev/null)
  if [ -n "$elbg" ]; then
    _notify_tmux \
      set-option -p -t "$pane" window-style "bg=$elbg" \; \
      set-option -p -t "$pane" window-active-style "bg=$elbg" \; \
      set-option -p -t "$pane" @notify '' \; \
      set-option -p -t "$pane" @notify_accent '' 2>/dev/null
  else
    _notify_tmux \
      set-option -pu -t "$pane" window-style \; \
      set-option -pu -t "$pane" window-active-style \; \
      set-option -p  -t "$pane" @notify '' \; \
      set-option -p  -t "$pane" @notify_accent '' 2>/dev/null
  fi
  # Another pane in this window may still need attention, with an own tint or an
  # elsewhere one. Choose the first such pane's accent rather than dropping the
  # window-tab indicator.
  accent=$(_notify_tmux list-panes -t "$pane" -F '#{?@notify,#{@notify_accent},#{?@notify_elsewhere_bg,#{@notify_elsewhere_accent},}}' 2>/dev/null | grep -m 1 . || :)
  if [ -n "$accent" ]; then
    _notify_tmux set-option -w -t "$pane" @notify_window 1 \; \
      set-option -w -t "$pane" @notify_window_accent "$accent" 2>/dev/null
  else
    _notify_tmux set-option -w -t "$pane" @notify_window '' \; \
      set-option -w -t "$pane" @notify_window_accent '' 2>/dev/null
  fi
  notify_log "clear pane=$pane${reason:+ via $reason}"
  return 0
}
