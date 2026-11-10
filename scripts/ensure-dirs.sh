#!/usr/bin/env bash
# scripts/ensure-dirs.sh
# Create the worktrees folder and the agent workspace (with its subdirectories)
# that chezmoi resolved for this host. Called by
# home/.chezmoiscripts/run_after_02-ensure-dirs.sh.tmpl with absolute paths.
# Idempotent and cheap: an existing directory is left alone, and its mode and
# ownership are never changed.
#
# It never runs sudo and never fails an apply. When a directory cannot be created
# because its nearest existing parent is not writable (for example /opt/worktrees),
# it prints the exact privileged command for the user to run and moves on. A
# directory listed below one that could not be used is skipped quietly, so a
# missing workspace root produces one hint instead of one per subdirectory.
#
# usage: ensure-dirs.sh [-m MODE] DIR...
#   -m MODE  octal mode for directories this run creates (default 755)
set -u

warn() { printf 'dotfiles: WARNING %s\n' "$*" >&2; }

owner="${USER:-$(id -un 2>/dev/null || printf 'user')}"
mode=755

if [[ "${1:-}" == -m ]]; then
    if [[ ! "${2:-}" =~ ^0?[0-7]{3}$ ]]; then
        warn "ensure-dirs: -m needs an octal mode such as 755 or 700"
        exit 0
    fi
    mode=$2
    shift 2
fi
mode=${mode#0}

# One shell-quoted command line the user can paste, e.g. for a path with spaces.
# The single quotes are deliberate: $USER must expand in the user's own shell.
# shellcheck disable=SC2016
sudo_install_hint() {
    local quoted
    quoted=$(printf '%q' "$1")
    printf '  sudo install -d -o "$USER" -m 0%s %s\n' "$mode" "$quoted" >&2
}

# ensure_dir DIR: returns 0 when DIR is a directory this user can use afterwards.
ensure_dir() {
    local dir="$1" parent quoted

    if [[ "$dir" != /* ]]; then
        warn "skipping '$dir': directory settings must be absolute paths"
        return 1
    fi

    if [[ -d "$dir" ]]; then
        if [[ ! -w "$dir" || ! -x "$dir" ]]; then
            quoted=$(printf '%q' "$dir")
            warn "$dir exists but $owner cannot write to it; fix its ownership once with:"
            # shellcheck disable=SC2016
            printf '  sudo chown "$USER" %s\n' "$quoted" >&2
            return 1
        fi
        return 0
    fi
    if [[ -e "$dir" || -L "$dir" ]]; then
        warn "$dir exists but is not a usable directory; move it aside so dotfiles can create the directory"
        return 1
    fi

    # Walk up to the nearest existing ancestor to decide whether mkdir can work.
    parent=$(dirname "$dir")
    while [[ ! -e "$parent" && ! -L "$parent" && "$parent" != / ]]; do
        parent=$(dirname "$parent")
    done

    if [[ ! -d "$parent" ]]; then
        warn "cannot create $dir: $parent is not a directory"
        return 1
    fi
    if [[ ! -w "$parent" || ! -x "$parent" ]]; then
        warn "cannot create $dir: $parent is not writable by $owner. Create it once with:"
        sudo_install_hint "$dir"
        return 1
    fi
    # chmod rather than mkdir -m: -m applies to the leaf only, and this leaf is new.
    if mkdir -p "$dir" 2>/dev/null && chmod "$mode" "$dir" 2>/dev/null; then
        printf 'dotfiles: created %s\n' "$dir"
        return 0
    fi
    warn "could not create $dir"
    return 1
}

# Newline-separated directories that could not be used (Bash 3.2: no arrays of
# arrays, and a plain string keeps the prefix test simple).
unusable=""

below_unusable() {
    local prefix
    while IFS= read -r prefix; do
        [[ -n "$prefix" ]] || continue
        case "$1" in "$prefix"/*) return 0 ;; esac
    done <<EOF
$unusable
EOF
    return 1
}

for dir in "$@"; do
    [[ -n "$dir" ]] || continue
    below_unusable "$dir" && continue
    ensure_dir "$dir" || unusable="$unusable$dir
"
done
exit 0
