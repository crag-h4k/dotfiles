#!/usr/bin/env bash
# ~/.claude/statusline-command.sh
# gud (Dracula-family) statusline for Claude Code. Fast renderer: one jq spawn off
# stdin, integer math in bash, no per-render token walk. The subagent-inclusive
# cumulative total is served from a cache file that a detached Python updater
# (~/.claude/statusline-tokens.py) refreshes off the critical path, so render stays
# flat regardless of transcript length.
#
# Colors are emitted as SGR ANSI codes (never hex) so gud-theme.conf resolves them.
# Orange is the one hue ANSI 16 cannot carry in gud; it is sourced once from
# ~/.config/statusline/gud-palette.sh as GUD_ORANGE. macOS ships bash 3.2, so
# glyphs are ANSI-C byte escapes ($'\xHH...') and there is no printf '\U' or flock.
#
# stdin schema: https://code.claude.com/docs/en/statusline
set -u

# --- palette (SGR) ---------------------------------------------------------
RESET=$'\e[0m'
PURPLE=$'\e[34m'     # ANSI 4  -> gud #BD93F9  (model)
CYAN=$'\e[36m'       # ANSI 6  -> gud #8BE9FD  (total)
GREY=$'\e[90m'       # ANSI 8  -> gud #555555  (labels, separators, empty track)
PINK=$'\e[35m'       # ANSI 5  -> gud #FF79C6  (5h rate; gud has no blue slot)
GREEN=$'\e[32m'      # ANSI 2  -> gud #50FA7B
YELLOW=$'\e[33m'     # ANSI 3  -> gud #F1FA8C
RED=$'\e[31m'        # ANSI 1  -> gud #FF5555
RED_BOLD=$'\e[1;31m' # ANSI 1 bold
PALETTE="$HOME/.config/statusline/gud-palette.sh"
# shellcheck source=/dev/null
[ -r "$PALETTE" ] && . "$PALETTE"
[ -n "${GUD_ORANGE:-}" ] || GUD_ORANGE=$'\e[38;2;255;184;108m'
ORANGE="$GUD_ORANGE"

# --- glyphs (Nerd Font; one swappable block) -------------------------------
# Each is the UTF-8 byte sequence for the codepoint named. If any renders as a
# tofu box, your terminal font is not a Nerd Font (v3) patched font; swap the
# codepoint here and nowhere else.
G_ROBOT=$'\xf3\xb0\x9a\xa9'   # U+F06A9 nf-md-robot          (model)
G_GAUGE=$'\xef\x83\xa4'       # U+F0E4  nf-fa-tachometer     (context)
G_CLOCK=$'\xef\x80\x97'       # U+F017  nf-fa-clock-o        (duration)
G_TIMER=$'\xef\x89\x92'       # U+F252  nf-fa-hourglass-half (5h rate)
G_CAL=$'\xef\x81\xb3'         # U+F073  nf-fa-calendar       (weekly rate)
G_BRANCH=$'\xee\x82\xa0'      # U+E0A0  powerline branch     (git)
G_SIGMA=$'\xce\xa3'           # U+03A3  greek capital sigma  (total)
G_SEP=$'\xe2\x94\x82'         # U+2502  box drawings light vertical (separator)
G_BLOCK=$'\xe2\x96\x88'       # U+2588  full block           (bar cell)
G_DOT=$'\xe2\x97\x8f'         # U+25CF  black circle         (dirty marker)
G_MIDDOT=$'\xc2\xb7'          # U+00B7  middle dot           (intra-group sep)

