#!/usr/bin/env bash
# Back up all chezmoi-managed files that exist on disk before applying changes.
# Runs before every chezmoi apply (new installs and updates alike).
# Backups land in ~/.dotfiles-backup/<timestamp>/ preserving directory structure.

set -euo pipefail

backup_root="$HOME/.dotfiles-backup"
backup_dir="$backup_root/$(date +%Y%m%dT%H%M%S)"
backed_up=0

while IFS= read -r target; do
    [[ -f "$target" ]] || continue
    rel="${target#"$HOME/"}"
    dst="$backup_dir/$rel"
    mkdir -p "$(dirname "$dst")"
    cp -p "$target" "$dst"
    backed_up=$(( backed_up + 1 ))
done < <(chezmoi managed --path-style=absolute --include=files 2>/dev/null)

if (( backed_up > 0 )); then
    printf 'dotfiles: backed up %d file(s) to %s\n' "$backed_up" "$backup_dir"
else
    rm -rf "$backup_dir"
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
