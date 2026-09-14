#!/usr/bin/env zsh
# bash's `mapfile` / `readarray` builtin, which zsh does not ship.
#
# NOT the same thing as zsh's `zsh/mapfile` module. That module provides a
# special PARAMETER, ${mapfile[/path]}, for whole-file read/write. This is the
# bash COMMAND that slurps a stream into an array, one element per line.
#
#   mapfile -t lines < file          # array `lines`, newlines stripped
#   somecmd | mapfile -t out         # from a pipe
#   mapfile arr < file               # newlines KEPT (bash default)
#   mapfile -t -s 1 -n 10 arr < file # skip header, take 10
#   mapfile -t -d '' paths < <(find . -print0)
#
# INDEXING GOTCHA: bash arrays are 0-indexed, zsh arrays are 1-indexed. The
# first line is ${arr[1]} here, not ${arr[0]}. `-O origin` is honoured relative
# to bash's origin, so `-O 0` starts at zsh index 1. Nothing can paper over this
# without KSH_ARRAYS, which would break the rest of the shell.
#
# Supported: -d -n -O -s -t -u -C -c, default array MAPFILE, `readarray` synonym.
function mapfile() {
    emulate -L zsh
    setopt local_options no_unset extended_glob

    local delim=$'\n' callback='' opt name
    local -i tflag=0 nread=0 origin=0 skip=0 fd=0 quantum=5000
    local -i have_origin=0
    local OPTIND=1 OPTARG

    while getopts ':d:n:O:s:u:C:c:t' opt; do
        case $opt in
            (d) delim=$OPTARG ;;
            (n) nread=$OPTARG ;;
            (O) origin=$OPTARG; have_origin=1 ;;
            (s) skip=$OPTARG ;;
            (u) fd=$OPTARG ;;
            (C) callback=$OPTARG ;;
            (c) quantum=$OPTARG ;;
            (t) tflag=1 ;;
            (:) print -ru2 -- "mapfile: -$OPTARG: option requires an argument"; return 2 ;;
            (?) print -ru2 -- "mapfile: -$OPTARG: invalid option"; return 2 ;;
        esac
    done
    shift $(( OPTIND - 1 ))

    (( $# > 1 )) && { print -ru2 -- "mapfile: too many arguments"; return 2 }
    name=${1:-MAPFILE}
    # Reject anything that is not a plain identifier: the assignment below goes
    # through eval, so this is the guard that keeps it from being an injection.
    [[ $name == [A-Za-z_][A-Za-z0-9_]# ]] || {
        print -ru2 -- "mapfile: \`$name': not a valid identifier"; return 2
    }

    # bash spells NUL as -d '' ; zsh's read wants the actual character. Only the
    # first character of a longer -d argument is used, matching bash.
    [[ -z $delim ]] && delim=$'\0' || delim=${delim[1]}

    local line
    local -a buf
    local -i rc=0 seen=0 kept=0

    while :; do
        line=''
        IFS= read -r -d "$delim" -u $fd line
        rc=$?
        # rc!=0 with a non-empty line is a final chunk with no trailing delim;
        # bash keeps it, so process it then stop.
        (( rc != 0 )) && [[ -z $line ]] && break

        (( seen++ ))
        if (( seen > skip )); then
            (( tflag )) || line+=$delim
            buf+=( "$line" )
            (( kept++ ))
            if [[ -n $callback ]] && (( quantum > 0 )) && (( kept % quantum == 0 )); then
                eval "${callback} $(( origin + kept - 1 )) ${(q)line}"
            fi
            (( nread > 0 && kept >= nread )) && break
        fi

        (( rc != 0 )) && break
    done

    if (( have_origin )); then
        # -O does not clear the array; it overwrites from `origin` onward.
        local -i i=1
        for line in "${buf[@]}"; do
            eval "${name}[$(( origin + i ))]=\${buf[i]}"
            (( i++ ))
        done
    else
        set -A "$name" "${buf[@]}"
    fi

    return 0
}

# bash ships both names for the same builtin.
function readarray() { mapfile "$@" }
