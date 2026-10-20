#!/usr/bin/env bash
# scripts/ensure-dirs.sh
# Create the worktrees and agent-notes directories that chezmoi resolved for this
# host. Called by home/.chezmoiscripts/run_after_02-ensure-dirs.sh.tmpl with
# absolute paths. Idempotent and cheap: an existing directory is left alone, and
# its mode and ownership are never changed.
#
# It never runs sudo and never fails an apply. When a directory cannot be created
# because its nearest existing parent is not writable (for example /opt/worktrees),
# it prints the exact privileged command for the user to run and moves on.
#
# usage: ensure-dirs.sh DIR...
set -u

warn() { printf 'dotfiles: WARNING %s\n' "$*" >&2; }

owner="${USER:-$(id -un 2>/dev/null || printf 'user')}"

# One shell-quoted command line the user can paste, e.g. for a path with spaces.
# The single quotes are deliberate: $USER must expand in the user's own shell.
# shellcheck disable=SC2016
sudo_install_hint() {
    local quoted
    quoted=$(printf '%q' "$1")
    printf '  sudo install -d -o "$USER" -m 0755 %s\n' "$quoted" >&2
}

ensure_dir() {
    local dir="$1" parent quoted

    if [[ "$dir" != /* ]]; then
        warn "skipping '$dir': directory settings must be absolute paths"
        return 0
    fi

    if [[ -d "$dir" ]]; then
        if [[ ! -w "$dir" || ! -x "$dir" ]]; then
            quoted=$(printf '%q' "$dir")
            warn "$dir exists but $owner cannot write to it; fix its ownership once with:"
            # shellcheck disable=SC2016
            printf '  sudo chown "$USER" %s\n' "$quoted" >&2
        fi
        return 0
    fi
    if [[ -e "$dir" || -L "$dir" ]]; then
        warn "$dir exists but is not a usable directory; move it aside so dotfiles can create the directory"
        return 0
    fi

    # Walk up to the nearest existing ancestor to decide whether mkdir can work.
    parent=$(dirname "$dir")
    while [[ ! -e "$parent" && ! -L "$parent" && "$parent" != / ]]; do
        parent=$(dirname "$parent")
    done

    if [[ ! -d "$parent" ]]; then
        warn "cannot create $dir: $parent is not a directory"
        return 0
    fi
    if [[ ! -w "$parent" || ! -x "$parent" ]]; then
        warn "cannot create $dir: $parent is not writable by $owner. Create it once with:"
        sudo_install_hint "$dir"
        return 0
    fi
    # chmod rather than mkdir -m: -m applies to the leaf only, and this leaf is new.
    if mkdir -p "$dir" 2>/dev/null && chmod 755 "$dir" 2>/dev/null; then
        printf 'dotfiles: created %s\n' "$dir"
    else
        warn "could not create $dir"
    fi
}

for dir in "$@"; do
    [[ -n "$dir" ]] || continue
    ensure_dir "$dir"
done
exit 0
