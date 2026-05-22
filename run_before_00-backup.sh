#!/usr/bin/env bash
# Back up all chezmoi-managed files that exist on disk before applying changes.
# Runs before every chezmoi apply (new installs and updates alike).
# Backups land in ~/.dotfiles-backup/<timestamp>/ preserving directory structure.

set -euo pipefail

backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%dT%H%M%S)"
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
