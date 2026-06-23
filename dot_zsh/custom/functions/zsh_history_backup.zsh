#!/usr/bin/env zsh
# Back up $HISTFILE, but only if the newest existing backup is older than
# ZSH_HISTORY_BACKUP_MIN_HOURS (default 6). Prunes to the most recent
# ZSH_HISTORY_BACKUP_KEEP files so the backup dir does not grow unbounded.
#
# Env:
#   ZSH_HISTORY_BACKUP_DIR       where backups live (default: ~/.zsh/zsh_history_backups)
#   ZSH_HISTORY_BACKUP_MIN_HOURS minimum gap between backups (default: 6)
#   ZSH_HISTORY_BACKUP_KEEP      how many backups to retain (default: 50)
function zsh_history_backup() {
    local backup_dir="${ZSH_HISTORY_BACKUP_DIR:-$HOME/.zsh/zsh_history_backups}"
    local min_hours=${ZSH_HISTORY_BACKUP_MIN_HOURS:-6}
    local min_secs=$(( min_hours * 3600 ))

    [[ -r "$HISTFILE" ]] || return 0
    mkdir -p "$backup_dir"

    # Newest existing backup (by mtime, survives clock skew).
    # (N) glob qualifier: expand to empty array instead of erroring when no backups exist yet.
    local newest=""
    local -a _backups=( "$backup_dir"/zsh_history_backup_*(N) )
    if (( ${#_backups} )); then
        newest=$(command ls -t "${_backups[@]}" | head -1)
    fi

    if [[ -n "$newest" && -f "$newest" ]]; then
        local now last
        now=$(date +%s)
        # GNU stat: -c %Y (Linux). BSD stat: -f %m (macOS). Try GNU first.
        last=$(stat -c %Y "$newest" 2>/dev/null || stat -f %m "$newest" 2>/dev/null)
        if [[ -n "$last" ]] && (( now - last < min_secs )); then
            return 0
        fi
    fi

    local ts
    ts=$(date +%Y-%m-%d-%H%M)
    cp -p "$HISTFILE" "$backup_dir/zsh_history_backup_${ts}"

    # Retention: keep the most recent $keep backups, prune the rest.
    # (Nom): N = expand to empty if no match, om = sort by mtime newest first.
    local keep=${ZSH_HISTORY_BACKUP_KEEP:-50}
    local -a _all=( "$backup_dir"/zsh_history_backup_*(Nom) )
    (( ${#_all} > keep )) && rm -f -- "${(@)_all[keep+1,-1]}"
}
