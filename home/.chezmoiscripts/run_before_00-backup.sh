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
moved=0
started=$SECONDS

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

# Move a type-conflicting target into the snapshot so chezmoi can write the managed
# dir/file/symlink in its place. Stored under a ".pre-apply" name so the moved original
# never collides with a content copy made by step 1. Warns and continues on a failed
# move: the leftover conflict would surface in apply anyway, but one odd path should not
# abort the whole backup.
move_aside() {
    local src="$1" rel dst n
    rel="${src#"$HOME/"}"
    dst="$backup_dir/$rel.pre-apply"
    if [[ -e "$dst" || -L "$dst" ]]; then
        n=1
        while [[ -e "$dst.$n" || -L "$dst.$n" ]]; do n=$(( n + 1 )); done
        dst="$dst.$n"
    fi
    mkdir -p "$(dirname "$dst")"
    if mv "$src" "$dst"; then
        moved=$(( moved + 1 ))
        printf 'dotfiles: moved conflicting %s aside to %s\n' "$src" "$dst"
    else
        printf 'dotfiles: WARNING could not move %s aside; chezmoi apply may fail on it\n' "$src" >&2
    fi
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

# 3. Move aside targets whose on-disk type conflicts with what chezmoi will write.
#    chezmoi silently overwrites a plain regular file, but hard-fails (aborting the
#    whole apply) when a target already exists as a different filesystem TYPE: a symlink
#    or file where a managed directory goes (e.g. a symlinked ~/.config/nvim from
#    LazyVim/kickstart), or a real directory where a managed file/symlink/readonly
#    external goes, or a special node (FIFO/named pipe, socket, block/char device)
#    where a managed file or symlink goes. Test -L before -e/-d, which follow symlinks
#    (-e is even false for a
#    broken symlink). Directories chezmoi also manages as directories (~/.config,
#    ~/.claude, ~/.codex, ~/.local) are left in place so their contents merge - only a
#    genuine type mismatch is moved, never a mergeable directory.

# Managed dirs (want a real dir): shallowest-first, so moving a conflicting parent
# clears its children before they are inspected.
while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if [[ -L "$t" ]] || { [[ -e "$t" && ! -d "$t" ]]; }; then
        move_aside "$t"
    fi
done < <(chezmoi managed --path-style=absolute --include=dirs 2>/dev/null | sort)

# Managed symlinks (want a symlink): a real directory OR a special node (FIFO/named
# pipe, socket, block/char device) conflicts - chezmoi cannot overwrite either in place,
# and a FIFO/socket can even hang the write. An existing regular file or symlink is
# overwritten cleanly, so leave those. Test -L first; then "exists but is not a regular
# file" catches dirs and special nodes without touching regular files or symlinks.
while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if [[ ! -L "$t" && -e "$t" && ! -f "$t" ]]; then
        move_aside "$t"
    fi
done < <(chezmoi managed --path-style=absolute --include=symlinks 2>/dev/null)

# Managed files (want a regular file): a real directory OR a special node (FIFO/named
# pipe, socket, block/char device) conflicts - e.g. a FIFO at a managed
# ~/.claude/settings.json would hang or error chezmoi when it writes that target. An
# existing regular file or symlink is overwritten cleanly (content already copied in
# step 1), so leave those. Test -L first; then "exists but is not a regular file"
# catches dirs and special nodes without touching regular files or symlinks.
while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if [[ ! -L "$t" && -e "$t" && ! -f "$t" ]]; then
        move_aside "$t"
    fi
done < <(chezmoi managed --path-style=absolute --include=files 2>/dev/null)

# Externals (git-repo dir targets like ~/.zsh/ohmyzsh, readonly file targets under
# ~/.local/share/agent-skills): a symlink is invalid for either. A real dir/file is left
# for chezmoi to handle (git pull / dirty-checkout skip, or file overwrite).
while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if [[ -L "$t" ]]; then
        move_aside "$t"
    fi
done < <(chezmoi managed --path-style=absolute --include=externals 2>/dev/null)

elapsed=$(( SECONDS - started ))
if (( backed_up > 0 || moved > 0 )); then
    printf 'dotfiles: backed up %d file(s), moved %d conflicting target(s) aside -> %s (%ss)\n' \
        "$backed_up" "$moved" "$backup_dir" "$elapsed"
else
    rm -rf "$backup_dir"
    printf 'dotfiles: no existing configs needed backup (%ss)\n' "$elapsed"
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

# chezmoi applies managed files and clones missing .chezmoiexternal.toml plugin
# repos next, interleaved. Package mode refreshes existing checkouts later. There
# is no "before externals only" hook
# (run_before scripts fire before the whole apply, not specifically before
# externals), so this is a coarse phase marker for "the next step includes
# externals"; per-file detail comes from `progress = true` in .chezmoi.toml.tmpl.
printf 'dotfiles: applying configs and fetching missing selected externals...\n'
