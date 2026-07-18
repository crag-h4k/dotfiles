#!/usr/bin/env bash
# Back up config files that exist on disk before applying changes, so the
# previous (pre-apply) version can be restored. Runs before every chezmoi apply
# (new installs and updates alike). Backups land in
# ~/.dotfiles-backup/<timestamp>/ preserving directory structure.
#
# Scope: every chezmoi-managed file, PLUS non-managed "state" / local-addition
# files that sit in the same config directories (e.g. ~/.config/nvim/lazy-lock.json
# or a hand-added ~/.tmux/conf.d/*.conf). Git-repo externals (oh-my-zsh, tmux/zsh
# plugins) are intentionally skipped: they are re-fetchable and would balloon every
# snapshot. Only directories that hold a managed file are scanned - never $HOME
# itself, never a bare container like ~/.config - and only their direct entries, so
# unrelated files and external plugin trees (their own dirs, no managed file) are
# never reached.
#
# App-state dirs (~/.claude, ~/.codex) are excluded from the extra-state scan: they
# mix secrets, session DBs, and logs (e.g. ~/.codex/auth.json) with their few
# managed files. Those managed files are still captured by step 1 - we just do not
# sweep the surrounding runtime state into a plaintext backup.

set -euo pipefail

backup_root="$HOME/.dotfiles-backup"
backup_dir="$backup_root/$(date +%Y%m%dT%H%M%S)"
backed_up=0

printf 'dotfiles: inspecting existing configs for backup...\n'

# cp one existing regular file into the snapshot, preserving its path relative to
# $HOME. Idempotent within a run: a file already copied (e.g. a managed file also
# seen in the directory scan) is skipped.
copy_into_backup() {
    local src="$1" rel dst
    [[ -f "$src" ]] || return 0
    rel="${src#"$HOME/"}"
    dst="$backup_dir/$rel"
    [[ -e "$dst" ]] && return 0
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst"
    backed_up=$(( backed_up + 1 ))
}

# 1. Every managed file (the configs themselves).
while IFS= read -r target; do
    copy_into_backup "$target"
done < <(chezmoi managed --path-style=absolute --include=files 2>/dev/null)

# 2. Non-managed state / local-addition files colocated with a managed file (e.g.
#    ~/.config/nvim/lazy-lock.json, a hand-added ~/.tmux/conf.d/*.conf). Scan only
#    the directories that hold a managed file, non-recursively, so external plugin
#    subtrees and unrelated $HOME files are never reached. Two guards keep secrets
#    and churn out of the plaintext backup: skip the app-state dirs (~/.claude,
#    ~/.codex - see header), and skip obvious non-config junk by name.
while IFS= read -r dir; do
    [[ -z "$dir" || "$dir" == "$HOME" ]] && continue
    case "$dir" in
        "$HOME"/.claude|"$HOME"/.claude/*|"$HOME"/.codex|"$HOME"/.codex/*) continue ;;
    esac
    for f in "$dir"/*; do
        [[ -f "$f" ]] || continue
        case "${f##*/}" in
            .DS_Store|*.log|*.bak|*.bak-*|*.bak.*|*.ig|*.swp|*.swo) continue ;;
        esac
        copy_into_backup "$f"
    done
done < <(chezmoi managed --path-style=absolute --include=files 2>/dev/null \
         | while IFS= read -r t; do dirname "$t"; done | sort -u)

if (( backed_up > 0 )); then
    printf 'dotfiles: backed up %d file(s) to %s\n' "$backed_up" "$backup_dir"
else
    rm -rf "$backup_dir"
    printf 'dotfiles: no existing configs needed backup\n'
fi

# Retention: every apply makes a snapshot, so keep only the most recent $keep and
# prune the rest. Override with DOTFILES_BACKUP_KEEP. find/sort avoids a glob that
# would trip set -e / pipefail when the root has no snapshots yet.
keep=${DOTFILES_BACKUP_KEEP:-20}
if [[ -d "$backup_root" ]]; then
    find "$backup_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | sort -r | tail -n +"$(( keep + 1 ))" | while IFS= read -r old; do
        rm -rf "$old"
    done
fi
