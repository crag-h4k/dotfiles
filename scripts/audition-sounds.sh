#!/usr/bin/env bash
# scripts/audition-sounds.sh
# Play notification sounds in sequence, announcing each name, through the real
# playback path: this sources ~/.config/notify/lib.sh and calls notify_play, so
# the player chain (afplay -> mpg123 -> ffplay) and the volume-to-gain math are
# exactly what fires on a finished turn. Nothing here re-implements playback.
#
# Default source is the chezmoi source tree, so candidates can be auditioned
# before `chezmoi apply`. Pass --live to audition what is actually installed.
#
# Usage:
#   scripts/audition-sounds.sh                  # every sound, source tree
#   scripts/audition-sounds.sh --new            # only sounds not yet in notify.yaml
#   scripts/audition-sounds.sh --live           # what is installed under ~/.config
#   scripts/audition-sounds.sh -v 40 chime-up bell
#   scripts/audition-sounds.sh --gap 1.5 --say  # slower, with spoken names
set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE_DIR="$REPO_DIR/home"
LIB="$SOURCE_DIR/dot_config/notify/lib.sh"
NOTIFY_TMPL="$SOURCE_DIR/dot_config/notify/notify.yaml.tmpl"
LIVE_CONFIG="$HOME/.config/notify/notify.yaml"

sounds_dir="$SOURCE_DIR/dot_config/notify/sounds"
gap=1.2
volume=""
say=0
only_new=0
names=()

while [ $# -gt 0 ]; do
    case "$1" in
        --live)
            sounds_dir="$HOME/.config/notify/sounds"
            LIB="$HOME/.config/notify/lib.sh"
            ;;
        --new) only_new=1 ;;
        --say) say=1 ;;
        --gap) gap="$2"; shift ;;
        -v|--volume) volume="$2"; shift ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "audition-sounds: unknown flag $1" >&2; exit 2 ;;
        *) names+=("$1") ;;
    esac
    shift
done

[ -d "$sounds_dir" ] || { echo "audition-sounds: no sounds dir at $sounds_dir" >&2; exit 1; }
[ -f "$LIB" ] || { echo "audition-sounds: no notify lib at $LIB" >&2; exit 1; }

# Real playback path. NOTIFY_SOUNDS redirects notify_play at the chosen dir.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../home/dot_config/notify/lib.sh
. "$LIB"
export NOTIFY_SOUNDS="$sounds_dir"

# Volume: honor an explicit -v, else settings.volume from the live config, else
# the same built-in default notify_play falls back to.
if [ -z "$volume" ]; then
    if [ -f "$LIVE_CONFIG" ] && command -v yq >/dev/null 2>&1; then
        volume=$(yq -r '.settings.volume // ""' "$LIVE_CONFIG" 2>/dev/null || true)
    fi
fi
case "$volume" in ''|*[!0-9]*) volume=75 ;; esac

# Sounds already referenced by the notify config, so --new can exclude them.
assigned=""
if command -v yq >/dev/null 2>&1; then
    if [ -f "$LIVE_CONFIG" ]; then
        cfg_text=$(cat "$LIVE_CONFIG")
    elif command -v chezmoi >/dev/null 2>&1; then
        cfg_text=$(chezmoi execute-template --source "$REPO_DIR" <"$NOTIFY_TMPL" 2>/dev/null || true)
    else
        cfg_text=""
    fi
    if [ -n "$cfg_text" ]; then
        assigned=" $(printf '%s' "$cfg_text" | yq -r \
            '[(.groups // {}), (.integrations // {})] | .[] | .[] | .sound // ""' \
            2>/dev/null | grep -v '^$' | sort -u | tr '\n' ' ')"
    fi
fi

announce() {
    [ "$say" -eq 1 ] || return 0
    if command -v say >/dev/null 2>&1; then say -r 250 "$1" 2>/dev/null || true
    elif command -v spd-say >/dev/null 2>&1; then spd-say -w -r 40 "$1" 2>/dev/null || true
    elif command -v espeak >/dev/null 2>&1; then espeak -s 200 "$1" 2>/dev/null || true
    fi
}

# Build the play list.
if [ "${#names[@]}" -eq 0 ]; then
    while IFS= read -r f; do names+=("$(basename "$f")"); done < <(find "$sounds_dir" -name '*.mp3' | sort)
else
    for i in "${!names[@]}"; do
        case "${names[i]}" in *.mp3) ;; *) names[i]="${names[i]}.mp3" ;; esac
    done
fi

printf 'auditioning %s\n' "$sounds_dir"
printf 'volume %s  gap %ss%s\n\n' "$volume" "$gap" "$([ "$only_new" -eq 1 ] && printf '  (unassigned only)')"

played=0
for n in "${names[@]}"; do
    [ -f "$sounds_dir/$n" ] || { printf '  %-20s MISSING\n' "$n"; continue; }
    if [ "$only_new" -eq 1 ] && [ -n "$assigned" ]; then
        case "$assigned" in *" $n "*) continue ;; esac
    fi
    tag=""
    case "$assigned" in *" $n "*) tag="  (assigned)" ;; esac
    printf '  %-20s%s\n' "${n%.mp3}" "$tag"
    announce "${n%.mp3}"
    # notify_play is best-effort by contract and is written for callers that do
    # not run under `set -e` (interactive zsh, the AI hooks). Its internal
    # `[ "$vol" -gt 100 ] && vol=100` guard returns 1 on the common path, so call
    # it as part of an || list: that both ignores the status and suspends `set -e`
    # inside the function body.
    notify_play "$n" "$volume" || true
    played=$((played + 1))
    sleep "$gap"
done

printf '\n%s sound(s) played.\n' "$played"