# --- stdin: single jq spawn ------------------------------------------------
# jq reads the script's stdin directly via process substitution: no `cat`, no
# `printf | jq` pipe, no command-substitution subshell. One fork total.
model=""; pct=""; used=""; maxw=""; dur_ms=""; r5=""; r7=""; sid=""; tpath=""; dir="$PWD"
if command -v jq >/dev/null 2>&1; then
  # Fields are joined with US (unit separator, \x1f), NOT tab: tab is IFS
  # whitespace, so `read` would collapse consecutive empty fields (absent
  # rate_limits) and shift every value left. \x1f is non-whitespace, so empty
  # fields are preserved and the rate segments hide correctly when absent.
  IFS=$'\x1f' read -r model pct used maxw dur_ms r5 r7 sid tpath dir < <(
    jq -r '[
      (.model.display_name // ""),
      (.context_window.used_percentage // ""),
      (.context_window.total_input_tokens // ""),
      (.context_window.context_window_size // ""),
      (.cost.total_duration_ms // ""),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.seven_day.used_percentage // ""),
      (.session_id // ""),
      (.transcript_path // ""),
      (.workspace.current_dir // .cwd // "")
    ] | map(tostring) | join("\u001f")' 2>/dev/null)
  [ -n "$dir" ] || dir="$PWD"
else
  model=$(sed -n 's/.*"display_name":"\([^"]*\)".*/\1/p')
fi

# --- helpers (set globals, no subshell forks in the hot path) --------------
FMT_OUT=""
fmt_h() { # human number: 940 / 94k / 94.5k / 1.2M / 11.7B
  local n=$1
  case $n in ''|*[!0-9]*) FMT_OUT=""; return;; esac
  if [ "$n" -lt 1000 ]; then FMT_OUT="$n"
  elif [ "$n" -lt 1000000 ]; then
    local w=$((n/1000)) f=$(((n%1000)/100))
    if [ "$f" -eq 0 ]; then FMT_OUT="${w}k"; else FMT_OUT="${w}.${f}k"; fi
  elif [ "$n" -lt 1000000000 ]; then
    local w=$((n/1000000)) f=$(((n%1000000)/100000))
    if [ "$f" -eq 0 ]; then FMT_OUT="${w}M"; else FMT_OUT="${w}.${f}M"; fi
  else
    local w=$((n/1000000000)) f=$(((n%1000000000)/100000000))
    if [ "$f" -eq 0 ]; then FMT_OUT="${w}B"; else FMT_OUT="${w}.${f}B"; fi
  fi
}

RAMP_OUT=""
ramp() { # threshold color for a 0-100 value
  local p=$1
  if   [ "$p" -lt 50 ]; then RAMP_OUT="$GREEN"
  elif [ "$p" -lt 75 ]; then RAMP_OUT="$YELLOW"
  elif [ "$p" -lt 90 ]; then RAMP_OUT="$ORANGE"
  else RAMP_OUT="$RED_BOLD"; fi
}

BAR_OUT=""
make_bar() { # $1 pct(int) $2 width $3 fill-color  -> bracketed bar
  local p=$1 w=$2 color=$3 filled empty i out
  filled=$(( (p*w + 50)/100 ))
  [ "$filled" -gt "$w" ] && filled=$w
  [ "$filled" -lt 0 ] && filled=0
  empty=$(( w - filled ))
  out="["
  if [ "$filled" -gt 0 ]; then
    out="$out$color"
    i=0; while [ "$i" -lt "$filled" ]; do out="$out$G_BLOCK"; i=$((i+1)); done
    out="$out$RESET"
  fi
  if [ "$empty" -gt 0 ]; then
    out="$out$GREY"
    i=0; while [ "$i" -lt "$empty" ]; do out="$out$G_BLOCK"; i=$((i+1)); done
    out="$out$RESET"
  fi
  BAR_OUT="$out]"
}

# --- adaptive width --------------------------------------------------------
# Claude Code >= 2.1.153 exports COLUMNS/LINES to the statusline command. Its
# stdout is captured (so `tput cols` / `stty size` see no tty) and the stdin JSON
# carries no width, so $COLUMNS is the only width signal: read it and pick a
# layout tier. Absent (older Claude Code, a pipe test, a non-interactive caller)
# falls back to MED, which mirrors the previous fixed layout.
cols=${COLUMNS:-0}; case $cols in ''|*[!0-9]*) cols=0;; esac

# Per-tier tunables (one-line swaps): context-bar width, rate-bar width, the
# (used/max) detail, the duration segment, the rate segments, and the padding
# around the group divider. Bars widen and low-priority segments drop as space
# shrinks; the no-width default is MED.
if   [ "$cols" -ge 115 ]; then ctxw=16; ratew=12; show_detail=1; show_dur=1; show_rate=1; gpad="   "
elif [ "$cols" -ge 80 ] || [ "$cols" -eq 0 ]; then ctxw=10; ratew=8; show_detail=1; show_dur=1; show_rate=1; gpad="  "
elif [ "$cols" -ge 55 ]; then ctxw=8; ratew=6; show_detail=0; show_dur=1; show_rate=1; gpad=" "
else ctxw=6; ratew=6; show_detail=0; show_dur=0; show_rate=0; gpad=" "
fi

# Separators, SGR grey so the terminal theme still owns the hue. GSEP divides the
# logical groups; GDOT separates items inside a group (swap either glyph here).
GSEP="${GREY}${gpad}${G_SEP}${gpad}${RESET}"
GDOT="${GREY} ${G_MIDDOT} ${RESET}"

# --- build each segment (any may stay empty) -------------------------------
model_seg=""; ctx_seg=""; total_seg=""; dur_seg=""; r5_seg=""; r7_seg=""; git_seg=""

# Model (purple glyph, default-fg text)
[ -n "$model" ] && model_seg="${PURPLE}${G_ROBOT}${RESET} ${model}"

# Context: grey gauge + threshold bar + pct (+ used/max at wider tiers)
if [ -n "$pct" ]; then
  pint=${pct%%.*}; case $pint in ''|*[!0-9]*) pint=0;; esac
  ramp "$pint"; make_bar "$pint" "$ctxw" "$RAMP_OUT"
  ctx_seg="${GREY}${G_GAUGE}${RESET} ${BAR_OUT} ${pint}%"
  if [ "$show_detail" -eq 1 ]; then
    fmt_h "$used"; uh="$FMT_OUT"; fmt_h "$maxw"; mh="$FMT_OUT"
    [ -n "$uh" ] && [ -n "$mh" ] && ctx_seg="$ctx_seg (${uh}/${mh})"
  fi
fi

# Total (cyan sigma) from the cached, subagent-inclusive walk
cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
total_h="..."
if [ -n "$sid" ]; then
  totalfile="$cachedir/$sid.total"
  if [ -r "$totalfile" ]; then
    read -r total_raw < "$totalfile" 2>/dev/null || total_raw=""
    fmt_h "$total_raw"; [ -n "$FMT_OUT" ] && total_h="$FMT_OUT"
  fi
fi
total_seg="${CYAN}${G_SIGMA} ${total_h}${RESET}"

# Duration from cost.total_duration_ms (grey), dropped at the tiny tier
if [ "$show_dur" -eq 1 ] && [ -n "$dur_ms" ]; then
  case $dur_ms in *[!0-9]*) dur_ms="";; esac
fi
if [ "$show_dur" -eq 1 ] && [ -n "$dur_ms" ]; then
  s=$((dur_ms/1000)); h=$((s/3600)); m=$(((s%3600)/60))
  if [ "$h" -gt 0 ]; then dfmt=$(printf '%dh%02dm' "$h" "$m"); else dfmt="${m}m"; fi
  dur_seg="${GREY}${G_CLOCK}${RESET} ${dfmt}"
fi

# Rate 5h (pink) / weekly (orange) - only when rate_limits present and tier allows
if [ "$show_rate" -eq 1 ] && [ -n "$r5" ]; then
  r5i=${r5%%.*}; case $r5i in ''|*[!0-9]*) r5i=0;; esac
  ramp "$r5i"; make_bar "$r5i" "$ratew" "$RAMP_OUT"
  r5_seg="${PINK}${G_TIMER}${RESET} 5h ${BAR_OUT} ${r5i}%"
fi
if [ "$show_rate" -eq 1 ] && [ -n "$r7" ]; then
  r7i=${r7%%.*}; case $r7i in ''|*[!0-9]*) r7i=0;; esac
  ramp "$r7i"; make_bar "$r7i" "$ratew" "$RAMP_OUT"
  r7_seg="${ORANGE}${G_CAL}${RESET} wk ${BAR_OUT} ${r7i}%"
fi

# Git: branch via one porcelain=v2 spawn; green clean / yellow dirty + red dot
if [ -n "$dir" ] && [ -d "$dir" ]; then
  raw=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" status --porcelain=v2 --branch --untracked-files=no 2>/dev/null)
  if [ -n "$raw" ]; then
    branch=""; oid=""; dirty=0
    while IFS= read -r line; do
      case $line in
        "# branch.head "*) branch=${line#\# branch.head } ;;
        "# branch.oid "*)  oid=${line#\# branch.oid } ;;
        "#"*) : ;;
        ?*) dirty=1 ;;
      esac
    done <<EOF
