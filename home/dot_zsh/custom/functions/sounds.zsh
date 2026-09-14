#!/usr/bin/env zsh
# ~/.zsh/custom/functions/sounds.zsh
# Audition the notification sounds: print each name, then play it, one at a time.
# For picking which sound goes on which group in ~/.config/notify/notify.yaml.
#
# Playback is deliberately BLOCKING here, which is why this does not call
# notify_play from lib.sh. That one fires the player in a background subshell so
# a notification never delays a turn; in a loop every sound would start at once
# and you would hear mush. This resolves the same player chain (afplay, then
# mpg123, then ffplay) via lib.sh's _notify_find and waits for each to finish.
#
# Sounds already claimed by a group are tagged, since the whole point is finding
# one that is still free and distinguishable from its neighbours.

function sounds() {
    emulate -L zsh
    setopt local_options null_glob

    local dir="$HOME/.config/notify/sounds"
    local cfg="${NOTIFY_CONFIG:-$HOME/.config/notify/notify.yaml}"
    local volume=75 list_only=0 only_new=0
    local -a names

    while (( $# )); do
        case "$1" in
            -s|--source)
                # Candidates that are in the chezmoi source but not applied yet.
                # ~/dotfiles is Dane's symlink to the chezmoi source root.
                dir="$HOME/dotfiles/home/dot_config/notify/sounds"
                [[ -d $dir ]] || dir="$HOME/.local/share/chezmoi/home/dot_config/notify/sounds"
                ;;
            -n|--new)  only_new=1 ;;
            -l|--list) list_only=1 ;;
            -v|--volume) volume="$2"; shift ;;
            -h|--help)
                print -r -- 'sounds [-s] [-n] [-l] [-v 0-100] [name...]'
                print -r -- '  -s  audition the chezmoi source tree, not the installed sounds'
                print -r -- '  -n  only sounds no group claims yet'
                print -r -- '  -l  list without playing'
                print -r -- '  -v  volume 0-100 (default 75)'
                return 0 ;;
            -*) print -u2 "sounds: unknown flag $1"; return 2 ;;
            *)  names+=("$1") ;;
        esac
        shift
    done

    [[ -d $dir ]] || { print -u2 "sounds: no sound directory at $dir"; return 1 }

    # group lookup: which groups, if any, already use each file. A sound can be
    # claimed more than once (glass.mp3 is currently both opencode and
    # slow_processes), and that collision is exactly what you want to see while
    # picking, so collect every claimant rather than letting the last one win.
    local -A claimed
    if [[ -r $cfg ]] && (( $+commands[yq] )); then
        local snd grp
        while IFS=' ' read -r snd grp; do
            [[ -n $snd ]] || continue
            if [[ -n ${claimed[$snd]} ]]; then
                claimed[$snd]="${claimed[$snd]}, $grp"
            else
                claimed[$snd]="$grp"
            fi
        done < <(yq -r '[(.groups // {} | to_entries), (.integrations // {} | to_entries)] | flatten | .[]
                        | select(.value.sound != null and .value.sound != "")
                        | .value.sound + " " + .key' "$cfg" 2>/dev/null)
    fi

    local -a files
    if (( $#names )); then
        local n
        for n in $names; do
            files+=( $dir/${n%.mp3}.mp3(N) )
        done
    else
        files=( $dir/*.mp3(N) )
    fi
    (( $#files )) || { print -u2 "sounds: nothing to play in $dir"; return 1 }

    # Same resolution order lib.sh uses at notification time, so what you hear
    # here is what fires later.
    local player=""
    if ! typeset -f _notify_find >/dev/null 2>&1; then
        [[ -r ~/.config/notify/lib.sh ]] && source ~/.config/notify/lib.sh
    fi
    if typeset -f _notify_find >/dev/null 2>&1; then
        player=$(_notify_find afplay /usr/bin/afplay)
        [[ -z $player ]] && player=$(_notify_find mpg123 /opt/homebrew/bin/mpg123 /usr/bin/mpg123)
        [[ -z $player ]] && player=$(_notify_find ffplay /opt/homebrew/bin/ffplay /usr/bin/ffplay)
    else
        local p
        for p in afplay mpg123 ffplay; do
            (( $+commands[$p] )) && { player=$commands[$p]; break }
        done
    fi
    if [[ -z $player && $list_only -eq 0 ]]; then
        print -u2 "sounds: no player found (afplay, mpg123, or ffplay)"
        return 1
    fi

    local f base tag
    for f in $files; do
        base="${f:t}"
        tag=""
        [[ -n ${claimed[$base]} ]] && tag=" -> ${claimed[$base]}"
        (( only_new )) && [[ -n ${claimed[$base]} ]] && continue
        printf '%-22s%s\n' "${base:r}" "$tag"
        (( list_only )) && continue
        case "${player:t}" in
            afplay) "$player" -v "$(printf '%d.%02d' $((volume / 100)) $((volume % 100)))" "$f" 2>/dev/null ;;
            mpg123) "$player" -q --volume "$volume" "$f" 2>/dev/null ;;
            ffplay) "$player" -nodisp -autoexit -loglevel quiet -volume "$volume" "$f" 2>/dev/null ;;
        esac
    done
}

function _sounds() {
    emulate -L zsh
    local dir="$HOME/.config/notify/sounds"
    [[ -d $dir ]] || dir="$HOME/.local/share/chezmoi/home/dot_config/notify/sounds"
    compadd -- $dir/*.mp3(N:t:r)
}
compdef _sounds sounds 2>/dev/null