$raw
EOF
    [ "$branch" = "(detached)" ] && branch=$(printf '%s' "$oid" | cut -c1-7)
    if [ -n "$branch" ]; then
      if [ "$dirty" -eq 1 ]; then
        git_seg="${YELLOW}${G_BRANCH} ${branch}${RESET} ${RED}${G_DOT}${RESET}"
      else
        git_seg="${GREEN}${G_BRANCH} ${branch}${RESET}"
      fi
    fi
  fi
fi

# --- compose groups, then join groups with the heavier divider -------------
# Grouping clusters related info so the line reads in chunks, not one long run:
#   identity (model, context)  usage (total, duration)  limits (5h, weekly)  git
# Items inside a group join with GDOT; groups join with GSEP.
g1=""; g2=""; g3=""; g4="$git_seg"
for s in "$model_seg" "$ctx_seg"; do
  [ -n "$s" ] || continue
  if [ -n "$g1" ]; then g1="$g1$GDOT$s"; else g1="$s"; fi
done
for s in "$total_seg" "$dur_seg"; do
  [ -n "$s" ] || continue
  if [ -n "$g2" ]; then g2="$g2$GDOT$s"; else g2="$s"; fi
done
for s in "$r5_seg" "$r7_seg"; do
  [ -n "$s" ] || continue
  if [ -n "$g3" ]; then g3="$g3$GDOT$s"; else g3="$s"; fi
done

out=""
for g in "$g1" "$g2" "$g3" "$g4"; do
  [ -n "$g" ] || continue
  if [ -z "$out" ]; then out="$g"; else out="$out$GSEP$g"; fi
done
printf '%s\n' "$out"

# --- kick the detached updater (never blocks render) -----------------------
# Portable lock is a directory the Python updater creates atomically (no flock on
# macOS). Skip the spawn when a fresh lock exists; the updater steals a stale one.
if [ -n "$sid" ] && [ -n "$tpath" ] && [ -f "$tpath" ]; then
  totalfile="$cachedir/$sid.total"
  lockdir="$cachedir/$sid.lock"
  if { [ ! -f "$totalfile" ] || [ "$tpath" -nt "$totalfile" ]; } && [ ! -d "$lockdir" ]; then
    ( python3 "$HOME/.claude/statusline-tokens.py" "$sid" "$tpath" "$cachedir" ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
fi
